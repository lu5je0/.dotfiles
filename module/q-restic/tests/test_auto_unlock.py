"""自动清理残留锁，保留仍存活的本机 restic 进程持有的锁。"""

import contextlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from test_q_restic import q, test_config


class AutoUnlockTests(unittest.TestCase):
    def test_uses_native_stale_detection_without_force_or_snapshot_filters(self):
        cfg = test_config()
        with patch.object(q, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            self.assertEqual(q.unlock_stale_locks('restic', cfg), 0)
        run.assert_called_once_with('restic', cfg, ['unlock'])

    def test_unlock_error_propagates_with_diagnostic(self):
        with patch.object(q, 'run', return_value=subprocess.CompletedProcess([], 12, '', 'wrong password')), \
             contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(q.unlock_stale_locks('restic', test_config()), 12)
        self.assertIn('wrong password', err.getvalue())


@unittest.skipUnless(shutil.which('restic'), 'requires restic')
class NativeAutoUnlockTests(unittest.TestCase):
    def test_active_lock_is_preserved_and_crashed_process_lock_is_removed_before_backup(self):
        with tempfile.TemporaryDirectory(prefix='q-restic-unlock-', dir='/tmp') as tmp:
            root = Path(tmp)
            source = root / 'source'
            source.mkdir()
            (source / 'file').write_text('backup content')
            cfg = test_config(repository=str(root / 'repo'), sources=[str(source)], keep={})
            restic = q.restic_bin()
            with contextlib.redirect_stdout(io.StringIO()), \
                 patch.dict(os.environ, {'XDG_CACHE_HOME': str(root / 'cache')}):
                q.ensure_repo(restic, cfg)
                # stdin 不关闭，让 restic 保持活动锁；不需要实际 FUSE 挂载。
                holder = subprocess.Popen(
                    [restic, 'backup', '--stdin', '--stdin-filename', 'held'],
                    env=q.restic_env(cfg), stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 10
                    locks = ''
                    while time.monotonic() < deadline:
                        result = q.run(restic, cfg, ['list', 'locks'])
                        self.assertEqual(result.returncode, 0, result.stderr)
                        locks = result.stdout.strip()
                        if locks:
                            break
                        self.assertIsNone(holder.poll())
                        time.sleep(.05)
                    self.assertTrue(locks, 'restic 未建立测试锁')
                    self.assertEqual(q.unlock_stale_locks(restic, cfg), 0)
                    self.assertEqual(q.run(restic, cfg, ['list', 'locks']).stdout.strip(), locks)
                    self.assertIsNone(holder.poll())
                    # 模拟异常退出；finally 中仍解锁，避免测试留下仓库锁。
                    holder.kill()
                    holder.wait(timeout=5)
                    self.assertEqual(q.run(restic, cfg, ['list', 'locks']).stdout.strip(), locks)
                    self.assertEqual(q.do_backup(cfg), 0)
                    self.assertEqual(q.run(restic, cfg, ['list', 'locks']).stdout.strip(), '')
                    self.assertEqual(len(q.snapshots(restic, cfg)), 1)
                finally:
                    if holder.poll() is None:
                        holder.terminate()
                    holder.wait(timeout=5)
                    holder.stdin.close()
                    q.run(restic, cfg, ['unlock'])


if __name__ == '__main__':
    unittest.main()
