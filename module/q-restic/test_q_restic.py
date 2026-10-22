"""备份清理、异步加载、错误恢复和缓存回归；只用假 restic，不连接真实仓库。"""

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


def raw_profile(**overrides):
    cfg = dict(repository="/tmp/test-repo", password_file="/tmp/test-password", sources=["/tmp/source"],
               host="test", tag="home", snapshot_tag="home", mount_dir="/tmp/restic-mnt/test",
               restore_dir="/tmp/restic-restore/test", keep={"daily": 7, "weekly": 4, "monthly": 1})
    cfg.update(overrides)
    return cfg


def test_config(**overrides):
    return q.profile_config({"version": 2, "profiles": {"home": raw_profile(**overrides)}}, "home")


def test_app(cfg=None):
    document = {"version": 2, "profiles": {"home": cfg or raw_profile()}}
    return q.App(document, profile="home")


def snapshot(n):
    return {"id": str(n) * 64, "short_id": str(n) * 8,
            "time": f"2026-10-{n:02d}T12:00:00Z", "summary": {"total_bytes_processed": 1024}}


class DiffTests(unittest.TestCase):
    def setUp(self):
        self.app = q.App.__new__(q.App)
        self.app.cfg = test_config()
        self.app.restic = "restic"
        self.app.snaps = [snapshot(1), snapshot(2)]
        self.app.term = Mock()
        self.app.set_message = Mock()

    def test_diff_opens_readonly_neovim_and_cleans_file(self):
        paths = []

        def call(args, **kwargs):
            if args[0] == "restic":
                self.assertEqual(args, ["restic", "diff", "11111111", "22222222"])
                kwargs["stdout"].write(b"M    /home/test/file\n")
            else:
                self.assertEqual(args[:-1], [
                    "nvim", "-R", "-n", "+setlocal filetype=diff nomodifiable", "--",
                ])
                paths.append(Path(args[-1]))
                self.assertEqual(paths[-1].read_bytes(), b"M    /home/test/file\n")
            return 0

        with patch.object(q.subprocess, "call", side_effect=call):
            self.app.act_diff(self.app.snaps[1])
        self.assertFalse(paths[0].exists())
        self.app.term.suspend.assert_called_once()
        self.app.term.resume.assert_called_once()
        self.app.term.wait_key.assert_not_called()

    def test_failures_wait_before_resuming(self):
        for result in (11, FileNotFoundError("nvim")):
            with self.subTest(result=result):
                self.app.term.reset_mock()
                effects = [11] if result == 11 else [0, result]
                with patch.object(q.subprocess, "call", side_effect=effects):
                    self.app.act_diff(self.app.snaps[1])
                self.assertEqual([c[0] for c in self.app.term.mock_calls],
                                 ["suspend", "wait_key", "resume"])

    def test_first_snapshot_does_not_open_editor(self):
        with patch.object(q.subprocess, "call") as call:
            self.app.act_diff(self.app.snaps[0])
        call.assert_not_called()
        self.app.term.suspend.assert_not_called()


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.cfg = test_config()
        self.out, self.err = io.StringIO(), io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.out))
        self.enterContext(contextlib.redirect_stderr(self.err))
        self.enterContext(patch.object(q, "restic_bin", return_value="restic"))
        for name in ("require_password", "acquire_lock", "preflight_sftp", "ensure_repo"):
            self.enterContext(patch.object(q, name))

    def test_cleanup_failure_reaches_caller_without_claiming_success(self):
        for backup_code, forget_code, expected in ((0, 1, 1), (0, 11, 11), (0, 12, 12),
                                                    (3, 1, 3), (3, 11, 3)):
            with self.subTest(backup=backup_code, forget=forget_code), patch.object(
                q, "run_stream", return_value=backup_code
            ), patch.object(q, "do_forget", return_value=forget_code) as forget:
                self.out.seek(0)
                self.out.truncate()
                self.err.seek(0)
                self.err.truncate()
                self.assertEqual(q.do_backup(self.cfg), expected)
                forget.assert_called_once()
                self.assertIn(f"清理失败（退出码 {forget_code}）", self.err.getvalue())
                self.assertNotIn("完成", self.out.getvalue())
                self.assertNotIn("已按保留策略清理", self.out.getvalue())

    def test_cleanup_runs_after_both_complete_and_incomplete_backups(self):
        for code in (0, 3):
            with self.subTest(code=code), patch.object(q, "run_stream", return_value=code), patch.object(
                q, "do_forget", return_value=0
            ) as forget:
                self.assertEqual(q.do_backup(self.cfg), code)
                forget.assert_called_once()

    def test_failed_backups_and_dry_run_do_not_apply_retention(self):
        for code, dry_run in ((1, False), (10, False), (11, False), (12, False), (0, True), (3, True)):
            with self.subTest(code=code, dry_run=dry_run), patch.object(
                q, "run_stream", return_value=code
            ), patch.object(q, "do_forget") as forget:
                self.assertEqual(q.do_backup(self.cfg, dry_run=dry_run), code)
                forget.assert_not_called()

    def test_locked_cleanup_reports_recovery_command(self):
        for stream in (True, False):
            with self.subTest(stream=stream), patch.object(q, "run_stream", return_value=11), patch.object(
                q, "run", return_value=subprocess.CompletedProcess([], 11, "", "locked")
            ):
                self.assertEqual(q.do_forget("restic", self.cfg, stream=stream), 11)
        self.assertIn(q.command_hint(self.cfg, "unlock"), self.err.getvalue())
        self.assertIn(q.command_hint(self.cfg, "forget"), self.err.getvalue())

    def retention_group(self, matches, removed=()):
        return {"keep": [snapshot(n) for n in matches],
                "remove": [snapshot(n) for n in removed] or None,
                "reasons": [{"snapshot": snapshot(n), "matches": reasons}
                            for n, reasons in matches.items()]}

    def test_only_oldest_fallback_is_removed_and_groups_stay_independent(self):
        groups = [self.retention_group({
            1: ["oldest weekly snapshot", "oldest monthly snapshot"],
            2: ["weekly snapshot"],
            3: ["daily snapshot", "oldest weekly snapshot"],
        }, removed=(4,)), self.retention_group({5: ["daily snapshot"]})]
        self.assertEqual({s["id"] for s in q.retention_removals(groups)},
                         {snapshot(1)["id"], snapshot(4)["id"]})

    def test_single_snapshot_and_empty_repository_are_preserved(self):
        group = self.retention_group({1: ["daily snapshot", "weekly snapshot"]})
        self.assertEqual(q.retention_removals([group]), [])
        self.assertEqual(q.retention_removals([]), [])

    def test_invalid_preview_and_removing_whole_group_are_rejected(self):
        missing_reasons = self.retention_group({1: ["daily snapshot"]})
        missing_reasons["reasons"] = []
        for groups in (None, {}, [{}], [missing_reasons],
                       [self.retention_group({1: ["oldest weekly snapshot"]})],
                       [self.retention_group({1: []})]):
            with self.subTest(groups=groups), self.assertRaises(RuntimeError):
                q.retention_removals(groups)

    def test_cleanup_uses_exact_planned_ids_and_propagates_delete_failures(self):
        groups = [self.retention_group({1: ["oldest weekly snapshot"],
                                        2: ["weekly snapshot"]}, removed=(3,))]
        preview = subprocess.CompletedProcess([], 0, json.dumps(groups), "")
        expected_ids = {snapshot(1)["id"], snapshot(3)["id"]}
        for stream in (True, False):
            with self.subTest(stream=stream), patch.object(
                q, "run", side_effect=[preview, subprocess.CompletedProcess([], 12)]
            ) as run, patch.object(q, "run_stream", return_value=12) as run_stream:
                self.assertEqual(q.do_forget("restic", self.cfg, stream=stream), 12)
                preview_args = run.call_args_list[0].args[2]
                self.assertIn("--dry-run", preview_args)
                self.assertIn("--json", preview_args)
                self.assertEqual(preview_args[-4:], ["--host", "test", "--tag", "home"])
                delete_args = (run_stream if stream else run).call_args.args[2]
                self.assertEqual(set(delete_args[1:3]), expected_ids)
                self.assertEqual(delete_args[3:], ["--prune", "--host", "test", "--tag", "home"])

    def test_dry_run_empty_and_failed_previews_never_delete(self):
        groups = [self.retention_group({1: ["oldest weekly snapshot"],
                                        2: ["weekly snapshot"]})]
        for result, dry_run, expected in (
            (subprocess.CompletedProcess([], 0, json.dumps(groups), ""), True, 0),
            (subprocess.CompletedProcess([], 0, "[]", ""), False, 0),
            (subprocess.CompletedProcess([], 0, "broken", ""), False, 1),
            (subprocess.CompletedProcess([], 0, "[{}]", ""), False, 1),
            (subprocess.CompletedProcess([], 12, "", "wrong password"), False, 12),
        ):
            with self.subTest(result=result, dry_run=dry_run), patch.object(
                q, "run", return_value=result
            ) as run, patch.object(q, "run_stream") as delete:
                self.assertEqual(q.do_forget("restic", self.cfg, dry_run=dry_run), expected)
                run.assert_called_once()
                delete.assert_not_called()

    def test_cli_cleanup_preview_does_not_take_write_lock(self):
        with patch.object(q, "load_config", return_value={"version": 2, "profiles": {}}), patch.object(q, "profile_config", return_value=self.cfg), patch.object(
            q, "do_forget", return_value=0
        ) as forget, patch.object(q, "acquire_lock") as lock, patch.object(
            sys, "argv", ["q-restic", "-p", "home", "forget", "--dry-run"]
        ):
            self.assertEqual(q.main(), 0)
        lock.assert_not_called()
        forget.assert_called_once_with("restic", self.cfg, dry_run=True)

    def test_empty_preview_is_only_successful_for_confirmed_empty_repository(self):
        for snaps, expected in (([], 0), ([snapshot(1)], 1)):
            with self.subTest(snaps=snaps), patch.object(
                q, "run", return_value=subprocess.CompletedProcess([], 0, "", "")
            ), patch.object(q, "snapshots", return_value=snaps), patch.object(q, "run_stream") as delete:
                self.assertEqual(q.do_forget("restic", self.cfg), expected)
                delete.assert_not_called()

    def test_unlock_cannot_report_read_failure_as_no_locks(self):
        with patch.object(q, "run", return_value=subprocess.CompletedProcess([], 12, "", "wrong password")), patch.object(
            q, "run_stream"
        ) as unlock:
            self.assertEqual(q.do_unlock(self.cfg), 12)
        unlock.assert_not_called()
        self.assertIn("wrong password", self.err.getvalue())
        self.assertNotIn("没有锁", self.out.getvalue())

    def test_unlock_serializes_writes_and_only_removes_stale_locks(self):
        with patch.object(q, "run", return_value=subprocess.CompletedProcess([], 0, "lock-id\n", "")), patch.object(
            q, "run_stream", return_value=0
        ) as unlock, patch.object(q, "acquire_lock") as lock:
            self.assertEqual(q.do_unlock(self.cfg), 0)
        lock.assert_called_once_with(self.cfg)
        unlock.assert_called_once_with("restic", self.cfg, ["unlock"])

    def test_tui_does_not_claim_incomplete_backup_was_cleaned(self):
        app = test_app(self.cfg)
        with patch.object(app, "run_suspended", return_value=3):
            app.act_backup()
        self.assertIn("备份不完整", app.message)
        self.assertNotIn("已清理", app.message)
        with patch.object(app, "run_suspended", return_value=11):
            app.act_backup()
        self.assertIn("清理失败", app.message)


class LoadingTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(q, "acquire_lock"))
        self.enterContext(patch.object(q, "password_ready", return_value=True))
        self.enterContext(patch.object(q.shutil, "which", return_value="restic"))
        self.app = test_app()
        self.app.restic = "restic"

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
            cfg = raw_profile(repository=str(root / "repo"), host="test", password_file=str(root / "password"))
            (root / "password").write_text("test-password\n")
            (root / "q-restic/config.json").write_text(json.dumps({"version": 2, "profiles": {"home": cfg}}))
            (root / "offline").touch()
            fake = root / "restic"
            fake.write_text("#!" + sys.executable + "\n" + '''import json, os, sys, time
from pathlib import Path
root = Path(os.environ['XDG_CONFIG_HOME'])
with (root / 'calls').open('a') as log:
    log.write(sys.argv[1] + '\\n')
assert sys.argv[-4:] == ['--host', 'test', '--tag', 'home']
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
                os.execv(sys.executable, [sys.executable, str(SOURCE), "-p", "home"])
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
                os.write(fd, b"hqq")
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
