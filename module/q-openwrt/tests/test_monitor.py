import contextlib
import curses
import io
import json
import math
from pathlib import Path
import queue
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from q_openwrt.app import parse_args
from q_openwrt.model import Counter, Sample, StreamParser, Tracker, format_rate, parse_netdev
from q_openwrt.source import Source, remote_script
from q_openwrt.ui import Dashboard, braille_graph, graph_scale


def netdev(name="pppoe-wan", rx=1000, tx=500):
    return f" {name}: {rx} 10 0 0 0 0 0 0 {tx} 5 0 0 0 0 0 0\n"


class ParserTests(unittest.TestCase):
    def test_linux_headers_and_large_counters(self):
        text = "Inter-| Receive | Transmit\n" + netdev(rx=2**53 + 7) + netdev("br-lan", 123, 456)
        result = parse_netdev(text)
        self.assertEqual(result["pppoe-wan"].rx, 2**53 + 7)
        self.assertEqual(result["br-lan"], Counter(123, 456))

    def test_malformed_counters_are_ignored(self):
        self.assertEqual(parse_netdev("bad: 1 2\n" + netdev(rx=-1) + netdev(tx="x")), {})

    def test_complete_frames_and_wan_routing_device(self):
        parser = StreamParser()
        metadata = {"interface": [
            {"interface": "wan", "up": True, "l3_device": "pppoe-wan", "device": "eth1"},
            {"interface": "wan6", "up": True, "l3_device": "pppoe-wan"},
            {"interface": "lan", "up": True, "device": "br-lan"},
            {"interface": "backup", "up": False, "device": "wwan0"},
        ]}
        for line in ["@@WAN", json.dumps(metadata), "@@WAN_END", "@@SAMPLE 50.25", netdev().strip()]:
            self.assertIsNone(parser.feed(line))
        sample = parser.feed("@@END")
        self.assertEqual(sample.wan, ("pppoe-wan",))
        self.assertEqual(sample.uptime, 50.25)

    def test_custom_interface_with_default_route(self):
        parser = StreamParser()
        for line in ["@@WAN", json.dumps({"interface": [{"interface": "isp", "up": True,
                    "device": "eth2", "route": [{"mask": 0}]}]}), "@@WAN_END"]:
            parser.feed(line)
        self.assertEqual(parser.wan, ("eth2",))

    def test_incomplete_frame_replaced_and_invalid_timestamp_rejected(self):
        parser = StreamParser()
        for line in ["@@SAMPLE 2", netdev(), "@@SAMPLE nan", netdev()]:
            parser.feed(line)
        self.assertIsNone(parser.feed("@@END"))
        for line in ["@@SAMPLE 4.5", netdev(rx=999)]:
            parser.feed(line)
        self.assertEqual(parser.feed("@@END").counters["pppoe-wan"].rx, 999)


class RateTests(unittest.TestCase):
    def sample(self, timestamp, rx, tx=0, name="wan"):
        return Sample(timestamp, {name: Counter(rx, tx)}, (name,))

    def test_elapsed_router_time_and_session_volume(self):
        tracker = Tracker()
        tracker.update(self.sample(100, 2**55, 200))
        tracker.update(self.sample(102, 2**55 + 4096, 1224))
        item = tracker.interfaces["wan"]
        self.assertEqual((item.rx, item.tx), (2048, 512))
        self.assertEqual((item.total_rx, item.total_tx), (4096, 1024))
        self.assertEqual((item.peak_rx, item.peak_tx), (2048, 512))

    def test_reset_reboot_and_zero_time_never_make_spikes(self):
        tracker = Tracker()
        for timestamp, rx in [(100, 1000), (101, 2000), (102, 10), (2, 20), (2, 30)]:
            tracker.update(self.sample(timestamp, rx))
        item = tracker.interfaces["wan"]
        self.assertEqual(item.rx, 0)
        self.assertEqual(item.total_rx, 1000)
        tracker.update(self.sample(3, 130))
        self.assertEqual(item.rx, 100)

    def test_reconnect_excludes_unobserved_traffic(self):
        tracker = Tracker()
        tracker.update(self.sample(1, 100))
        tracker.update(self.sample(2, 200))
        tracker.disconnect()
        tracker.update(self.sample(50, 5000))
        self.assertEqual(tracker.interfaces["wan"].rx, 0)
        tracker.update(self.sample(51, 5250))
        self.assertEqual(tracker.interfaces["wan"].total_rx, 350)

    def test_hotplug_interfaces_start_with_baseline(self):
        tracker = Tracker()
        tracker.update(self.sample(1, 10))
        tracker.update(self.sample(2, 100000, name="pppoe-wan"))
        self.assertNotIn("wan", tracker.interfaces)
        self.assertEqual(tracker.interfaces["pppoe-wan"].rx, 0)

    def test_units(self):
        self.assertEqual(format_rate(1024), "1.00 KiB/s")
        self.assertEqual(format_rate(125000, bits=True), "1.00 Mbit/s")

    def test_reset_preserves_devices_and_restarts_statistics(self):
        tracker = Tracker()
        tracker.update(self.sample(1, 100))
        tracker.update(self.sample(2, 500))
        tracker.reset()
        self.assertEqual(tracker.wan, ("wan",))
        self.assertEqual(tracker.interfaces["wan"].total_rx, 0)
        self.assertEqual(tracker.elapsed, 0)
        tracker.update(self.sample(3, 750))
        self.assertEqual(tracker.interfaces["wan"].total_rx, 250)
        self.assertEqual(tracker.interfaces["wan"].peak_rx, 250)


class SourceTests(unittest.TestCase):
    def test_remote_script_runs_on_local_linux_and_stops(self):
        source = Source(["sh", "-c", remote_script(0.2)], 0.2)
        source.start()
        try:
            samples = []
            deadline = time.monotonic() + 5
            while len(samples) < 2 and time.monotonic() < deadline:
                kind, value = source.events.get(timeout=2)
                if kind == "sample":
                    samples.append(value)
            self.assertEqual(len(samples), 2)
            self.assertGreater(samples[1].uptime, samples[0].uptime)
            self.assertIn("lo", samples[0].counters)
        finally:
            source.close()
        self.assertFalse(source.thread.is_alive())
        self.assertIsNone(source.process)

    def test_stderr_failure_is_reported_and_retried(self):
        source = Source([sys.executable, "-c", "import sys; sys.stderr.write('login failed'); sys.exit(1)"], 0.2)
        source.start()
        try:
            events = [source.events.get(timeout=3) for _ in range(3)]
            self.assertIn(("error", "login failed"), events)
            self.assertTrue(any("Reconnecting" in value for kind, value in events if kind == "status"))
        finally:
            source.close()

    def test_cli_rejects_invalid_intervals_and_hosts(self):
        for args in [["--interval", "nan"], ["--interval", "inf"], ["--interval", "0"],
                     ["--port", "0"], ["root@host\n"], ["--local", "router"]]:
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    parse_args(args)

    def test_script_rejects_nonfinite_interval(self):
        for interval in (math.nan, math.inf, 0, 100):
            with self.assertRaises(ValueError):
                remote_script(interval)

    def test_busybox_integer_sleep_fallback_and_usleep(self):
        for has_usleep in (False, True):
            with self.subTest(usleep=has_usleep), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                trace = root / "trace"
                real_sleep = shutil.which("sleep")
                sleep = root / "sleep"
                sleep.write_text(f"#!/bin/sh\nprintf 'sleep %s\\n' \"$1\" >> {shlex.quote(str(trace))}\n"
                                 f"case $1 in *.*) exit 1;; esac\nexec {shlex.quote(real_sleep)} 0.02\n")
                sleep.chmod(0o755)
                (root / "cat").symlink_to(shutil.which("cat"))
                if has_usleep:
                    usleep = root / "usleep"
                    usleep.write_text(f"#!/bin/sh\nprintf 'usleep %s\\n' \"$1\" >> {shlex.quote(str(trace))}\n"
                                      f"exec {shlex.quote(real_sleep)} 0.02\n")
                    usleep.chmod(0o755)
                command = [shutil.which("sh"), "-c", f"PATH={shlex.quote(directory)}\n" + remote_script(0.2)]
                source = Source(command, 0.2)
                source.start()
                try:
                    samples = []
                    deadline = time.monotonic() + 3
                    while len(samples) < 2 and time.monotonic() < deadline:
                        kind, value = source.events.get(timeout=2)
                        if kind == "sample":
                            samples.append(value)
                        if kind == "error":
                            self.fail(value)
                    self.assertEqual(len(samples), 2)
                    calls = trace.read_text()
                    self.assertIn("usleep 200000" if has_usleep else "sleep 1", calls)
                    self.assertNotIn("sleep 0.2", calls)
                finally:
                    source.close()


class FakeScreen:
    def __init__(self, height, width):
        self.height, self.width = height, width
        self.erase()

    def erase(self):
        self.lines = [list(" " * self.width) for _ in range(self.height)]

    def getmaxyx(self):
        return self.height, self.width

    def addnstr(self, y, x, text, limit, style):
        for offset, char in enumerate(text[:limit]):
            self.lines[y][x + offset] = char

    def timeout(self, value):
        pass

    def refresh(self):
        pass

    def text(self):
        return "\n".join("".join(line) for line in self.lines)


class LayoutTests(unittest.TestCase):
    def dashboard(self, height, width):
        screen = FakeScreen(height, width)
        args = parse_args(["--demo"])
        with patch.object(curses, "has_colors", return_value=False), patch.object(curses, "curs_set"):
            dashboard = Dashboard(screen, Source(None, 1, True), args)
        for timestamp, counter in [(1, 100), (2, 1024100)]:
            dashboard.source.events.put(("sample", Sample(timestamp, {"pppoe-wan": Counter(counter, counter // 2)}, ("pppoe-wan",))))
        dashboard.drain()
        return dashboard, screen

    def test_layout_sizes_and_help(self):
        for height, width in [(23, 68), (24, 80), (32, 100), (50, 160)]:
            with self.subTest(size=(height, width)):
                dashboard, screen = self.dashboard(height, width)
                dashboard.draw()
                self.assertIn("download", screen.text())
                self.assertIn("upload", screen.text())
                self.assertIn("pppoe-wan", screen.text())
                self.assertIn("1,000.00 KiB/s", screen.text())
                dashboard.help = True
                dashboard.draw()
                self.assertIn("HELP", screen.text())

    def test_missing_interface_and_small_terminal(self):
        dashboard, screen = self.dashboard(24, 80)
        dashboard.automatic = False
        dashboard.selected = "missing"
        dashboard.draw()
        self.assertIn("unavailable", screen.text())
        dashboard.screen = FakeScreen(8, 40)
        dashboard.draw()
        self.assertIn("enlarge terminal", dashboard.screen.text())

    def test_terminal_escape_sequences_are_sanitized(self):
        dashboard, screen = self.dashboard(24, 80)
        dashboard.error = "remote\x1b[2J\nerror"
        dashboard.draw()
        self.assertNotIn("\x1b", screen.text())

    def test_hidden_interfaces_are_excluded_from_selection_and_rendering(self):
        dashboard, screen = self.dashboard(32, 100)
        dashboard.tracker.update(Sample(3, {name: Counter(1024200, 512100)
                                 for name in ("pppoe-wan", "br-lan", "sit0", "lo")}, ("lo", "pppoe-wan")))
        dashboard.choose()
        self.assertEqual(dashboard.names(), ["pppoe-wan", "br-lan"])
        self.assertEqual(dashboard.selected, "pppoe-wan")
        dashboard.draw()
        self.assertNotIn("sit0", screen.text())
        self.assertNotRegex(screen.text(), r"\blo\b")

    def test_only_hidden_interfaces_does_not_select_loopback(self):
        dashboard, screen = self.dashboard(24, 80)
        dashboard.tracker.update(Sample(3, {"lo": Counter(100, 100), "sit0": Counter(0, 0)}))
        dashboard.choose()
        self.assertEqual(dashboard.names(), [])
        self.assertIsNone(dashboard.selected)
        dashboard.draw()
        self.assertIn("Waiting for interfaces", screen.text())


class GraphTests(unittest.TestCase):
    def test_braille_sample_order_and_pixel_masks(self):
        self.assertEqual(braille_graph([1, 0], 1, 1, 4), ["⡀"])
        self.assertEqual(braille_graph([0, 1], 1, 1, 4), ["⢀"])
        self.assertEqual(braille_graph([1, 0], 1, 1, 4, inverted=True), ["⠁"])
        self.assertEqual(braille_graph([4, 4], 1, 1, 4), ["⣿"])
        self.assertEqual(braille_graph([0, 0], 1, 1, 4), [" "])

    def test_graph_clips_history_and_keeps_scale_above_peak(self):
        self.assertEqual(braille_graph([999, 0, 0], 1, 1, 4), [" "])
        self.assertEqual(braille_graph([], 3, 2, 1), ["   ", "   "])
        self.assertGreaterEqual(graph_scale([1000000, 250000]), 1000000)
        self.assertGreater(graph_scale([]), 0)


if __name__ == "__main__":
    unittest.main()
