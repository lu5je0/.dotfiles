"""Preparation/recovery ordering, failures, and termination against temporary hooks."""
import contextlib
import io
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_q_restic import q, SOURCE, test_config


class BackupHookTests(unittest.TestCase):
    def setUp(self):
        self.cfg = test_config(hooks={'before_backup': ['prepare'], 'after_backup': ['finish']})
        self.events = []
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        self.enterContext(patch.object(q, 'restic_bin', return_value='restic'))
        self.enterContext(patch.object(q, 'require_password'))
        self.enterContext(patch.object(q, 'writer_lock', side_effect=lambda cfg: contextlib.nullcontext()))
        for name in ('preflight_sftp', 'ensure_repo'):
            self.enterContext(patch.object(q, name, side_effect=lambda *args, n=name: self.events.append(n)))

    def hook(self, cfg, name):
        self.events.append(name)
        return 0

    def backup(self, *args):
        self.events.append('backup')
        return 3

    def forget(self, *args, **kwargs):
        self.events.append('forget')
        return 0

    def test_recovery_precedes_retention_even_for_incomplete_backup(self):
        with patch.object(q, 'run_backup_hook', side_effect=self.hook), patch.object(
                q, 'run_stream', side_effect=self.backup), patch.object(q, 'do_forget', side_effect=self.forget):
            self.assertEqual(q.do_backup(self.cfg), 3)
        self.assertEqual(self.events, ['before_backup', 'preflight_sftp', 'ensure_repo', 'backup', 'after_backup', 'forget'])

    def test_failed_preparation_or_backup_still_recovers_without_pruning(self):
        for failure in ('before_backup', 'backup', 'ensure_repo'):
            self.events.clear()
            def hook(cfg, name):
                self.events.append(name)
                return 7 if name == failure else 0
            with patch.object(q, 'run_backup_hook', side_effect=hook), patch.object(q, 'run_stream', return_value=8), patch.object(q, 'do_forget') as forget:
                if failure == 'ensure_repo':
                    with patch.object(q, 'ensure_repo', side_effect=SystemExit(9)), self.assertRaises(SystemExit):
                        q.do_backup(self.cfg)
                else:
                    self.assertEqual(q.do_backup(self.cfg), 7 if failure == 'before_backup' else 8)
                forget.assert_not_called()
                self.assertEqual(self.events[-1], 'after_backup')

    def test_recovery_failure_is_nonzero_and_never_prunes(self):
        with patch.object(q, 'run_backup_hook', side_effect=[0, 6]), patch.object(q, 'run_stream', return_value=0), patch.object(q, 'do_forget') as forget:
            self.assertEqual(q.do_backup(self.cfg), 6)
            forget.assert_not_called()

    def test_dry_run_never_prepares_or_initializes_repository(self):
        with patch.object(q, 'run_backup_hook') as hook, patch.object(q, 'run_stream', return_value=0):
            self.assertEqual(q.do_backup(self.cfg, dry_run=True), 0)
            hook.assert_not_called()
        self.assertEqual(self.events, [])

    def test_hook_cwd_argv_and_profile_context_without_shell(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            result = root / 'result.json'
            cfg = dict(self.cfg, hooks={'before_backup': [sys.executable, '-c',
                'import json,os,sys; open("result.json","w").write(json.dumps([os.getcwd(),os.environ["Q_RESTIC_CONFIG"],os.environ["Q_RESTIC_PROFILE"],sys.argv[1]]))', '$(not-a-shell)']})
            with patch.object(q, 'CONFIG_FILE', root / 'config.json'):
                self.assertEqual(q.run_backup_hook(cfg, 'before_backup'), 0)
            self.assertEqual(json.loads(result.read_text()), [str(root), str(root/'config.json'), 'home', '$(not-a-shell)'])

    def test_invalid_hook_shapes_are_rejected(self):
        for hooks in ('cmd', {'unknown': ['cmd']}, {'before_backup': 'cmd'}, {'before_backup': []}, {'after_backup': [1]}):
            with self.subTest(hooks=hooks), self.assertRaises(SystemExit):
                test_config(hooks=hooks)

    def test_sigterm_runs_recovery_and_releases_writer_lock(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            marker = root / 'recovered'
            program = '''import importlib.util,sys,time
s=importlib.util.spec_from_file_location('q',sys.argv[1]); q=importlib.util.module_from_spec(s); s.loader.exec_module(q)
from pathlib import Path
q.CONFIG_FILE=Path(sys.argv[2])/'config.json'
q.restic_bin=lambda:'restic'
q.require_password=lambda cfg:None
q.preflight_sftp=lambda cfg:None
q.ensure_repo=lambda *args:None
def backup(*args):
 from pathlib import Path
 Path(sys.argv[2]+'/ready').touch()
 while True: time.sleep(.1)
q.run_stream=backup
cfg={'sources':['/tmp/source'],'repository':sys.argv[2]+'/repo','host':'test','hooks':{'after_backup':[sys.executable,'-c','from pathlib import Path; Path('+repr(sys.argv[2]+'/recovered')+').write_text("ok")']}}
q.do_backup(cfg)
'''
            env = dict(os.environ, XDG_CACHE_HOME=str(root/'cache'))
            proc = subprocess.Popen([sys.executable, '-u', '-c', program, str(SOURCE), str(root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            try:
                import time
                deadline = time.monotonic() + 10
                ready = False
                while time.monotonic() < deadline:
                    if (root/'ready').exists():
                        ready = True
                        break
                    time.sleep(.05)
                self.assertTrue(ready, 'backup did not start')
                proc.send_signal(signal.SIGTERM)
                out, err = proc.communicate(timeout=15)
                self.assertEqual(proc.returncode, 143, out+err)
                self.assertEqual(marker.read_text(), 'ok')
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.communicate()


class PreflightTests(unittest.TestCase):
    def test_preflight_keeps_callers_identity_without_repository_or_password(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            cfg = root/'config.json'
            cfg.write_text(json.dumps({'profiles': {'home': dict(sources=['./source'], repository=str(root/'repo'),
                password_file=str(root/'no-password'), hooks={'preflight': [sys.executable, '-c',
                'import os,json; from pathlib import Path; Path("identity.json").write_text(json.dumps([os.getuid(),os.getgid(),os.environ.get("HOME"),os.getcwd()]))']})}}))
            result = subprocess.run([sys.executable, str(SOURCE), '-c', str(cfg), '-p', 'home', 'preflight'],
                capture_output=True, text=True, cwd='/tmp')
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertEqual(json.loads((root/'identity.json').read_text()),
                [os.getuid(), os.getgid(), os.environ.get('HOME'), str(root)])
            self.assertFalse((root/'repo').exists())
            self.assertFalse((root/'no-password').exists())

    def test_unconfigured_preflight_fails_without_creating_repository(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            cfg = root/'config.json'
            cfg.write_text(json.dumps({'profiles': {'home': dict(sources=['./source'], repository=str(root/'repo'),
                password_file=str(root/'no-password'))}}))
            result = subprocess.run([sys.executable, str(SOURCE), '-c', str(cfg), '-p', 'home', 'preflight'],
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('hooks.preflight', result.stderr)
            self.assertFalse((root/'repo').exists())
