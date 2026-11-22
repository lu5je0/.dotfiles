import base64
from contextlib import contextmanager
import ctypes
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import time


START_TIMEOUT = 15
GNOME_SESSION = "org.gnome.SessionManager"
KDE_POLICY = "org.kde.Solid.PowerManagement.PolicyAgent"
KDE_POLICY_PATH = "/org/kde/Solid/PowerManagement/PolicyAgent"
WINDOWS_POWERSHELL = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
REASON = "Prevent idle suspend"


def checked_output(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"{args[0]} exited with status {result.returncode}")
    return result.stdout


def bus_call(scope, service, path, interface, method, *args):
    output = checked_output([
        "busctl", scope, "--timeout=4s", "--json=short", "--auto-start=no", "call",
        service, path, interface, method, *args,
    ])
    return json.loads(output)["data"][0]


def desktop_session():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower().split(":")
    sessions = {"gnome": GNOME_SESSION, "kde": KDE_POLICY}
    expected = next((name for name in desktop if name in sessions), None)
    if expected is None and "plasma" in desktop:
        expected = "kde"
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    if not (expected or os.environ.get("DBUS_SESSION_BUS_ADDRESS") or (runtime / "bus").exists()):
        return None

    for name in [expected] if expected else sessions:
        if bus_call(
            "--user", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "NameHasOwner", "s", sessions[name],
        ):
            return name
    if expected:
        raise RuntimeError(f"the {expected.upper()} power management service is unavailable")
    return None


def linux_command(app_id, gnome):
    args = [
        "systemd-inhibit", "--no-ask-password", "--what=idle", "--mode=block",
        "--who=no-suspend", f"--why={REASON}", "--",
    ]
    if gnome:
        args.extend(["gnome-session-inhibit", "--app-id", app_id, "--reason", REASON, "--inhibit", "suspend"])
    return args + [sys.executable, "-B", Path(__file__).with_name("no-suspend.py"), "_hold"]


def check_linux(pid, app_id, gnome):
    inhibitors = bus_call(
        "--system", "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "ListInhibitors",
    )
    if not any(
        who == "no-suspend" and mode == "block" and uid == os.getuid() and owner == pid and "idle" in what.split(":")
        for what, who, _why, mode, uid, owner in inhibitors
    ):
        raise RuntimeError("the logind idle inhibitor is missing")
    if gnome:
        output = checked_output(["gnome-session-inhibit", "--list"])
        if not any(line.startswith(f"{app_id}: ") for line in output.splitlines()):
            raise RuntimeError("the GNOME suspend inhibitor is missing")
    elif (desktop := desktop_session()):
        raise RuntimeError(f"{desktop.upper()} started after the current inhibitor; set it again")


@contextmanager
def inhibit_kde(app_id):
    try:
        library = ctypes.CDLL("libsystemd.so.0")
    except OSError:
        # On NixOS the library is next to the resolved systemd executable in the store.
        busctl = shutil.which("busctl")
        if busctl is None:
            raise
        systemd = Path(busctl).resolve().parent.parent
        library = ctypes.CDLL(os.fspath(systemd / "lib" / "libsystemd.so.0"))

    pointer = ctypes.c_void_p
    string = ctypes.c_char_p
    library.sd_bus_open_user.argtypes = [ctypes.POINTER(pointer)]
    library.sd_bus_close_unref.argtypes = [pointer]
    library.sd_bus_close_unref.restype = pointer
    library.sd_bus_set_method_call_timeout.argtypes = [pointer, ctypes.c_uint64]
    library.sd_bus_call_method.argtypes = [pointer, string, string, string, string, pointer, pointer, string]

    bus = pointer()
    result = library.sd_bus_open_user(ctypes.byref(bus))
    if result < 0:
        raise RuntimeError(f"cannot open the KDE session bus: {os.strerror(-result)}")

    def active():
        inhibitors = bus_call("--user", KDE_POLICY, KDE_POLICY_PATH, KDE_POLICY, "ListInhibitions")
        return [app_id, REASON] in inhibitors

    def check(running_only=False):
        if not running_only and not active():
            raise RuntimeError("the KDE PowerDevil suspend inhibitor is missing")

    try:
        library.sd_bus_set_method_call_timeout(bus, 4_000_000)
        # PowerDevil ties the inhibitor to this connection. Policy 1 is InterruptSession.
        result = library.sd_bus_call_method(
            bus, KDE_POLICY.encode(), KDE_POLICY_PATH.encode(), KDE_POLICY.encode(),
            b"AddInhibition", None, None, b"uss", ctypes.c_uint(1), app_id.encode(), REASON.encode(),
        )
        if result < 0:
            raise RuntimeError(f"cannot request the KDE PowerDevil inhibitor: {os.strerror(-result)}")

        # PowerDevil normally waits five seconds before applying a request.
        deadline = time.monotonic() + 8
        while not active():
            if time.monotonic() >= deadline:
                raise RuntimeError("KDE PowerDevil did not activate the suspend inhibitor")
            time.sleep(0.2)
        yield check
    finally:
        library.sd_bus_close_unref(bus)


def check_macos(pid):
    output = checked_output(["/usr/bin/pmset", "-g", "assertions"])
    if not re.search(rf"^\s*pid {pid}\(caffeinate\):[^\n]*\bPreventUserIdleSystemSleep\b", output, re.MULTILINE):
        raise RuntimeError("the macOS idle sleep assertion is missing")


def windows_command():
    powershell = shutil.which("powershell.exe")
    if powershell is None and os.access(WINDOWS_POWERSHELL, os.X_OK):
        powershell = WINDOWS_POWERSHELL
    if powershell is None:
        raise RuntimeError("powershell.exe is required for WSL power management")
    script = Path(__file__).with_name("hold-windows.ps1").read_text(encoding="utf-8")
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    return [powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]


def platform():
    if sys.platform == "darwin":
        return "macos"
    if sys.platform == "linux":
        if (
            "microsoft" in os.uname().release.lower()
            or os.environ.get("WSL_INTEROP") or os.environ.get("WSL_DISTRO_NAME")
        ):
            return "wsl"
        if not os.environ.get("TERMUX_VERSION"):
            return "linux"
    raise RuntimeError("requires Linux with systemd-logind, WSL, or macOS")


def wait_ready(process, timeout, name):
    deadline = time.monotonic() + timeout
    output = bytearray()
    while (remaining := deadline - time.monotonic()) > 0:
        if not select.select([process.stdout], [], [], remaining)[0]:
            break
        data = os.read(process.stdout.fileno(), 4096)
        if not data:
            break
        output.extend(data)
        if b"ready" in output.splitlines():
            return
    detail = output.decode(errors="replace").strip().removeprefix("no-suspend: ")
    raise RuntimeError(detail or f"{name} failed to become ready")


def stop_holder(holder, wait_for_eof):
    if holder.stdin is not None:
        holder.stdin.close()
    try:
        if wait_for_eof:
            holder.wait(timeout=2)
        elif holder.poll() is None:
            holder.terminate()
            holder.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(holder.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        holder.wait()


@contextmanager
def inhibit(app_id):
    system = platform()
    desktop = desktop_session() if system == "linux" else None
    if desktop == "kde":
        # PowerDevil maps a logind idle lock to a display power inhibitor.
        with inhibit_kde(app_id) as check:
            yield check
        return

    gnome = desktop == "gnome"
    if system == "macos":
        args = ["/usr/bin/caffeinate", "-i", "-w", str(os.getpid())]
    elif system == "wsl":
        args = windows_command()
    else:
        args = linux_command(app_id, gnome)

    with subprocess.Popen(
        args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
    ) as holder:
        def check(running_only=False):
            if holder.poll() is not None:
                raise RuntimeError("the power inhibitor exited")
            if not running_only:
                if system == "macos":
                    check_macos(holder.pid)
                elif system == "linux":
                    check_linux(holder.pid, app_id, gnome)

        try:
            if system == "macos":
                deadline = time.monotonic() + START_TIMEOUT
                while True:
                    try:
                        check()
                        break
                    except RuntimeError:
                        if holder.poll() is not None or time.monotonic() >= deadline:
                            raise
                        time.sleep(0.05)
            else:
                wait_ready(holder, START_TIMEOUT, "power inhibitor")
                check()
            yield check
        finally:
            stop_holder(holder, wait_for_eof=system != "macos")
