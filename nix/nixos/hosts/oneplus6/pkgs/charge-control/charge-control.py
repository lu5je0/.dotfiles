"""Keep OnePlus 6 battery charge within a hysteresis band."""

import argparse
import logging
from pathlib import Path
import signal
import threading


class ChargeController:
    def __init__(self, root, low=40, high=60):
        self.capacity = root / "bq27411-0/capacity"
        self.behaviour = root / "pmi8998-charger/charge_behaviour"
        self.low = low
        self.high = high
        self.last_error = None
        self.last_state = None

    def read_mode(self):
        tokens = self.behaviour.read_text().split()
        selected = [token[1:-1] for token in tokens if token.startswith("[") and token.endswith("]")]
        if not selected and len(tokens) == 1:
            selected = tokens
        if len(selected) != 1 or selected[0] not in ("auto", "inhibit-charge"):
            raise ValueError("invalid charge_behaviour: " + " ".join(tokens))
        return selected[0]

    def restore_charging(self):
        try:
            current = self.read_mode()
        except (OSError, ValueError):
            current = None
        if current != "auto":
            self.behaviour.write_text("auto\n")
            logging.info("Restored normal charging")

    def step(self):
        try:
            capacity = int(self.capacity.read_text().strip())
            if not 0 <= capacity <= 100:
                raise ValueError(f"battery capacity out of range: {capacity}")
            current = self.read_mode()
        except (OSError, ValueError) as error:
            message = str(error)
            if message != self.last_error:
                logging.error("Cannot read charging state; restoring charging: %s", error)
            self.last_error = message
            self.last_state = None
            self.restore_charging()
            return

        if self.last_error is not None:
            logging.info("Battery readings recovered")
        self.last_error = None

        desired = current
        if capacity < self.low:
            desired = "auto"
        elif capacity > self.high:
            desired = "inhibit-charge"

        if desired != current:
            self.behaviour.write_text(desired + "\n")
        if desired != self.last_state:
            logging.info("Battery %d%%: %s (band %d%%–%d%%)", capacity, desired, self.low, self.high)
        self.last_state = desired


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--low", type=int, default=40)
    parser.add_argument("--high", type=int, default=60)
    parser.add_argument("--interval", type=float, default=15)
    parser.add_argument("--power-supply-root", type=Path, default=Path("/sys/class/power_supply"))
    args = parser.parse_args()
    if not 0 < args.low < args.high < 100:
        parser.error("thresholds must satisfy 0 < low < high < 100")
    if not 0 < args.interval <= 3600:
        parser.error("interval must be between 0 and 3600 seconds")

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    stopped = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stopped.set())

    controller = ChargeController(args.power_supply_root, args.low, args.high)
    try:
        while not stopped.is_set():
            controller.step()
            stopped.wait(args.interval)
    except OSError:
        logging.exception("Failed to control charging")
        return 1
    finally:
        try:
            controller.restore_charging()
        except OSError:
            logging.exception("Could not restore normal charging")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
