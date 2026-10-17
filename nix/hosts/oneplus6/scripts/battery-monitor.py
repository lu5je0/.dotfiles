#!/usr/bin/env python3
"""Record read-only phone battery samples for a bounded overnight test."""
import argparse
import csv
import datetime
import json
import pathlib
import signal
import threading
import time


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=pathlib.Path, required=True)
    parser.add_argument("--interval", type=int, default=60)
    args = parser.parse_args()
    if args.interval < 1:
        parser.error("interval must be positive")
    metadata = json.loads((args.directory / "metadata.json").read_text())
    deadline = metadata["stop_at_epoch"]
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())

    supplies = pathlib.Path("/sys/class/power_supply")
    battery = supplies / "bq27411-0"
    charger = supplies / "pmi8998-charger"
    columns = {
        "capacity_percent": battery / "capacity",
        "battery_status": battery / "status",
        "battery_current_uA": battery / "current_now",
        "battery_voltage_uV": battery / "voltage_now",
        "battery_temp_tenths_C": battery / "temp",
        "charge_full_uAh": battery / "charge_full",
        "charge_now_uAh": battery / "charge_now",
        "usb_online": charger / "online",
        "usb_current_limit_uA": charger / "current_max",
        "usb_voltage_uV": charger / "voltage_now",
        "charger_status": charger / "status",
        "charger_health": charger / "health",
        "charge_behaviour": charger / "charge_behaviour",
    }
    fields = ["timestamp", "uptime_seconds", "load_1m", *columns]
    output = args.directory / "samples.csv"
    print(f"Recording every {args.interval}s to {output}; stop at epoch {deadline}", flush=True)
    with output.open("a", newline="", buffering=1) as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        if handle.tell() == 0:
            writer.writeheader()
        while not stop.is_set() and time.time() < deadline:
            row = {key: read(path) for key, path in columns.items()}
            row["timestamp"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            uptime = read(pathlib.Path("/proc/uptime")).split()
            load = read(pathlib.Path("/proc/loadavg")).split()
            row["uptime_seconds"] = uptime[0] if uptime else ""
            row["load_1m"] = load[0] if load else ""
            writer.writerow(row)
            handle.flush()
            stop.wait(max(0, min(args.interval, deadline - time.time())))
    print("Battery recording stopped; samples preserved", flush=True)


if __name__ == "__main__":
    main()
