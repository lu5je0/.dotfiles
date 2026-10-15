"""异步加载、错误恢复和缓存回归；只用假 restic，不连接真实仓库。"""

import contextlib
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).with_name("q-restic.py")
SPEC = importlib.util.spec_from_file_location("q_restic", SOURCE)
q = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(q)


def snapshot(n):
    return {"id": str(n) * 64, "short_id": str(n) * 8,
            "time": f"2026-10-{n:02d}T12:00:00Z", "summary": {"total_bytes_processed": 1024}}


class LoadingTests(unittest.TestCase):
    def setUp(self):
        with patch.object(q, "restic_bin", return_value="restic"):
            self.app = q.App(dict(q.DEFAULT_CONFIG, repository="/tmp/test-repo", host="test"))

    def until(self, predicate):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            self.app.poll_data()
            if predicate():
                return
            time.sleep(.005)
        self.fail("后台任务未完成")

    def test_snapshots_distinguish_empty_error_and_bad_json(self):
        for stdout, stderr, code, error in [
            ("[]", "", 0, None), ("", "wrong password", 12, "wrong password"),
            ("broken", "", 0, "无效的 JSON"), ("null", "", 0, "格式无效"),
        ]:
            with self.subTest(stdout=stdout, code=code), patch.object(
                q, "run", return_value=subprocess.CompletedProcess([], code, stdout, stderr)
            ):
                if error:
                    with self.assertRaisesRegex(RuntimeError, error):
                        q.snapshots("restic", self.app.cfg)
                else:
                    self.assertEqual(q.snapshots("restic", self.app.cfg), [])

    def test_cli_status_reports_failure(self):
        with patch.object(q, "restic_bin"), patch.object(q, "require_password"), patch.object(
            q, "snapshots", side_effect=RuntimeError("offline")
        ), contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(q.do_status(self.app.cfg), 1)
        self.assertNotIn("还没有任何版本", out.getvalue())
        self.assertIn("offline", err.getvalue())

    def test_failure_preserves_list_error_and_selection_then_retry(self):
        self.app.snaps = [snapshot(1), snapshot(2)]
        self.app.screen = "snapshots"
        self.app.history = [("menu", 2, 0)]
        self.app.cursor = 1
        with patch.object(q, "snapshots", side_effect=RuntimeError("offline")):
            self.app.refresh()
            self.until(lambda: not self.app.loading)
        self.assertEqual(len(self.app.snaps), 2)
        self.app.handle("k")
        self.assertEqual(self.app.load_error, "offline")
        self.assertIn("offline", "".join(self.app.footer(80)))
        with patch.object(q, "snapshots", return_value=[snapshot(1), snapshot(2), snapshot(3)]), patch.object(
            q, "repo_stats", return_value={"total_size": 123}
        ):
            self.app.handle("h")
            self.app.handle("ENTER")
            self.until(lambda: not self.app.loading and self.app.repo_size_loaded)
        self.assertEqual(self.app.load_error, "")
        self.assertEqual(len(self.app.snaps), 3)
        self.assertEqual(self.app.cursor, 1)  # 刷新后仍选中原来的版本 2
        self.assertFalse(any(item["label"] == "刷新版本与占用" for item in self.app.snapshot_items()))

    def test_refresh_returns_immediately_and_stats_are_lazy_cached(self):
        release = threading.Event()
        def slow_snapshots(*_):
            if not release.wait(3):
                raise RuntimeError("test timeout")
            return [snapshot(1)]
        with patch.object(q, "snapshots", side_effect=slow_snapshots), patch.object(
            q, "repo_stats", return_value={"total_size": 42}
        ) as stats:
            started = time.monotonic()
            self.app.start_load()
            self.assertLess(time.monotonic() - started, .2)
            try:
                self.assertTrue(self.app.loading)
                stats.assert_not_called()
            finally:
                release.set()
            self.until(lambda: not self.app.loading)
            stats.assert_not_called()
            self.app.cursor = 2
            self.app.activate()
            self.until(lambda: self.app.repo_size_loaded)
            self.app.go_back()
            self.app.activate()
            self.app.poll_data()
            self.assertEqual(stats.call_count, 1)
            # 只读刷新保留缓存；仓库写入后的刷新会更新占用。
            self.app.refresh(invalidate_stats=False)
            self.until(lambda: not self.app.loading)
            self.assertEqual(stats.call_count, 1)
            self.app.refresh()
            self.until(lambda: not self.app.loading and self.app.repo_size_loaded)
            self.assertEqual(stats.call_count, 2)

    def test_stale_results_cannot_overwrite_new_repository(self):
        started, release = threading.Event(), threading.Event()
        def load(_, cfg):
            if cfg["repository"] == "/tmp/test-repo":
                started.set()
                release.wait(3)
                return [snapshot(1)]
            return [snapshot(2)]
        with patch.object(q, "snapshots", side_effect=load):
            self.app.start_load()
            self.assertTrue(started.wait(3))
            try:
                self.app.cfg = dict(self.app.cfg, repository="/tmp/new-repo")
                self.app.refresh()
                self.until(lambda: not self.app.loading)
            finally:
                release.set()
            self.app._results.put(self.app._results.get(timeout=3))
            self.app.poll_data()
            self.assertEqual(self.app.snaps, [snapshot(2)])

    def test_old_stats_ignored_after_invalidation(self):
        self.app.screen = "snapshots"
        started, release = threading.Event(), threading.Event()
        def old_stats(*_, **__):
            started.set()
            release.wait(3)
            return {"total_size": 1}
        with patch.object(q, "repo_stats", side_effect=old_stats):
            self.app.start_stats_load()
            self.assertTrue(started.wait(3))
        try:
            self.app.invalidate_stats()
            with patch.object(q, "repo_stats", return_value={"total_size": 2}):
                self.app.start_stats_load()
                self.until(lambda: self.app.repo_size_loaded)
        finally:
            release.set()
        self.app._results.put(self.app._results.get(timeout=3))
        self.app.poll_data()
        self.assertEqual(self.app.repo_size, 2)

    def test_stats_failure_stops_retrying_and_zero_is_valid(self):
        self.app.screen = "snapshots"
        for result, error, label in [({}, None, "不可用"), (None, RuntimeError("offline"), "不可用"),
                                     ({"total_size": 0}, None, "0 B")]:
            self.app.invalidate_stats()
            with patch.object(q, "repo_stats", return_value=result, side_effect=error) as stats:
                self.app.start_stats_load()
                self.until(lambda: self.app.repo_size_loaded)
                self.app.poll_data()
                self.assertEqual(stats.call_count, 1)
            self.assertIn("总占用 " + label, self.app.detail_text())

    def test_readonly_actions_do_not_refresh_and_backup_does(self):
        self.app.term = Mock()
        with patch.object(self.app, "refresh") as refresh:
            self.app.run_suspended(lambda: 0)
            refresh.assert_not_called()
            self.app.run_suspended(lambda: 3, refresh_repo=True)
            refresh.assert_called_once_with()
        self.app.term.wait_key.assert_called_once()

    def test_delete_cancellation_does_not_refresh(self):
        self.app.term = Mock()
        with patch("builtins.input", return_value="n"), patch.object(self.app, "refresh") as refresh, contextlib.redirect_stdout(io.StringIO()):
            self.app.act_forget_snap(snapshot(1))
        refresh.assert_not_called()

    def test_menu_has_no_integrity_check(self):
        self.assertNotIn("校验仓库完整性", [item["label"] for item in self.app.menu_items()])

    def test_delete_success_removes_cached_version_before_refresh_finishes(self):
        self.app.snaps = [snapshot(1), snapshot(2)]
        self.app.screen = "snap_actions"
        self.app.active_snap = snapshot(2)
        self.app.history = [("menu", 2, 0), ("snapshots", 1, 0)]
        self.app.term = Mock()
        with patch("builtins.input", return_value="y"), patch.object(
            q, "run_visible", return_value=(0, "")
        ), patch.object(self.app, "_start_request"), contextlib.redirect_stdout(io.StringIO()):
            self.app.act_forget_snap(snapshot(2))
        self.assertTrue(self.app.loading)
        self.assertEqual(self.app.snaps, [snapshot(1)])
        self.assertEqual(self.app.screen, "snapshots")
        self.assertEqual(self.app.cursor, 0)


class PtyTests(unittest.TestCase):
    def test_navigation_retry_and_cached_stats(self):
        with tempfile.TemporaryDirectory(prefix="q-restic-test-", dir="/tmp") as tmp:
            root = Path(tmp)
            (root / "q-restic").mkdir()
            cfg = dict(q.DEFAULT_CONFIG, repository=str(root / "repo"), host="test")
            (root / "q-restic/config.json").write_text(json.dumps(cfg))
            (root / "offline").touch()
            fake = root / "restic"
            fake.write_text("#!" + sys.executable + "\n" + '''import json, os, sys, time
from pathlib import Path
root = Path(os.environ['XDG_CONFIG_HOME'])
with (root / 'calls').open('a') as log:
    log.write(sys.argv[1] + '\\n')
assert sys.argv[-2:] == ['--host', 'test']
if (root / 'offline').exists():
    print('NAS unavailable', file=sys.stderr)
    raise SystemExit(1)
if sys.argv[1] == 'snapshots':
    time.sleep(.3)
    print(json.dumps([{'id': str(i)*64, 'short_id': str(i)*8, 'time': f'2026-10-0{i}T12:00:00Z'} for i in (1, 2)]))
elif sys.argv[1] == 'stats':
    assert sys.argv[2:5] == ['--json', '--mode', 'raw-data']
    time.sleep(.5)
    print(json.dumps({'total_size': 3*1024**3}))
else:
    raise SystemExit(1)
''')
            fake.chmod(0o755)
            pid, fd = pty.fork()
            if pid == 0:
                os.environ.update(HOME=tmp, XDG_CONFIG_HOME=tmp, TERM="xterm-256color",
                                  EDITOR="/bin/true", PATH=tmp + ":" + os.environ["PATH"])
                os.execv(sys.executable, [sys.executable, str(SOURCE)])
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 90, 0, 0))
            def read_until(text):
                output = bytearray()
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    if select.select([fd], [], [], .05)[0]:
                        try:
                            output.extend(os.read(fd, 65536))
                        except OSError:
                            break
                        decoded = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", output.decode("utf-8", "replace"))
                        if text in decoded:
                            return decoded
                self.fail(f"没找到 {text!r}: {output[-4000:]!r}")
            try:
                read_until("NAS unavailable")
                self.assertNotIn("stats", (root / "calls").read_text())
                os.write(fd, b"jj\r")
                output = read_until("读取仓库失败")
                self.assertNotIn("还没有任何版本", output)
                self.assertNotIn("刷新版本与占用", output)
                (root / "offline").unlink()
                os.write(fd, b"h")
                read_until("立即备份")
                os.write(fd, b"\r")
                read_until("总占用 统计中")
                # 刷新未完成时仍能返回主菜单，并再次进入版本列表。
                os.write(fd, b"h")
                read_until("立即备份")
                os.write(fd, b"\r")
                read_until("总占用 3.0 GiB")
                os.write(fd, b"g")
                read_until("▌ 11111111")
                os.write(fd, b"h")
                read_until("立即备份")
                os.write(fd, b"\r")
                read_until("总占用 3.0 GiB")
                self.assertEqual((root / "calls").read_text().splitlines().count("stats"), 1)
                os.write(fd, b"hq")
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    child, status = os.waitpid(pid, os.WNOHANG)
                    if child:
                        pid = None
                        self.assertEqual(status, 0)
                        break
                    if select.select([fd], [], [], .05)[0]:
                        with contextlib.suppress(OSError):
                            os.read(fd, 65536)
                self.assertIsNone(pid, "TUI 未正常退出")
            finally:
                if pid is not None:
                    os.kill(pid, signal.SIGTERM)
                    os.waitpid(pid, 0)
                os.close(fd)


if __name__ == "__main__":
    unittest.main()
