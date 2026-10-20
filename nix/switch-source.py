#!/usr/bin/env python3
"""在 macOS 上通过独立 TUI 切换整机 Nix 二进制缓存。"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

NIX_CONFIG = Path("/etc/nix/nix.conf")
SOURCE_CONFIG = Path("/etc/nix/source.conf")
DAEMON_PLIST = Path("/Library/LaunchDaemons/org.nixos.nix-daemon.plist")
MIRROR = "https://mirror.sjtu.edu.cn/nix-channels/store?priority=10"
SOURCES = {
    "official": ("官方 / 原有配置", "关闭国内镜像，使用系统配置中的缓存源"),
    "sjtug": ("交大 SJTUG", "优先使用国内镜像，保留原有缓存作为备用"),
}


def source_config(source):
    text = f"# Managed by .dotfiles/nix/switch-source.py\n# source: {source}\n"
    if source == "sjtug":
        text += f"extra-substituters = {MIRROR}\n"
    return text.encode()


def read_source():
    if SOURCE_CONFIG.is_symlink():
        raise RuntimeError(f"{SOURCE_CONFIG} 是软链接，请先手动检查，避免覆盖其他配置")
    if not SOURCE_CONFIG.exists():
        return "official", None
    previous = SOURCE_CONFIG.read_bytes()
    for source in SOURCES:
        if previous == source_config(source):
            return source, previous
    raise RuntimeError(f"{SOURCE_CONFIG} 已有非本工具管理的内容，请先手动检查")


def ensure_ready():
    include = f"!include {SOURCE_CONFIG}"
    if not NIX_CONFIG.is_file() or include not in NIX_CONFIG.read_text().splitlines():
        raise RuntimeError(
            "请先运行 ./setup.py 并应用一次 nix-darwin，将全局切源配置接入系统；"
            "以后切源无需重新构建"
        )
    if not DAEMON_PLIST.is_file():
        raise RuntimeError("未找到 nix-darwin 管理的 Nix daemon，请先完成 nix-darwin 安装")


def write_config(content):
    fd, temporary = tempfile.mkstemp(prefix=".source.conf.", dir=SOURCE_CONFIG.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fchmod(stream.fileno(), 0o644)
        os.replace(temporary, SOURCE_CONFIG)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def restart_daemon():
    subprocess.run(
        ["/bin/launchctl", "kickstart", "-k", "system/org.nixos.nix-daemon"], check=True
    )


def apply_source(source):
    ensure_ready()
    _, previous = read_source()
    write_config(source_config(source))
    try:
        restart_daemon()
    except (OSError, subprocess.CalledProcessError) as exc:
        if previous is None:
            SOURCE_CONFIG.unlink()
        else:
            write_config(previous)
        try:
            restart_daemon()
        except (OSError, subprocess.CalledProcessError) as recovery:
            raise RuntimeError("源配置已恢复，但 Nix daemon 重启失败，请检查服务状态") from recovery
        raise RuntimeError("Nix daemon 重启失败，已恢复原来的源配置") from exc


def pick_source(current):
    fzf = shutil.which("fzf")
    if not fzf and Path("/run/current-system/sw/bin/fzf").is_file():
        fzf = "/run/current-system/sw/bin/fzf"
    if not fzf:
        raise RuntimeError("未找到 fzf，请先通过 nix-darwin 安装共用 CLI 软件")
    ordered = [current] + [source for source in SOURCES if source != current]
    options = "".join(
        f"{source}\t{SOURCES[source][0]}  ·  {SOURCES[source][1]}\n" for source in ordered
    )
    result = subprocess.run(
        [
            fzf,
            "--height=14",
            "--reverse",
            "--border",
            "--no-multi",
            "--no-sort",
            "--delimiter=\t",
            "--with-nth=2..",
            "--prompt=Nix 源 > ",
            f"--header=当前：{SOURCES[current][0]}\n"
            "作用于本机所有用户和 Nix daemon 的默认二进制缓存\n"
            "↑/↓ 选择 · Enter 应用并重启 daemon · Esc 取消",
        ],
        input=options,
        stdout=subprocess.PIPE,
        text=True,
    )
    if result.returncode in (1, 130):
        return None
    if result.returncode:
        raise RuntimeError(f"fzf 退出码：{result.returncode}")
    source = result.stdout.strip().split("\t", 1)[0]
    if source not in SOURCES:
        raise RuntimeError("未识别的源选项")
    return source


def main(argv=None):
    if sys.platform != "darwin":
        print("Nix 全局切源 TUI 仅支持 macOS", file=sys.stderr)
        return 1
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", choices=SOURCES, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        ensure_ready()
        if args.apply:
            if os.geteuid() != 0:
                raise RuntimeError("写入整机配置需要管理员权限，请直接运行 TUI")
            apply_source(args.apply)
            print(f"已切换到 {SOURCES[args.apply][0]}，Nix daemon 已重启")
            return 0
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            raise RuntimeError("请在交互式终端运行此 TUI")
        current, _ = read_source()
        source = pick_source(current)
        if source is None:
            print("已取消")
            return 0
        if source == current:
            print(f"当前已使用 {SOURCES[source][0]}")
            return 0
        return subprocess.run(
            ["sudo", sys.executable, str(Path(__file__).resolve()), "--apply", source]
        ).returncode
    except (OSError, RuntimeError) as exc:
        print(f"切源失败：{exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n已取消")
        return 0


if __name__ == "__main__":
    sys.exit(main())
