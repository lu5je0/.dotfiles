"""Missing-repository handling without hiding authentication and connectivity failures."""
import contextlib
import fcntl
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

from test_q_restic import q, SOURCE, raw_profile, snapshot


class RepositoryStateTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.raw = raw_profile(repository=str(self.root/'repo'))
        self.document = {'profiles': {'home': self.raw}}
        self.cfg = q.profile_config(self.document, 'home')
        self.app = q.App(self.document, profile='home')
        self.enterContext(patch.object(q.shutil, 'which', return_value='restic'))

    def until_loaded(self):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            self.app.poll_data()
            if not self.app.loading:
                return
            time.sleep(.005)
        self.fail('snapshot load did not finish')

    def test_modern_and_legacy_local_missing_repository_are_recognized(self):
        for code, stderr in [(10, 'repository does not exist'),
                             (1, 'Fatal: unable to open config file: stat /repo/config: no such file or directory')]:
            with self.subTest(code=code), patch.object(q, 'run', return_value=subprocess.CompletedProcess([], code, '', stderr)):
                self.assertFalse(q.repo_ready('restic', self.cfg))
                with self.assertRaises(q.RepositoryNotInitialized):
                    q.snapshots('restic', self.cfg)
        self.assertFalse((self.root/'repo').exists())

    def test_failures_are_not_missing_and_never_initialize_repository(self):
        cases = [(12, 'wrong password'), (1, 'wrong password or no key found'),
                 (1, 'unable to open config file: permission denied'),
                 (1, 'ssh: connection refused'), (1, 'invalid config file')]
        for code, error in cases:
            result = subprocess.CompletedProcess([], code, '', error)
            with self.subTest(error=error), patch.object(q, 'run', return_value=result), patch.object(q, 'run_stream') as initialize, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, error):
                    q.snapshots('restic', self.cfg)
                with self.assertRaises(SystemExit):
                    q.ensure_repo('restic', self.cfg)
                initialize.assert_not_called()

    def test_legacy_missing_error_with_existing_config_is_not_masked(self):
        (self.root/'repo').mkdir()
        (self.root/'repo/config').write_text('exists')
        result = subprocess.CompletedProcess([], 1, '', 'unable to open config file: no such file or directory')
        self.assertFalse(q.repository_missing(result, self.cfg))
        with patch.object(q.Path, 'stat', side_effect=PermissionError):
            self.assertFalse(q.repository_missing(result, self.cfg))
        self.assertFalse(q.repository_missing(result, dict(self.cfg, repository='sftp:user@host:/repo')))

    def test_cli_status_explains_first_backup_without_creating_repository(self):
        with patch.object(q, 'restic_bin'), patch.object(q, 'snapshots', side_effect=q.RepositoryNotInitialized('仓库未初始化')), contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(q.do_status(self.cfg), 0)
        self.assertIn('仓库未初始化', out.getvalue())
        self.assertIn('backup', out.getvalue())
        self.assertEqual(err.getvalue(), '')
        self.assertFalse((self.root/'repo').exists())

    def test_tui_uninitialized_state_skips_stats_and_resets_after_first_snapshot(self):
        self.app.screen = 'snapshots'
        with patch.object(q, 'snapshots', side_effect=q.RepositoryNotInitialized('仓库未初始化')), patch.object(q, 'repo_stats') as stats:
            self.app.refresh()
            self.until_loaded()
            self.assertTrue(self.app.repo_uninitialized)
            self.assertEqual(self.app.load_error, '')
            self.assertEqual(self.app.snaps, [])
            self.assertIn('仓库未初始化', ''.join(self.app.header(100)))
            self.assertIn('初始化', self.app.snapshot_items()[0]['label'])
            self.assertIn('首次备份', self.app.detail_text())
            self.assertNotIn('读取仓库失败', ''.join(self.app.footer(100)))
            self.app.poll_data()
            stats.assert_not_called()
        with patch.object(q, 'snapshots', return_value=[snapshot(1)]), patch.object(q, 'repo_stats', return_value={'total_size': 42}):
            self.app.refresh()
            self.until_loaded()
            self.assertFalse(self.app.repo_uninitialized)
            self.assertEqual(self.app.snaps, [snapshot(1)])
            deadline = time.monotonic() + 3
            while self.app.repo_size_loading and time.monotonic() < deadline:
                self.app.poll_data()
                time.sleep(.005)
            self.assertTrue(self.app.repo_size_loaded)
            self.app.go_back()

    def test_disappeared_repository_preserves_previously_loaded_snapshots(self):
        self.app.snaps = [snapshot(1)]
        with patch.object(q, 'snapshots', side_effect=q.RepositoryNotInitialized('仓库未初始化')):
            self.app.refresh()
            self.until_loaded()
        self.assertFalse(self.app.repo_uninitialized)
        self.assertEqual(self.app.snaps, [snapshot(1)])
        self.assertIn('仓库未初始化', self.app.load_error)

    def test_switching_profiles_clears_missing_state_and_ignores_stale_missing_result(self):
        self.document['profiles']['other'] = raw_profile(repository=str(self.root/'other'))
        self.app.repo_uninitialized = True
        stale = self.app._requests['snapshots'] = object()
        with patch.object(q, 'snapshots', return_value=[snapshot(2)]):
            self.app.select_profile('other')
            self.until_loaded()
        self.app._results.put(('snapshots', stale, None, q.RepositoryNotInitialized('old repository')))
        self.app.poll_data()
        self.assertFalse(self.app.repo_uninitialized)
        self.assertEqual(self.app.snaps, [snapshot(2)])
        self.assertEqual(self.app.load_error, '')


@unittest.skipUnless(shutil.which('restic'), 'restic unavailable')
class NativeRepositoryTests(unittest.TestCase):
    def test_readonly_missing_repository_and_first_backup_in_real_pty(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            (root/'source').mkdir()
            (root/'source/file').write_text('test data')
            password = root/'password'
            password.write_text('lu5je0\n')
            password.chmod(0o600)
            cfg = root/'config.json'
            cfg.write_text(json.dumps({'profiles': {'home': dict(sources=[str(root/'source')],
                repository=str(root/'repo'), password_file=str(password), host='test')}}))
            env = dict(os.environ, TERM='xterm-256color', XDG_CACHE_HOME=str(root/'cache'))
            def cli(command):
                return subprocess.run([sys.executable, str(SOURCE), '-c', str(cfg), '-p', 'home', command],
                    capture_output=True, text=True, env=env)
            result = cli('status')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('仓库未初始化', result.stdout)
            self.assertFalse((root/'repo').exists())
            pid, fd = pty.fork()
            if pid == 0:
                os.environ.update(env)
                os.execv(sys.executable, [sys.executable, str(SOURCE), '-c', str(cfg), '-p', 'home'])
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 28, 120, 0, 0))
            def read_until(text):
                output = bytearray()
                deadline = time.monotonic()+5
                while time.monotonic() < deadline:
                    if select.select([fd], [], [], .05)[0]:
                        try: output.extend(os.read(fd,65536))
                        except OSError: break
                        decoded = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', output.decode('utf-8','replace'))
                        if text in decoded: return decoded
                self.fail(f'missing {text!r}: {output[-2000:]!r}')
            try:
                screen = read_until('仓库未初始化')
                self.assertNotIn('读取仓库失败', screen)
                os.write(fd, b'jj\r')
                screen = read_until('首次备份将自动初始化仓库')
                self.assertNotIn('统计中', screen)
                self.assertFalse((root/'repo').exists())
                os.write(fd,b'hqq')
                deadline = time.monotonic()+3
                while time.monotonic()<deadline:
                    child,status = os.waitpid(pid,os.WNOHANG)
                    if child:
                        pid = None
                        self.assertEqual(status,0)
                        break
                    if select.select([fd],[],[],.05)[0]:
                        with contextlib.suppress(OSError):os.read(fd,65536)
                self.assertIsNone(pid,'TUI did not exit')
            finally:
                if pid is not None:
                    with contextlib.suppress(ProcessLookupError):os.kill(pid,signal.SIGTERM)
                    os.waitpid(pid,0)
                os.close(fd)
            backup = cli('backup')
            self.assertEqual(backup.returncode,0,backup.stdout+backup.stderr)
            self.assertTrue((root/'repo/config').exists())
            result = cli('status')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertNotIn('仓库未初始化',result.stdout)
            self.assertIn('q-restic:profile:home',result.stdout)
