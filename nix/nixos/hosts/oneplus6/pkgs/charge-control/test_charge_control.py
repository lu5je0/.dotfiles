"""Exercise controller I/O, threshold boundaries and shutdown recovery."""

from pathlib import Path
import importlib.util
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("charge_control", Path(__file__).with_name("charge-control.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ChargeController = module.ChargeController


class ChargeControlTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.capacity = self.root / "bq27411-0/capacity"
        self.behaviour = self.root / "pmi8998-charger/charge_behaviour"
        self.capacity.parent.mkdir()
        self.behaviour.parent.mkdir()
        self.capacity.write_text("65\n")
        self.behaviour.write_text("[auto] inhibit-charge\n")
        self.controller = ChargeController(self.root)

    def test_stateful_band_and_exact_boundaries(self):
        for capacity, expected in [
            (65, "inhibit-charge"),
            (60, "inhibit-charge"),
            (40, "inhibit-charge"),
            (39, "auto"),
            (40, "auto"),
            (60, "auto"),
            (61, "inhibit-charge"),
            (0, "auto"),
        ]:
            with self.subTest(capacity=capacity, expected=expected):
                self.capacity.write_text(f"{capacity}\n")
                self.controller.step()
                self.assertEqual(self.behaviour.read_text().strip(), expected)

    def test_invalid_or_missing_capacity_restores_charging_and_recovers(self):
        for value in ("-1", "101", "unavailable", None):
            with self.subTest(value=value):
                self.behaviour.write_text("auto [inhibit-charge]\n")
                if value is None:
                    self.capacity.unlink()
                else:
                    self.capacity.write_text(value)
                with self.assertLogs(level="ERROR"):
                    self.controller.step()
                self.assertEqual(self.behaviour.read_text().strip(), "auto")
                self.capacity.write_text("70\n")
                self.controller.step()
                self.assertEqual(self.behaviour.read_text().strip(), "inhibit-charge")

    def test_termination_restores_charging(self):
        process = subprocess.Popen(
            [sys.executable, str(Path(__file__).with_name("charge-control.py")),
             "--power-supply-root", str(self.root), "--interval", "0.02"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.monotonic() + 3
            while self.behaviour.read_text().strip() != "inhibit-charge":
                self.assertIsNone(process.poll())
                if time.monotonic() >= deadline:
                    self.fail("controller did not pause charging")
                time.sleep(0.01)
            process.terminate()
            self.assertEqual(process.wait(timeout=3), 0)
            self.assertEqual(self.behaviour.read_text().strip(), "auto")
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()


if __name__ == "__main__":
    unittest.main()
