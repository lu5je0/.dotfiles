"""Parse Linux counters and calculate rates using the router's clock."""

from collections import deque
from dataclasses import dataclass, field
import json
import math


@dataclass(frozen=True)
class Counter:
    rx: int
    tx: int


@dataclass(frozen=True)
class Sample:
    uptime: float
    counters: dict[str, Counter]
    wan: tuple[str, ...] = ()


def parse_netdev(text: str) -> dict[str, Counter]:
    result = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        name, values = line.rsplit(":", 1)
        fields = values.split()
        try:
            if len(fields) != 16:
                continue
            rx, tx = int(fields[0]), int(fields[8])
            if min(rx, tx) >= 0 and name.strip():
                result[name.strip()] = Counter(rx, tx)
        except ValueError:
            continue
    return result


class StreamParser:
    """Only publish complete frames; partial frames are discarded on reconnect."""

    def __init__(self):
        self.wan = ()
        self.uptime = None
        self.lines = []
        self.metadata = None

    def feed(self, line: str) -> Sample | None:
        line = line.rstrip("\r\n")
        if line == "@@WAN":
            self.metadata = []
        elif line == "@@WAN_END":
            try:
                status = json.loads("\n".join(self.metadata or []))
                names = []
                for entry in status.get("interface", []):
                    # Prefer the routing device; summing it with its Ethernet
                    # parent would count the same packets twice.
                    if entry.get("up") and (
                        entry.get("interface") in ("wan", "wan6")
                        or any(route.get("mask") == 0 for route in entry.get("route", []))
                    ):
                        device = entry.get("l3_device") or entry.get("device")
                        if isinstance(device, str) and device not in names:
                            names.append(device)
                self.wan = tuple(names)
            except (ValueError, AttributeError, TypeError):
                pass
            self.metadata = None
        elif line.startswith("@@SAMPLE "):
            try:
                uptime = float(line.split()[1])
                self.uptime = uptime if math.isfinite(uptime) and uptime >= 0 else None
            except (ValueError, IndexError):
                self.uptime = None
            self.lines = []
        elif line == "@@END":
            counters = parse_netdev("\n".join(self.lines))
            result = Sample(self.uptime, counters, self.wan) if self.uptime is not None and counters else None
            self.uptime, self.lines = None, []
            return result
        elif self.metadata is not None:
            if len(self.metadata) < 8192:
                self.metadata.append(line)
        elif self.uptime is not None and len(self.lines) < 4096:
            self.lines.append(line)
        return None


@dataclass
class Interface:
    rx: float = 0
    tx: float = 0
    peak_rx: float = 0
    peak_tx: float = 0
    total_rx: int = 0
    total_tx: int = 0
    history_rx: deque = field(default_factory=lambda: deque(maxlen=240))
    history_tx: deque = field(default_factory=lambda: deque(maxlen=240))


class Tracker:
    def __init__(self):
        self.previous: Sample | None = None
        self.interfaces: dict[str, Interface] = {}
        self.wan: tuple[str, ...] = ()
        self.elapsed = 0.0
        self.interval = None

    def disconnect(self):
        self.previous = None
        for interface in self.interfaces.values():
            interface.rx = interface.tx = 0

    def reset(self):
        self.interfaces = {name: Interface() for name in self.interfaces}
        self.elapsed = 0.0
        self.interval = None

    def update(self, sample: Sample):
        old = self.previous
        dt = sample.uptime - old.uptime if old else 0
        self.wan = sample.wan
        self.interfaces = {name: self.interfaces.get(name, Interface()) for name in sample.counters}
        if dt > 0:
            self.elapsed += dt
            self.interval = dt
        for name, counters in sample.counters.items():
            interface = self.interfaces[name]
            prior = old.counters.get(name) if old and dt > 0 else None
            if prior is None or counters.rx < prior.rx or counters.tx < prior.tx:
                # Reboots, recreated interfaces and counter resets need a new
                # baseline, never a fabricated spike or negative throughput.
                interface.rx = interface.tx = 0
                if prior is not None or (old and dt < 0):
                    interface.history_rx.clear()
                    interface.history_tx.clear()
                continue
            rx, tx = counters.rx - prior.rx, counters.tx - prior.tx
            interface.rx, interface.tx = rx / dt, tx / dt
            interface.peak_rx = max(interface.peak_rx, interface.rx)
            interface.peak_tx = max(interface.peak_tx, interface.tx)
            interface.total_rx += rx
            interface.total_tx += tx
            interface.history_rx.append(interface.rx)
            interface.history_tx.append(interface.tx)
        self.previous = sample


def format_rate(value: float, bits: bool = False) -> str:
    value *= 8 if bits else 1
    base = 1000 if bits else 1024
    units = ("bit/s", "Kbit/s", "Mbit/s", "Gbit/s", "Tbit/s") if bits else ("B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s")
    for unit in units[:-1]:
        if value < base:
            return f"{value:,.2f} {unit}"
        value /= base
    return f"{value:,.2f} {units[-1]}"


def format_bytes(value: int) -> str:
    return format_rate(value).removesuffix("/s")
