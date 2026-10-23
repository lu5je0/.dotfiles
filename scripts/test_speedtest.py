#!/usr/bin/env python3
"""离线回归检查：python3 scripts/test_speedtest.py。"""

import contextlib
import http.client
import io
import os
from pathlib import Path
import runpy
import threading
import unittest
from unittest.mock import Mock, patch


SPEEDTEST = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/common/speedtest"))
GLOBALS = SPEEDTEST["main"].__globals__


class SpeedtestTests(unittest.TestCase):
    def test_recent_rate_excludes_old_fast_samples(self):
        samples = [(0.0, 0), (1.0, 1000), (2.0, 1100), (3.0, 1200), (4.0, 1300)]
        self.assertEqual(SPEEDTEST["sample_rate"](samples, 2.0), 100.0)

    def test_final_rate_excludes_warmup_and_includes_tail(self):
        samples = [(0.0, 0), (1.0, 50), (2.0, 100), (3.0, 400), (4.0, 800)]
        self.assertEqual(SPEEDTEST["sample_rate"](samples, 2.0), 350.0)

    def test_rate_interpolates_irregular_sample_boundaries(self):
        samples = [(0.0, 0), (1.1, 110), (2.4, 240)]
        self.assertAlmostEqual(SPEEDTEST["sample_rate"](samples, 0.5), 100.0)
        self.assertAlmostEqual(SPEEDTEST["sample_rate"](samples, -1.0), 100.0)

    def test_rate_reports_stall_and_handles_empty_window(self):
        rate = SPEEDTEST["sample_rate"]
        self.assertEqual(rate([(0.0, 0), (2.0, 100), (4.0, 100)], 2.0), 0.0)
        self.assertEqual(rate([], 0.0), 0.0)
        self.assertEqual(rate([(0.0, 0)], 0.0), 0.0)
        self.assertEqual(rate([(0.0, 0), (1.0, 100)], 1.0), 0.0)
        self.assertEqual(rate([(0.0, 0), (1.0, 100)], 2.0), 0.0)

    def test_upload_body_reuses_buffer_and_counts_after_send(self):
        data = bytes(range(256)) * (SPEEDTEST["IO_CHUNK"] // 256 + 1)
        stop = threading.Event()
        counts = []
        chunks = iter(SPEEDTEST["_CountingBody"](data, counts.append, stop))
        first = next(chunks)
        self.assertIsInstance(first, memoryview)
        self.assertIs(first.obj, data)
        self.assertEqual(counts, [])
        second = next(chunks)
        self.assertEqual(counts, [len(first)])
        self.assertIs(second.obj, data)
        with self.assertRaises(StopIteration):
            next(chunks)
        self.assertEqual(sum(counts), len(data))
        self.assertEqual(bytes(first) + bytes(second), data)

    def test_upload_stop_keeps_completed_chunk_count(self):
        stop = threading.Event()
        counts = []
        data = bytes(SPEEDTEST["IO_CHUNK"] * 3)
        chunks = iter(SPEEDTEST["_CountingBody"](data, counts.append, stop))
        next(chunks)
        stop.set()
        with self.assertRaises(StopIteration):
            next(chunks)
        self.assertEqual(counts, [SPEEDTEST["IO_CHUNK"]])
        self.assertEqual(list(SPEEDTEST["_CountingBody"](data, counts.append, stop)), [])

    def test_http_client_sends_exact_body(self):
        data = bytes(range(256)) * 2049
        counts = []
        sent = []
        conn = http.client.HTTPConnection("example.com")
        conn.sock = Mock()
        conn.sock.sendall.side_effect = lambda chunk: sent.append(bytes(chunk))
        conn.request("POST", "/upload", body=SPEEDTEST["_CountingBody"](
            data, counts.append, threading.Event()), headers={"Content-Length": str(len(data))})
        header, payload = b"".join(sent).split(b"\r\n\r\n", 1)
        self.assertIn(b"Content-Length: " + str(len(data)).encode(), header)
        self.assertNotIn(b"Transfer-Encoding", header)
        self.assertEqual(payload, data)
        self.assertEqual(sum(counts), len(data))
        self.assertLessEqual(max(counts), SPEEDTEST["IO_CHUNK"])

    def test_failed_send_is_not_counted(self):
        counts = []
        conn = http.client.HTTPConnection("example.com")
        conn.sock = Mock()
        conn.sock.sendall.side_effect = [None, OSError("send failed")]
        with self.assertRaises(OSError):
            conn.request("POST", "/upload", body=SPEEDTEST["_CountingBody"](
                b"payload", counts.append, threading.Event()), headers={"Content-Length": "7"})
        self.assertEqual(counts, [])

    def test_librespeed_urls(self):
        for url, expected in [
            ("192.168.1.10:3000", "http://192.168.1.10:3000/"),
            ("https://example.com/test/", "https://example.com/test/"),
            ("https://example.com/test", "https://example.com/test/"),
            ("http://[::1]:3000", "http://[::1]:3000/"),
        ]:
            with self.subTest(url=url):
                base, paths = SPEEDTEST["librespeed_target"](url)
                self.assertEqual(base, expected)
                prefix = "/test/backend/" if "/test/" in base else "/backend/"
                self.assertEqual(paths["latency"], prefix + "empty.php")
                self.assertEqual(paths["upload"], prefix + "empty.php")
                self.assertEqual(paths["download"], prefix + "garbage.php?ckSize=50")

    def test_invalid_urls(self):
        for url in ["", "ftp://host", "http://", "http://host:bad", "http://host:65536",
                    "http://user:pass@host", "http://host/?query=1", "http://host/#fragment"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                SPEEDTEST["librespeed_target"](url)

    def run_main(self, args, cfg=None):
        server = {"id": "60324", "host": "node:8080", "sponsor": "Test", "name": "Tokyo"}
        mocks = {
            "fetch_config": Mock(return_value=cfg or {"servers": [server]}),
            "select_server": Mock(return_value=(server, "http://node:8080/speedtest/")),
            "resolve_base": Mock(return_value="http://node:8080/speedtest/"),
            "measure_idle_latency": Mock(return_value=([1.0, 2.0], 0, 3)),
            "run_transfer": Mock(return_value={"bytes": 1024, "speed": 512, "latency": []}),
            "try_save_result": Mock(return_value=None),
        }
        with patch.dict(GLOBALS, mocks), patch.dict(os.environ, {"SPEEDTEST_SAVE": "1"}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = SPEEDTEST["main"](args)
        return result, mocks

    def test_custom_node_bypasses_ookla(self):
        result, mocks = self.run_main(["--librespeed", "http://host/test", "-T", "8"])
        self.assertEqual(result, 0)
        for name in ("fetch_config", "select_server", "resolve_base", "try_save_result"):
            mocks[name].assert_not_called()
        mocks["measure_idle_latency"].assert_called_once_with(
            "http://host/test/", 5, "/test/backend/empty.php")
        self.assertEqual(mocks["run_transfer"].call_count, 2)
        for call, upload in zip(mocks["run_transfer"].call_args_list, [False, True]):
            self.assertEqual(call.args[1], "http://host/test/")
            self.assertEqual(call.args[3:5], (8, upload))
            self.assertEqual(call.args[6]["upload"], "/test/backend/empty.php")

    def test_default_librespeed_node(self):
        for args in (["--librespeed"], ["--librespeed="], ["--librespeed", "-T", "4"]):
            with self.subTest(args=args):
                result, mocks = self.run_main(args)
                self.assertEqual(result, 0)
                mocks["fetch_config"].assert_not_called()
                mocks["measure_idle_latency"].assert_called_once_with(
                    "http://192.168.1.10:3000/", 5, "/backend/empty.php")
                self.assertEqual(mocks["run_transfer"].call_args.args[3], 4 if "-T" in args else 1)

    def test_librespeed_equals_url(self):
        result, mocks = self.run_main(["--librespeed=http://other:8080/test"])
        self.assertEqual(result, 0)
        mocks["measure_idle_latency"].assert_called_once_with(
            "http://other:8080/test/", 5, "/test/backend/empty.php")

    def test_ookla_explicit_and_automatic_selection(self):
        for args in (["-s", "60324"], []):
            with self.subTest(args=args):
                result, mocks = self.run_main(args)
                self.assertEqual(result, 0)
                mocks["fetch_config"].assert_called_once_with("60324" if args else None)
                self.assertEqual(mocks["resolve_base"].call_count, 1 if args else 0)
                self.assertEqual(mocks["select_server"].call_count, 0 if args else 1)
                self.assertEqual(mocks["run_transfer"].call_args.args[6], SPEEDTEST["OOKLA_PATHS"])
                mocks["try_save_result"].assert_called_once()

    def test_ookla_list_only(self):
        result, mocks = self.run_main(["-L"])
        self.assertEqual(result, 0)
        mocks["fetch_config"].assert_called_once_with(None)
        mocks["run_transfer"].assert_not_called()

    def test_conflicting_targets(self):
        for args in (["--librespeed", "http://host", "-s", "60324"],
                     ["--librespeed", "http://host", "-L"]):
            with self.subTest(args=args), self.assertRaises(SystemExit) as exc:
                self.run_main(args)
            self.assertEqual(exc.exception.code, 2)

    def test_http_errors_are_not_speed_results(self):
        conn = Mock()
        conn.getresponse.return_value = Mock(status=404, reason="Not Found")
        paths = SPEEDTEST["librespeed_target"]("http://host/test")[1]
        with patch.dict(GLOBALS, {"make_conn": Mock(return_value=conn)}):
            samples, failures, probes = SPEEDTEST["measure_idle_latency"](
                "http://host/test/", 2, paths["latency"])
            self.assertEqual((samples, failures, probes), ([], 3, 3))
            for upload in (False, True):
                with self.subTest(upload=upload), self.assertRaisesRegex(RuntimeError, "HTTP 404"):
                    SPEEDTEST["run_transfer"]("Test", "http://host/test/", 1, 1, upload, False, paths)


if __name__ == "__main__":
    unittest.main()
