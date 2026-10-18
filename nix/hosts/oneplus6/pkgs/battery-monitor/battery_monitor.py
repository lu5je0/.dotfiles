#!/usr/bin/env python3
"""Continuously record read-only battery samples in daily, bounded CSV files."""
import argparse
import csv
import datetime
import pathlib
import re
import signal
import threading


COLUMNS = {
    "capacity_percent": "bq27411-0/capacity",
    "battery_status": "bq27411-0/status",
    "battery_current_uA": "bq27411-0/current_now",
    "battery_voltage_uV": "bq27411-0/voltage_now",
    "battery_temp_tenths_C": "bq27411-0/temp",
    "charge_full_uAh": "bq27411-0/charge_full",
    "charge_now_uAh": "bq27411-0/charge_now",
    "usb_online": "pmi8998-charger/online",
    "usb_current_limit_uA": "pmi8998-charger/current_max",
    "usb_voltage_uV": "pmi8998-charger/voltage_now",
    "charger_status": "pmi8998-charger/status",
    "charger_health": "pmi8998-charger/health",
    "charge_behaviour": "pmi8998-charger/charge_behaviour",
}
FIELDS = ["timestamp", "uptime_seconds", "load_1m", *COLUMNS]


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        # A supply can temporarily disappear or lack a particular attribute.
        return ""


def collect_sample(now, supplies=pathlib.Path("/sys/class/power_supply"), proc=pathlib.Path("/proc")):
    sample = {key: read(supplies / path) for key, path in COLUMNS.items()}
    sample["timestamp"] = now.isoformat(timespec="seconds")
    uptime = read(proc / "uptime").split()
    load = read(proc / "loadavg").split()
    sample["uptime_seconds"] = uptime[0] if uptime else ""
    sample["load_1m"] = load[0] if load else ""
    return sample


def append_sample(directory, sample):
    day = datetime.datetime.fromisoformat(sample["timestamp"]).date()
    output = directory / f"{day.isoformat()}.csv"
    # Close after each sample so a restart or date change never leaves buffered
    # samples behind or a writer attached to yesterday's file.
    with output.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        if handle.tell() == 0:
            writer.writeheader()
        writer.writerow(sample)


def prune_logs(directory, today, retention_days):
    # Include today: a 30-day window retains today and the preceding 29 dates.
    cutoff = today - datetime.timedelta(days=retention_days - 1)
    for path in directory.iterdir():
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}\.csv", path.name):
            continue
        if path.is_symlink() or not path.is_file():
            continue
        try:
            day = datetime.date.fromisoformat(path.stem)
        except ValueError:
            continue
        if day < cutoff:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=pathlib.Path, required=True)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--retention-days", type=int, default=30)
    args = parser.parse_args()
    if args.interval < 1 or args.retention_days < 1:
        parser.error("interval and retention-days must be positive")
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o755)
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())

    print(
        f"Recording every {args.interval}s to {args.directory}; "
        f"retaining {args.retention_days} calendar days",
        flush=True,
    )
    last_day = None
    while not stop.is_set():
        now = datetime.datetime.now().astimezone()
        if now.date() != last_day:
            prune_logs(args.directory, now.date(), args.retention_days)
            last_day = now.date()
        append_sample(args.directory, collect_sample(now))
        stop.wait(args.interval)
    print("Battery recording stopped; samples preserved", flush=True)


if __name__ == "__main__":
    main()
