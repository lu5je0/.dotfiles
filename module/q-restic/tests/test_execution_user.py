"""Execution identities, shared locks, and fixed-password repositories.

Run this file as namespace root to exercise real UID/GID transitions as well.
"""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_q_restic import q, test_config


class ExecutionUserTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.root.chmod(0o755)
        self.home = self.root / 'home'
        self.home.mkdir()
        real_lookup = pwd.getpwnam
        original = real_lookup('nobody') if os.geteuid() == 0 else pwd.getpwuid(os.geteuid())
        values = list(original)
        values[5] = str(self.home)
        self.account = pwd.struct_passwd(values)
        if os.geteuid() == 0:
            os.chown(self.home, self.account.pw_uid, self.account.pw_gid)
        self.enterContext(patch.object(q.pwd, 'getpwnam', side_effect=lambda name:
            self.account if name == self.account.pw_name else real_lookup(name)))
        self.cfg = test_config(run_as=self.account.pw_name, sources=[str(self.home / 'source')],
                               repository=str(self.home / 'repo'))
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))

    def test_target_home_environment_paths_and_remote_url_are_consistent(self):
        with patch.dict(os.environ, {'HOME': '/wrong', 'XDG_CACHE_HOME': '/wrong/cache',
                                    'RESTIC_PASSWORD_FILE': '/wrong/password',
                                    'RESTIC_PASSWORD_COMMAND': 'false', 'RESTIC_PASSWORD': 'wrong'}):
            cfg = test_config(run_as=self.account.pw_name, sources=['$HOME/data', '~/other'],
                              repository='sftp://user@host:22//repo')
            self.assertEqual(cfg['sources'], [str(self.home/'data'), str(self.home/'other')])
            self.assertEqual(cfg['repository'], 'sftp://user@host:22//repo')
            env = q.restic_env(cfg)
            self.assertEqual(env['HOME'], str(self.home))
            self.assertEqual(env['RESTIC_CACHE_DIR'], str(self.home/'.cache/restic'))
            self.assertEqual(env['RESTIC_PASSWORD'], 'lu5je0')
            self.assertNotIn('RESTIC_PASSWORD_FILE', env)
            self.assertNotIn('RESTIC_PASSWORD_COMMAND', env)
            self.assertNotIn('password_file', cfg)

    def test_invalid_or_unavailable_identity_does_not_silently_fallback(self):
        for value in ('', 123, 'q-restic-nonexistent-account-123'):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                test_config(run_as=value)
        with patch.object(q.os, 'geteuid', return_value=self.account.pw_uid + 100000):
            with self.assertRaisesRegex(PermissionError, 'sudo'):
                q.execution_options(self.cfg)
        cfg = dict(self.cfg, hooks_run_as='root')
        with patch.object(q.os, 'geteuid', return_value=12345):
            with self.assertRaisesRegex(PermissionError, 'hook'):
                q.execution_options(cfg, hook=True)

    def test_subprocess_really_uses_selected_uid_gid_groups_and_home(self):
        result = q.run(sys.executable, self.cfg, ['-c',
            'import os,json; print(json.dumps([os.getuid(),os.getgid(),os.getgroups(),os.environ["HOME"],os.getcwd()]))'])
        self.assertEqual(result.returncode, 0, result.stderr)
        uid, gid, groups, home, cwd = json.loads(result.stdout)
        self.assertEqual(uid, self.account.pw_uid)
        self.assertEqual(home, str(self.home))
        self.assertEqual(cwd, str(self.home))
        if os.geteuid() == 0:
            self.assertEqual(gid, self.account.pw_gid)
            self.assertEqual(set(groups), set(os.getgrouplist(self.account.pw_name, self.account.pw_gid)))

    def test_user_files_and_lock_are_owned_by_target_and_lock_is_shared(self):
        q.user_mkdir(self.cfg, self.home/'mount')
        self.assertEqual((self.home/'mount').stat().st_uid, self.account.pw_uid)
        digest = hashlib.sha256(self.cfg['repository'].encode()).hexdigest()[:12]
        path = self.home/'.cache'/f'q-restic.{digest}.lock'
        probe = ['-c', 'import fcntl,sys; f=open(sys.argv[1],"r+"); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)', str(path)]
        with patch.dict(os.environ, {'XDG_CACHE_HOME': '/wrong/cache'}):
            with q.writer_lock(self.cfg):
                self.assertEqual(path.stat().st_uid, self.account.pw_uid)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                blocked = q.run(sys.executable, self.cfg, probe)
                self.assertNotEqual(blocked.returncode, 0)
                self.assertIn('BlockingIOError', blocked.stderr)
            self.assertEqual(q.run(sys.executable, self.cfg, probe).returncode, 0)
        link = self.home/'link'
        link.symlink_to(path)
        with self.assertRaises(OSError):
            q.user_open(self.cfg, link)

    @unittest.skipUnless(shutil.which('restic'), 'restic unavailable')
    def test_new_repository_and_restore_work_without_any_password_file(self):
        q.user_mkdir(self.cfg, self.home/'source')
        with q.user_open(self.cfg, self.home/'source/data', truncate=True) as out:
            out.write('test content')
        self.cfg['keep'] = {}
        self.assertEqual(q.do_backup(self.cfg), 0)
        snaps = q.snapshots(q.restic_bin(), self.cfg)
        self.assertEqual(len(snaps), 1)
        self.assertEqual(q.do_backup(self.cfg, dry_run=True), 0)
        self.assertEqual(len(q.snapshots(q.restic_bin(), self.cfg)), 1)
        self.assertTrue(all(p.stat().st_uid == self.account.pw_uid
                            for p in (self.home/'repo').rglob('*')))
        self.assertEqual(q.do_restore(self.cfg, 'latest', str(self.home/'restore')), 0)
        restored = self.home/'restore'/str(self.home/'source/data').lstrip('/')
        self.assertEqual(restored.read_text(), 'test content')
        self.assertEqual(restored.stat().st_uid, self.account.pw_uid)

    @unittest.skipUnless(os.geteuid() == 0, 'requires root or a mapped user namespace')
    def test_root_hook_is_explicit_and_receives_backup_owner(self):
        marker = self.root/'root-hook.json'
        hook = [sys.executable, '-c',
                'import json,os,sys; from pathlib import Path; '
                'Path(sys.argv[1]).write_text(json.dumps([os.getuid(),os.environ["Q_RESTIC_UID"],os.environ["Q_RESTIC_GID"]]))', str(marker)]
        cfg = dict(self.cfg, hooks_run_as='root', hooks={'before_backup': hook},
                   _config_file=str(self.root/'config.json'))
        self.assertEqual(q.run_backup_hook(cfg, 'before_backup'), 0)
        self.assertEqual(json.loads(marker.read_text()),
                         [0, str(self.account.pw_uid), str(self.account.pw_gid)])
        self.assertEqual(marker.stat().st_uid, 0)
        # Without the explicit root hook setting, the same write must fail.
        marker.unlink()
        del cfg['hooks_run_as']
        self.assertNotEqual(q.run_backup_hook(cfg, 'before_backup'), 0)
        self.assertFalse(marker.exists())

    def test_password_setup_command_and_menu_are_removed(self):
        with self.assertRaises(SystemExit):
            q.build_parser().parse_args(['set-password'])
        app = q.App({'profiles': {'home': self.cfg}}, profile='home')
        self.assertFalse(any('密码' in item['label'] for item in app.menu_items()))
