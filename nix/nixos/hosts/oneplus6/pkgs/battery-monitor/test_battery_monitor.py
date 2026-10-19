import csv
import datetime
import pathlib
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

import battery_monitor as monitor


class BatteryMonitorTests(unittest.TestCase):
    def test_reads_raw_units_and_tolerates_missing_attributes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "bq27411-0").mkdir()
            (root / "bq27411-0/capacity").write_text("51\n")
            (root / "bq27411-0/current_now").write_text("-237000\n")
            (root / "bq27411-0/temp").write_text("317\n")
            (root / "uptime").write_text("123.45 234.56\n")
            (root / "loadavg").write_text("0.02 0.04 0.08 1/200 42\n")
            sample = monitor.collect_sample(datetime.datetime.now().astimezone(), root, root)
            self.assertEqual(sample["capacity_percent"], "51")
            self.assertEqual(sample["battery_current_uA"], "-237000")
            self.assertEqual(sample["battery_temp_tenths_C"], "317")
            self.assertEqual(sample["uptime_seconds"], "123.45")
            self.assertEqual(sample["load_1m"], "0.02")
            self.assertEqual(sample["usb_online"], "")

    def test_append_restart_and_midnight_preserve_rows_and_one_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            times = ["2026-10-18T23:58:00+08:00", "2026-10-18T23:59:00+08:00", "2026-10-19T00:00:00+08:00"]
            for timestamp in times:
                monitor.append_sample(root, {"timestamp": timestamp, "capacity_percent": "51"})
            with (root / "2026-10-18.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual([row["timestamp"] for row in rows], times[:2])
            with (root / "2026-10-19.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual([row["timestamp"] for row in rows], times[2:])

    def test_retention_boundary_only_removes_expired_daily_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            today = datetime.date(2026, 10, 18)
            for age in range(35):
                (root / f"{today - datetime.timedelta(days=age)}.csv").write_text("sample\n")
            (root / "notes.txt").write_text("preserve")
            (root / "2026-99-99.csv").write_text("preserve")
            (root / "2020-01-01.csv").symlink_to(root / "notes.txt")
            (root / "2020-01-02.csv").mkdir()
            monitor.prune_logs(root, today, 30)
            for age in range(35):
                self.assertEqual((root / f"{today - datetime.timedelta(days=age)}.csv").exists(), age < 30)
            self.assertTrue((root / "2020-01-01.csv").is_symlink())
            self.assertTrue((root / "2020-01-02.csv").is_dir())
            self.assertEqual((root / "notes.txt").read_text(), "preserve")
            self.assertTrue((root / "2026-99-99.csv").exists())

    def test_service_runs_without_metadata_prunes_at_start_and_stops_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            today = datetime.datetime.now().astimezone().date()
            old = root / f"{today - datetime.timedelta(days=30)}.csv"
            old.write_text("expired\n")
            logs = root / "logs"
            logs.mkdir(mode=0o755)
            old.rename(logs / old.name)
            old = logs / old.name
            output = logs / f"{today}.csv"
            process = subprocess.Popen(
                [sys.executable, str(pathlib.Path(monitor.__file__)), "--directory", str(logs), "--interval", "1"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                umask=0o022,
            )
            try:
                deadline = time.monotonic() + 8
                rows = []
                while time.monotonic() < deadline:
                    if output.exists():
                        with output.open(newline="") as handle:
                            rows = list(csv.DictReader(handle))
                    if len(rows) >= 2 or process.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertIsNone(process.poll())
                self.assertGreaterEqual(len(rows), 2)
                self.assertFalse(old.exists())
                self.assertEqual(stat.S_IMODE(logs.stat().st_mode), 0o755)
                self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o644)
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=3)
                self.assertEqual(process.returncode, 0, stderr)
                self.assertIn("samples preserved", stdout)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()

    def test_invalid_intervals_and_retention_are_rejected(self):
        for flag in ("--interval", "--retention-days"):
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(monitor.__file__)), "--directory", "/unused", flag, "0"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
