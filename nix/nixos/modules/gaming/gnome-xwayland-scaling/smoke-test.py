#!/usr/bin/env python3
"""在独立 D-Bus 会话中测试 Mutter；需要可用的 EGL render node。"""

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def wait_for(check, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {description}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--settings-daemon", type=Path)
    parser.add_argument("--x11-library", type=Path)
    parser.add_argument("--sdl-library", type=Path)
    parser.add_argument("--gtk-library", type=Path)
    parser.add_argument("--legacy-content-scale", action="store_true")
    parser.add_argument("--isolated", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    package = args.package.resolve()
    if args.settings_daemon and not (args.x11_library and args.sdl_library):
        parser.error("DPI tests require --x11-library and --sdl-library")
    if args.gtk_library and not args.settings_daemon:
        parser.error("GTK tests require --settings-daemon")
    tools = ["gsettings", "xrandr", "glxgears", "xwininfo"]
    if args.settings_daemon:
        tools.append("xrdb")
    for tool in tools:
        if not shutil.which(tool):
            raise SystemExit(f"Missing executable: {tool}")

    # 每次显式使用独立 bus，防止 gdctl 修改用户当前桌面。
    if not args.isolated:
        subprocess.run(
            ["dbus-run-session", "--", sys.executable, __file__, *sys.argv[1:], "--isolated"],
            check=True,
        )
        return

    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        raise SystemExit("The isolated D-Bus session was not initialized")

    with tempfile.TemporaryDirectory(prefix="mutter-native-resolution-") as directory:
        root = Path(directory)
        (root / "run").mkdir(mode=0o700)
        (root / "config").mkdir()
        env = os.environ.copy()
        env.update(
            XDG_RUNTIME_DIR=str(root / "run"),
            XDG_CONFIG_HOME=str(root / "config"),
            GSETTINGS_BACKEND="keyfile",
            GSETTINGS_SCHEMA_DIR=str(next(package.glob("share/gsettings-schemas/*/glib-2.0/schemas"))),
            GIO_USE_VFS="local",
            SDL_VIDEO_DRIVER="x11",
            GDK_BACKEND="x11",
        )
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "GNOME_SETUP_DISPLAY",
                    "GDK_SCALE", "GDK_DPI_SCALE", "GTK_MODULES", "SDL_VIDEO_X11_SCALING_FACTOR"):
            env.pop(key, None)

        def run(*args):
            result = subprocess.run(
                args, env=env, capture_output=True, text=True, timeout=15
            )
            if result.returncode:
                raise RuntimeError(f"{args}:\n{result.stdout}{result.stderr}")
            return result.stdout

        def setting(key, value):
            run("gsettings", "set", "org.gnome.mutter.wayland", key, value)

        def configure(scale, second_scale=None, placement="--right-of"):
            args = [
                str(package / "bin/gdctl"), "set", "--layout-mode", "logical",
                "--logical-monitor", "--primary", "--scale", str(scale),
                "--monitor", "Meta-0", "--mode", "3840x2160@60.000",
            ]
            if second_scale is not None:
                args += [
                    "--logical-monitor", "--scale", str(second_scale), placement, "Meta-0",
                    "--monitor", "Meta-1", "--mode", "3840x2160@60.000",
                ]
            run(*args)

        def resolution():
            output = run("xrandr", "--current")
            return tuple(map(int, re.search(r"current (\d+) x (\d+)", output).groups()))

        def expect_resolution(expected, label):
            wait_for(lambda: resolution() == expected, label)
            print(f"{label}: {expected[0]}x{expected[1]}", flush=True)

        def expect_outputs(expected):
            def ready():
                matches = re.findall(
                    r"^\S+ connected(?: primary)? (\d+)x(\d+)([+-]\d+)([+-]\d+)",
                    run("xrandr", "--current"), re.MULTILINE,
                )
                actual = sorted((int(x), int(y), int(w), int(h)) for w, h, x, y in matches)
                return actual == sorted(expected)

            wait_for(ready, f"X11 output geometries={expected}")
            print(f"  X11 outputs (x, y, width, height): {expected}", flush=True)

        def expect_dpi(scale, ui_scale, text_scale=1):
            if not args.settings_daemon:
                return
            if args.legacy_content_scale:
                scale = ui_scale
            window_scale = max(1, int(scale + 0.000001))
            absolute_dpi = int(96 * scale * text_scale * 1024 + 0.5)
            dpi = int(96 * scale * text_scale + 0.5)

            def resource_ready():
                match = re.search(r"^Xft\.dpi:\s*(\d+)$", run("xrdb", "-query"), re.MULTILINE)
                return match and int(match.group(1)) == dpi

            wait_for(resource_ready, f"Xft.dpi={dpi}")
            expected = {
                "Gdk/WindowScalingFactor": window_scale,
                "Gdk/UnscaledDPI": absolute_dpi // window_scale,
                "Xft/DPI": absolute_dpi,
                "Gtk/CursorThemeSize": int(24 * scale + 0.5),
            }

            def probe_ready():
                result = json.loads(run(
                    sys.executable, str(Path(__file__).with_name("dpi-probe.py")),
                    str(args.x11_library), str(args.sdl_library),
                    *([str(args.gtk_library)] if args.gtk_library else []),
                ))
                return result if result["xsettings"] == expected else None

            result = wait_for(probe_ready, f"GTK XSettings={expected}")
            assert math.isclose(result["sdl_scale"], dpi / 96, abs_tol=0.001), result
            if args.gtk_library:
                assert result["gtk"]["window_scale"] == window_scale, result
                assert math.isclose(result["gtk"]["content_scale"], scale * text_scale, abs_tol=0.001), result
                print(f"  GTK3: {result['gtk']}", flush=True)
            print(f"  DPI: {dpi}; SDL scale: {result['sdl_scale']:.4f}; GTK scale: {window_scale}", flush=True)

        def fullscreen(geometry=(0, 0, 3840, 2160)):
            x, y, width, height = geometry
            if not args.x11_library and len(re.findall(r"^\S+ connected ", run("xrandr", "--current"), re.MULTILINE)) > 1:
                print("  Skipping targeted multi-monitor fullscreen: provide --x11-library", flush=True)
                return
            command = ["glxgears", "-geometry", f"640x480+{x + 100}+{y + 100}"]
            if not args.x11_library:
                command.append("-fullscreen")
            gears = subprocess.Popen(
                command, env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            try:
                if args.x11_library:
                    def mapped():
                        return re.search(r'(0x[0-9a-f]+) "glxgears"', run("xwininfo", "-root", "-tree"))

                    window = wait_for(mapped, "GLX window initialization").group(1)
                    run(sys.executable, str(Path(__file__).with_name("dpi-probe.py")),
                        str(args.x11_library), "--fullscreen-window", window, str(x + 100), str(y + 100))

                def ready():
                    if gears.poll() is not None:
                        raise AssertionError("glxgears exited before drawing")
                    tree = run("xwininfo", "-root", "-tree")
                    return re.search(rf'"glxgears".*\s{width}x{height}\+{x}\+{y}', tree)

                wait_for(ready, f"GLX fullscreen geometry={geometry}")
                print(f"  GLX fullscreen window: {width}x{height}+{x}+{y}", flush=True)
            except BaseException:
                print(run("xwininfo", "-root", "-tree"), file=sys.stderr)
                raise
            finally:
                gears.terminate()
                try:
                    gears.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    gears.kill()
                    gears.wait()

        log_path = root / "mutter.log"
        with log_path.open("w") as log:
            settings_daemon = None
            compositor = subprocess.Popen(
                [
                    str(package / "bin/mutter"), "--headless", "--wayland",
                    "--wayland-display=native-resolution-test",
                    "--virtual-monitor=3840x2160@60",
                    "--virtual-monitor=3840x2160@60",
                ],
                env=env, stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                def started():
                    if compositor.poll() is not None:
                        raise RuntimeError("Mutter exited before initialization")
                    return re.search(r"Using public X11 display ([^,]+),", log_path.read_text())

                display = wait_for(started, "Mutter initialization")
                env["DISPLAY"] = display.group(1)
                env["XAUTHORITY"] = str(next((root / "run").glob(".mutter-Xwaylandauth.*")))
                configure(5 / 3)
                expect_resolution((4608, 2592), "default, single monitor, 166.7%")
                if args.settings_daemon:
                    settings_daemon = subprocess.Popen(
                        [str(args.settings_daemon.resolve() / "libexec/gsd-xsettings")],
                        env=env, stdout=log, stderr=subprocess.STDOUT,
                    )
                    expect_dpi(2, 2)

                setting("xwayland-native-resolution", "true")
                for scale in (1, 1.25, 1.5, 5 / 3, 2, 2.5):
                    configure(scale)
                    expect_resolution((3840, 2160), f"enabled, scale {scale:g}")
                    expect_dpi(scale, math.ceil(scale))
                    fullscreen()

                configure(5 / 3)
                expect_dpi(5 / 3, 2)
                if args.settings_daemon:
                    run("gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "1.25")
                    expect_dpi(5 / 3, 2, text_scale=1.25)
                    run("gsettings", "reset", "org.gnome.desktop.interface", "text-scaling-factor")
                    expect_dpi(5 / 3, 2)
                setting("xwayland-scaling-factor", "2.0")
                expect_resolution((4608, 2592), "explicit scaling override")
                expect_dpi(2, 2)
                setting("xwayland-scaling-factor", "0.0")
                expect_resolution((3840, 2160), "automatic scaling restored")
                expect_dpi(5 / 3, 2)

                configure(5 / 3, second_scale=1)
                expect_resolution((10240, 3600), "dual 4K, primary 166.7%, secondary 100%")
                expect_outputs([(0, 0, 3840, 2160), (3840, 0, 6400, 3600)])
                expect_dpi(5 / 3, 2)
                fullscreen()
                fullscreen((3840, 0, 6400, 3600))

                configure(5 / 3, second_scale=5 / 3)
                expect_resolution((7680, 2160), "dual 4K, both 166.7%")
                expect_outputs([(0, 0, 3840, 2160), (3840, 0, 3840, 2160)])
                expect_dpi(5 / 3, 2)
                fullscreen((3840, 0, 3840, 2160))

                configure(1, second_scale=1.5)
                expect_resolution((9600, 3240), "dual 4K, primary 100%, secondary 150%")
                expect_outputs([(0, 0, 5760, 3240), (5760, 0, 3840, 2160)])
                expect_dpi(1.5, 2)
                fullscreen((0, 0, 5760, 3240))
                fullscreen((5760, 0, 3840, 2160))

                configure(5 / 3, second_scale=1, placement="--below")
                expect_resolution((6400, 5760), "dual 4K, 166.7% above 100%")
                expect_outputs([(0, 0, 3840, 2160), (0, 2160, 6400, 3600)])
                expect_dpi(5 / 3, 2)
                fullscreen((0, 2160, 6400, 3600))

                setting("xwayland-scaling-factor", "2.0")
                configure(5 / 3, second_scale=1)
                expect_resolution((12288, 4320), "dual 4K, explicit integer override")
                expect_dpi(2, 2)
                setting("xwayland-scaling-factor", "0.0")
                expect_resolution((10240, 3600), "dual 4K, automatic scaling restored")
                expect_dpi(5 / 3, 2)
                setting("xwayland-native-resolution", "false")
                expect_resolution((12288, 4320), "dual 4K, disabled upstream behavior")
                expect_dpi(2, 2)
                setting("xwayland-native-resolution", "true")
                expect_resolution((10240, 3600), "dual 4K, enabled again")
                expect_dpi(5 / 3, 2)

                configure(5 / 3)
                expect_resolution((3840, 2160), "single monitor restored")
                expect_dpi(5 / 3, 2)
                setting("xwayland-native-resolution", "false")
                expect_resolution((4608, 2592), "disabled, upstream behavior restored")
                expect_dpi(2, 2)
            except BaseException:
                print(log_path.read_text(), file=sys.stderr)
                raise
            finally:
                if settings_daemon:
                    settings_daemon.terminate()
                    try:
                        settings_daemon.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        settings_daemon.kill()
                        settings_daemon.wait()
                compositor.terminate()
                try:
                    compositor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()


if __name__ == "__main__":
    main()
