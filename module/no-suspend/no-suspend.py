#!/usr/bin/env python3
import argparse
from datetime import datetime
import fcntl
import math
import os
from pathlib import Path
import re
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid

from power import START_TIMEOUT, inhibit, wait_ready


SCRIPT = Path(__file__).resolve()
CLOCK = getattr(time, "CLOCK_BOOTTIME", time.CLOCK_MONOTONIC)


def parse_duration(value):
    if re.fullmatch(r"(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?", value) and value:
        units = {"h": 3600, "m": 60, "s": 1}
        seconds = sum(
            int(number) * units[unit] for number, unit in re.findall(r"([0-9]+)([hms])", value)
        )
        if seconds > 0:
            try:
                datetime.fromtimestamp(time.time() + seconds)
            except (OverflowError, OSError, ValueError):
                pass
            else:
                return seconds
    raise argparse.ArgumentTypeError("expected a positive duration like 30s, 15m, 2h, or 1h30m")


def runtime_dir():
    base = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    name = f"no-suspend-{os.getuid()}"
    directory = base / name
    if len(os.fsencode(directory / "000000000000.sock")) >= 104:
        directory = Path("/tmp") / name
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError(f"unsafe runtime directory: {directory}")
    return directory


def request(path, action):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(15)
        try:
            client.connect(os.fspath(path))
        except (FileNotFoundError, ConnectionRefusedError):
            path.unlink(missing_ok=True)
            return None
        try:
            client.sendall(action)
            with client.makefile("rb") as reply:
                response = reply.readline().decode().strip()
        except (BrokenPipeError, ConnectionResetError):
            return None
        if response.startswith("error "):
            raise RuntimeError(response[6:])
        return float(response) if response else None


def serve_timer(path, seconds):
    cancel = None
    bound = False
    try:
        with inhibit(f"no-suspend-{path.stem}") as check:
            deadline = time.clock_gettime(CLOCK) + seconds
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(os.fspath(path))
                bound = True
                server.listen()
                print("ready", flush=True)
                while (remaining := deadline - time.clock_gettime(CLOCK)) > 0:
                    server.settimeout(min(remaining, 5))
                    try:
                        connection, _ = server.accept()
                    except socket.timeout:
                        check(running_only=True)
                        continue
                    connection.settimeout(2)
                    try:
                        action = connection.recv(1)
                        if action == b"c":
                            # Acknowledge cancellation after releasing the platform inhibitor.
                            cancel = connection
                            break
                        if action == b"s":
                            try:
                                check()
                                remaining = max(0, deadline - time.clock_gettime(CLOCK))
                                connection.sendall(f"{time.time() + remaining}\n".encode())
                            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                                connection.sendall(f"error {error}\n".encode())
                    except OSError:
                        pass
                    finally:
                        if connection is not cancel:
                            connection.close()
    finally:
        if bound:
            path.unlink(missing_ok=True)
        if cancel is not None:
            cancel.close()


def show_status(expires):
    remaining = math.ceil(expires - time.time()) if expires is not None else 0
    if remaining <= 0:
        print("Idle suspend inhibition timer is off.")
        return
    hours, remainder = divmod(remaining, 3600)
    minutes, seconds = divmod(remainder, 60)
    deadline = datetime.fromtimestamp(expires).astimezone().isoformat(sep=" ", timespec="seconds")
    print(f"Idle suspend inhibition is on until {deadline} ({hours:02d}:{minutes:02d}:{seconds:02d} remaining).")


def latest_timer(paths):
    for path in paths:
        expires = request(path, b"s")
        if expires is not None and expires > time.time():
            return expires
    return None


def start_timer(directory, previous, seconds):
    path = directory / f"{uuid.uuid4().hex[:12]}.sock"
    timer = subprocess.Popen(
        [sys.executable, "-B", SCRIPT, "_timer", path, str(seconds)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        wait_ready(timer, START_TIMEOUT + 5, "timer")
        expires = request(path, b"s")
    except BaseException:
        try:
            request(path, b"c")
        except (OSError, RuntimeError):
            pass
        if timer.poll() is None:
            timer.terminate()
        timer.wait()
        path.unlink(missing_ok=True)
        raise
    finally:
        timer.stdout.close()

    if expires is not None and expires > time.time():
        for old_path in previous:
            request(old_path, b"c")
        show_status(expires)
    else:
        show_status(latest_timer(previous))


def run_command(args):
    with inhibit(f"no-suspend-command-{uuid.uuid4().hex[:12]}"):
        # Job control delivers Ctrl-C to the command's foreground process group.
        signal.signal(signal.SIGINT, lambda *_: None)
        try:
            status = subprocess.call(args)
        except FileNotFoundError:
            print(f"no-suspend: command not found: {args[0]}", file=sys.stderr)
            return 127
        except PermissionError:
            print(f"no-suspend: cannot execute: {args[0]}", file=sys.stderr)
            return 126
    return status if status >= 0 else 128 - status


def main(args):
    parser = argparse.ArgumentParser(
        prog="no-suspend",
        description="Temporarily prevent idle suspend on Linux, WSL, or macOS.",
        epilog="Use no-suspend -- COMMAND [ARG ...] to inhibit idle suspend while a foreground command runs.",
        allow_abbrev=False,
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("-t", "--time", type=parse_duration, metavar="DURATION", help="set a timer, e.g. 2h or 1h30m")
    mode.add_argument("--status", action="store_true", help="show the timer (default)")
    mode.add_argument("--cancel", action="store_true", help="cancel the timer")

    if args[:1] == ["--"]:
        if len(args) == 1:
            parser.error("-- requires a command")
        return run_command(args[1:])

    options = parser.parse_args(args)
    directory = runtime_dir()
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Timers can expire and remove their sockets at any time.
        paths = []
        for path in directory.glob("*.sock"):
            if re.fullmatch(r"[0-9a-f]{12}\.sock", path.name):
                try:
                    paths.append((path.stat().st_mtime_ns, path))
                except FileNotFoundError:
                    pass
        previous = [path for _, path in sorted(paths, reverse=True)]
        if options.time is not None:
            start_timer(directory, previous, options.time)
        elif options.cancel:
            for path in previous:
                request(path, b"c")
            show_status(None)
        else:
            show_status(latest_timer(previous))
    return 0


if __name__ == "__main__":
    try:
        args = sys.argv[1:]
        if args == ["_hold"]:
            print("ready", flush=True)
            sys.stdin.buffer.read(1)
        elif args[:1] == ["_timer"] and len(args) == 3:
            serve_timer(Path(args[1]), int(args[2]))
        else:
            sys.exit(main(args))
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"no-suspend: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
