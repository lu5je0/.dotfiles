"""挂载失败回收和未挂载时的进程清理；不访问真实仓库或 FUSE。"""

import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from test_q_restic import q, test_config


class BrowseProcessTests(unittest.TestCase):
    def setUp(self):
        self.cfg = test_config()
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        self.enterContext(patch.object(q, 'restic_bin', return_value='restic'))
        self.enterContext(patch.object(q, 'require_fuse'))
        self.enterContext(patch.object(q, 'user_mkdir'))
        self.enterContext(patch.object(q, 'user_open', return_value=io.StringIO()))
        self.enterContext(patch.object(q, 'stop_mount_processes', return_value=0))
        self.mounted = self.enterContext(patch.object(q, 'is_mounted', return_value=False))
        self.sleep = self.enterContext(patch.object(q.time, 'sleep'))
        self.enterContext(patch.object(q.shutil, 'which', return_value=None))
        self.process = Mock(pid=123)
        self.process.poll.return_value = None
        self.popen = self.enterContext(patch.object(q.subprocess, 'Popen', return_value=self.process))

    def test_timeout_terminates_and_waits_for_background_process(self):
        with self.assertRaises(SystemExit):
            q.do_browse(self.cfg)
        self.process.terminate.assert_called_once()
        self.process.wait.assert_called_once_with(timeout=5)

    def test_early_exit_reports_failure_without_waiting_for_timeout(self):
        self.process.poll.return_value = 1
        with self.assertRaises(SystemExit):
            q.do_browse(self.cfg)
        self.sleep.assert_not_called()
        self.process.terminate.assert_not_called()
        self.process.wait.assert_called_once_with(timeout=5)

    def test_interrupt_reaps_background_process(self):
        self.sleep.side_effect = KeyboardInterrupt
        with self.assertRaises(KeyboardInterrupt):
            q.do_browse(self.cfg)
        self.process.terminate.assert_called_once()
        self.process.wait.assert_called_once_with(timeout=5)

    def test_success_keeps_background_mount_running(self):
        self.mounted.side_effect = [False, True]
        self.assertEqual(q.do_browse(self.cfg), 0)
        self.process.terminate.assert_not_called()
        self.process.wait.assert_not_called()

    def test_failure_to_stop_is_reported(self):
        self.process.wait.side_effect = subprocess.TimeoutExpired('restic', 5)
        with self.assertRaises(SystemExit):
            q.do_browse(self.cfg)


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux /proc 进程回收')
class MountProcessTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='q-restic-mount-', dir='/tmp')))
        self.cfg = test_config(repository=str(self.root / 'repo'), mount_dir=str(self.root / 'target'))
        # Python 用 argv[0]=restic 运行名为 mount 的脚本，模拟相同命令行及环境。
        (self.root / 'mount').write_text(
            'import os, time\nfrom pathlib import Path\n'
            'Path(str(os.getpid()) + ".ready").touch()\ntime.sleep(60)\n'
        )
        self.processes = []
        self.addCleanup(self.cleanup_processes)
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def cleanup_processes(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)

    def start_mount(self, **changes):
        cfg = dict(self.cfg, **changes)
        argv = ['restic', 'mount', cfg['mount_dir']] + q.snapshot_args(cfg)
        process = subprocess.Popen(argv, executable=sys.executable, cwd=self.root,
                                   env=q.restic_env(cfg), stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        self.processes.append(process)
        deadline = time.monotonic() + 5
        while not (self.root / f'{process.pid}.ready').exists():
            if process.poll() is not None or time.monotonic() >= deadline:
                self.fail('假挂载进程未启动')
            time.sleep(0.01)
        return process

    def test_unmount_without_mountpoint_stops_only_matching_mount(self):
        matching = self.start_mount()
        others = [self.start_mount(repository=str(self.root / 'other-repo')),
                  self.start_mount(mount_dir=str(self.root / 'other-target')),
                  self.start_mount(_profile_tag='other-profile'),
                  self.start_mount(host='other-host')]
        with patch.object(q, 'is_mounted', return_value=False):
            self.assertEqual(q.do_unmount(self.cfg), 0)
        matching.wait(timeout=5)
        self.assertTrue(all(process.poll() is None for process in others))
        # 重复卸载不受已退出的 PID 影响。
        self.assertEqual(q.stop_mount_processes(self.cfg, q.mount_point(self.cfg)), 0)

    def test_fallback_without_pidfd_also_waits_for_exit(self):
        process = self.start_mount()
        with patch.object(q.os, 'pidfd_open', side_effect=OSError(q.errno.ENOSYS, 'unavailable'),
                          create=True):
            self.assertEqual(q.stop_mount_processes(self.cfg, q.mount_point(self.cfg)), 1)
        process.wait(timeout=5)

    def test_changed_identity_is_not_signalled(self):
        process = self.start_mount()
        original = q.mount_process_identity
        reads = 0

        def identity(proc, *args):
            nonlocal reads
            if proc.name == str(process.pid):
                reads += 1
                if reads > 1:
                    return 'different-start-time'
            return original(proc, *args)

        with patch.object(q, 'mount_process_identity', side_effect=identity):
            self.assertEqual(q.stop_mount_processes(self.cfg, q.mount_point(self.cfg)), 0)
        self.assertIsNone(process.poll())

    def test_wrong_user_is_not_matched(self):
        process = self.start_mount()
        self.assertIsNone(q.mount_process_identity(
            Path(f'/proc/{process.pid}'), os.getuid() + 1,
            ['mount', self.cfg['mount_dir']] + q.snapshot_args(self.cfg), self.cfg['repository']))

    @unittest.skipUnless(hasattr(os, 'pidfd_open') and hasattr(q.signal, 'pidfd_send_signal'),
                         '需要 pidfd')
    def test_unresponsive_process_is_reported_as_failure(self):
        process = self.start_mount()
        with patch.object(q.signal, 'pidfd_send_signal'), patch.object(
            q.select, 'select', return_value=([], [], [])
        ), contextlib.redirect_stderr(io.StringIO()) as err, self.assertRaises(SystemExit):
            q.stop_mount_processes(self.cfg, q.mount_point(self.cfg))
        self.assertIn('仍未退出', err.getvalue())
        self.assertIsNone(process.poll())


if __name__ == '__main__':
    unittest.main()
