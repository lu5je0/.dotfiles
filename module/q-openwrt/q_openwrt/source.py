"""A single long-lived SSH connection streams read-only samples."""

import math
import os
from pathlib import Path
import queue
import random
import selectors
import signal
import shlex
import subprocess
import sys
import tempfile
import threading
import time

from .model import Counter, Sample, StreamParser


def remote_script(interval: float) -> str:
    # Only a validated number is substituted into this POSIX/BusyBox script.
    if not math.isfinite(interval) or not 0.2 <= interval <= 60:
        raise ValueError("interval must be between 0.2 and 60 seconds")
    if float(interval).is_integer():
        pause = f"pause() {{ sleep {interval:g}; }}"
    else:
        pause = f"""if sleep 0.001 2>/dev/null; then
    pause() {{ sleep {interval:g}; }}
elif command -v usleep >/dev/null 2>&1; then
    pause() {{ usleep {round(interval * 1000000)}; }}
else
    pause() {{ sleep {math.ceil(interval)}; }}
fi"""
    return f"""export LC_ALL=C
{pause}
while :; do
    printf '@@WAN\n'
    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface dump 2>/dev/null || :
    fi
    printf '\n@@WAN_END\n'
    read -r uptime rest < /proc/uptime || exit 1
    printf '@@SAMPLE %s\n' "$uptime"
    cat /proc/net/dev || exit 1
    printf '@@END\n'
    pause || exit 1
done
"""


class SSHConnection:
    def __init__(self, host: str, port: int, identity: str | None, config: str | None):
        # Passwords stay with OpenSSH's terminal prompt, never this process.
        self.host = host
        self.directory = tempfile.TemporaryDirectory(prefix="owrt-")
        self.socket = str(Path(self.directory.name) / "ssh")
        self.base = ["ssh", "-T"]
        if config:
            self.base += ["-F", config]
        self.base += [
            "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2", "-o", "LogLevel=ERROR",
            "-o", f"ControlPath={self.socket}",
        ]
        if port:
            self.base += ["-p", str(port)]
        if identity:
            self.base += ["-i", identity]

    def authenticate(self) -> bool:
        print(f"Connecting to {self.host} (OpenSSH may ask for your password / host key)...", file=sys.stderr, flush=True)
        result = subprocess.run(
            self.base + ["-o", "ControlMaster=auto", "-o", "ControlPersist=60", self.host, "true"]
        )
        return result.returncode == 0

    def command(self, interval: float) -> list[str]:
        return self.base + ["-o", "BatchMode=yes", self.host, "sh -c " + shlex.quote(remote_script(interval))]

    def close(self):
        try:
            subprocess.run(self.base + ["-O", "exit", self.host], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            pass
        self.directory.cleanup()


class Source:
    def __init__(self, command: list[str] | None, interval: float, demo: bool = False):
        self.command = command
        self.interval = interval
        self.demo = demo
        self.events: queue.Queue = queue.Queue(maxsize=512)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.process = None

    def emit(self, kind: str, value):
        while not self.stop.is_set():
            try:
                self.events.put((kind, value), timeout=0.2)
                return
            except queue.Full:
                continue

    def start(self):
        self.thread.start()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=3)

    def run(self):
        if self.demo:
            self.run_demo()
            return
        delay = 1
        while not self.stop.is_set():
            self.emit("status", "Connecting...")
            received = False
            try:
                with tempfile.TemporaryFile() as errors:
                    process = subprocess.Popen(self.command, stdout=subprocess.PIPE, stderr=errors,
                                               stdin=subprocess.DEVNULL, bufsize=0, start_new_session=True)
                    self.process = process
                    try:
                        parser = StreamParser()
                        buffer = b""
                        last_frame = time.monotonic()
                        with selectors.DefaultSelector() as selector:
                            selector.register(process.stdout, selectors.EVENT_READ)
                            while not self.stop.is_set():
                                if time.monotonic() - last_frame > max(12, self.interval * 4 + 5):
                                    raise TimeoutError("No samples received; connection stalled")
                                if not selector.select(timeout=0.2):
                                    continue
                                chunk = process.stdout.read(65536)
                                if not chunk:
                                    break
                                buffer += chunk
                                if len(buffer) > 2 * 1024 * 1024:
                                    raise ValueError("Router sent an oversized frame")
                                while b"\n" in buffer:
                                    line, buffer = buffer.split(b"\n", 1)
                                    sample = parser.feed(line.decode("utf-8", errors="replace"))
                                    if sample:
                                        self.emit("sample", sample)
                                        last_frame = time.monotonic()
                                        received, delay = True, 1
                    finally:
                        if process.poll() is None:
                            try:
                                os.killpg(process.pid, signal.SIGTERM)
                            except ProcessLookupError:
                                pass
                        try:
                            process.wait(timeout=1)
                        except subprocess.TimeoutExpired:
                            try:
                                os.killpg(process.pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            process.wait()
                        process.stdout.close()
                        self.process = None
                    errors.seek(0, 2)
                    size = errors.tell()
                    errors.seek(max(0, size - 1600))
                    message = errors.read().decode("utf-8", errors="replace").strip()
                    self.emit("error", message or ("Connection closed" if received else "No counters received"))
            except (OSError, ValueError, TimeoutError) as error:
                self.emit("error", str(error))
            if not self.stop.is_set():
                self.emit("status", f"Reconnecting in {delay}s (password login may require restarting)")
                self.stop.wait(delay)
                delay = min(delay * 2, 15)

    def run_demo(self):
        rng = random.Random(42)
        counts = {name: Counter(0, 0) for name in ("pppoe-wan", "eth1", "br-lan", "lo")}
        started = time.monotonic()
        self.emit("status", "DEMO / simulated traffic")
        while not self.stop.is_set():
            elapsed = time.monotonic() - started
            rx = (8 + 6 * math.sin(elapsed / 8) + rng.random() * 3) * 1024 * 1024
            tx = (1 + 0.7 * math.sin(elapsed / 5) + rng.random()) * 1024 * 1024
            for name, prior in counts.items():
                down, up = (tx, rx) if name == "br-lan" else (rx, tx)
                factor = 0.001 if name == "lo" else 1
                counts[name] = Counter(prior.rx + int(down * self.interval * factor),
                                       prior.tx + int(up * self.interval * factor))
            self.emit("sample", Sample(elapsed, dict(counts), ("pppoe-wan",)))
            self.stop.wait(self.interval)
