"""CLI entry point and plain-output diagnostic mode."""

import argparse
import json
import math
import queue
import shutil
import sys
import time

from .model import Tracker
from .source import SSHConnection, Source, remote_script


def parse_args(argv=None):
    parser = argparse.ArgumentParser(prog="q-openwrt", description="实时显示 OpenWrt 网速，使用系统 SSH，无第三方 Python 依赖。")
    parser.add_argument("host", nargs="?", help="SSH 目标或 ~/.ssh/config 别名，默认 root@192.168.1.1")
    parser.add_argument("-i", "--interface", help="默认网卡，如 pppoe-wan（默认自动识别 WAN）")
    parser.add_argument("-n", "--interval", type=float, default=1, help="采样间隔，0.2–60 秒（默认 1）")
    parser.add_argument("-p", "--port", type=int, help="SSH 端口，默认遵循 SSH 配置")
    parser.add_argument("--identity", help="SSH 私钥路径")
    parser.add_argument("--ssh-config", help="指定 SSH 配置；/dev/null 可跳过系统和用户配置")
    parser.add_argument("--batch", action="store_true", help="不弹出认证提示，仅使用 SSH 密钥或现有连接")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--demo", action="store_true", help="模拟网速，不连接路由器")
    source.add_argument("--local", action="store_true", help="读取本机 Linux 计数器，也可直接在路由器运行")
    parser.add_argument("--once", action="store_true", help="采集一次速率，以 JSON 输出后退出，便于诊断")
    parser.add_argument("--bits", action="store_true", help="默认显示 bit/s（默认显示 B/s）")
    args = parser.parse_args(argv)
    if not math.isfinite(args.interval) or not 0.2 <= args.interval <= 60:
        parser.error("--interval 必须在 0.2 到 60 秒之间")
    if args.port is not None and not 1 <= args.port <= 65535:
        parser.error("--port 必须在 1 到 65535 之间")
    if args.host and (args.host.startswith("-") or any(c.isspace() or ord(c) < 32 for c in args.host)):
        parser.error("host 必须是 SSH 主机名或 user@host，不能包含空白或选项")
    if args.host and (args.demo or args.local):
        parser.error("--demo / --local 不接受远端 host")
    args.host = args.host or "root@192.168.1.1"
    return args


def once(source, args):
    tracker = Tracker()
    deadline = time.monotonic() + max(20, args.interval * 3 + 10)
    while time.monotonic() < deadline:
        try:
            kind, value = source.events.get(timeout=0.2)
        except queue.Empty:
            continue
        if kind == "error":
            print(value, file=sys.stderr)
            return 1
        if kind != "sample":
            continue
        tracker.update(value)
        if tracker.elapsed <= 0:
            continue
        if args.interface and args.interface not in tracker.interfaces:
            print(f"找不到接口 {args.interface}；可用接口：{', '.join(tracker.interfaces)}", file=sys.stderr)
            return 1
        print(json.dumps({
            "host": "demo" if args.demo else "local" if args.local else args.host,
            "wan": tracker.wan,
            "interval_seconds": tracker.elapsed,
            "interfaces": {
                name: {"rx_bytes_per_second": item.rx, "tx_bytes_per_second": item.tx}
                for name, item in tracker.interfaces.items() if not args.interface or name == args.interface
            },
        }, indent=2))
        return 0
    print("等待网卡数据超时", file=sys.stderr)
    return 1


def main(argv=None):
    args = parse_args(argv)
    if not args.once and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        print("TUI 需要交互式终端；可使用 --once 输出 JSON。", file=sys.stderr)
        return 2
    connection = None
    source = None
    try:
        if args.demo:
            command = None
        elif args.local:
            command = ["sh", "-c", remote_script(args.interval)]
        else:
            if not shutil.which("ssh"):
                print("找不到系统 ssh，请先安装 OpenSSH 客户端。", file=sys.stderr)
                return 2
            connection = SSHConnection(args.host, args.port, args.identity, args.ssh_config)
            if not args.batch and not connection.authenticate():
                print("SSH 登录失败，请检查地址、凭据和主机密钥提示。", file=sys.stderr)
                return 1
            command = connection.command(args.interval)
        source = Source(command, args.interval, args.demo)
        source.start()
        if args.once:
            return once(source, args)
        from .ui import run
        run(source, args)
        return 0
    except KeyboardInterrupt:
        return 130
    except (OSError, RuntimeError) as error:
        print(f"启动失败：{error}", file=sys.stderr)
        return 1
    finally:
        if source:
            source.close()
        if connection:
            connection.close()
