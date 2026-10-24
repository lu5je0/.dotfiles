"""Linux ambient capability integration; run under unshare --map-auto --map-root-user.

Uses only a temporary repository, never the configured home backup.
"""
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'linux' and os.geteuid() == 0
                     and shutil.which('restic') and shutil.which('setpriv'),
                     'requires Linux root (or mapped user namespace), restic and setpriv')
class BackupCapabilityTests(unittest.TestCase):
    def test_private_source_backup_and_unprivileged_read(self):
        account = pwd.getpwnam('nobody')
        source_file = Path(__file__).resolve().parents[1] / 'q-restic.py'
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            root.chmod(0o755)
            source_copy = root / 'q-restic.py'
            shutil.copyfile(source_file, source_copy)
            source_copy.chmod(0o644)
            home = root / 'home'
            home.mkdir()
            os.chown(home, account.pw_uid, account.pw_gid)
            private = home / 'private'
            private.mkdir(mode=0o700)
            secret = private / 'secret'
            secret.write_text('root private backup content')
            secret.chmod(0o600)
            child = r'''
import importlib.util, json, os, pathlib, pwd, sys
from unittest.mock import patch
source, home, mode = sys.argv[1:]
spec = importlib.util.spec_from_file_location('q_restic', source)
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
account = list(pwd.getpwuid(os.geteuid()))
account[5] = home
account = pwd.struct_passwd(account)
secret = pathlib.Path(home) / 'private/secret'
with patch.object(q.pwd, 'getpwnam', return_value=account):
    cfg = q.profile_config({'profiles': {'home': {
        'run_as': account.pw_name, 'repository': home + '/repo',
        'sources': [home + '/private'], 'keep': {}, 'host': 'cap-test'
    }}}, 'home')
    assert os.geteuid() != 0
    if mode == 'backup':
        assert secret.read_text() == 'root private backup content'
        try:
            secret.write_text('must not overwrite')
        except PermissionError:
            pass
        else:
            raise AssertionError('read capability must not grant write access')
        assert q.do_backup(cfg) == 0
    else:
        try:
            secret.read_text()
        except PermissionError:
            pass
        else:
            raise AssertionError('ordinary viewer unexpectedly reads private source')
        if mode == 'view':
            snaps = q.snapshots(q.restic_bin(), cfg)
            assert len(snaps) == 1
            result = q.run(q.restic_bin(), cfg, ['dump', snaps[0]['id'], str(secret)])
            assert result.returncode == 0, result.stderr
            assert result.stdout == 'root private backup content'
            result = q.run(q.restic_bin(), cfg, ['ls', '--json', snaps[0]['id']])
            assert result.returncode == 0, result.stderr
            nodes = [json.loads(line) for line in result.stdout.splitlines()]
            node = next(n for n in nodes if n.get('path') == str(secret))
            assert node['uid'] == 0 and node['gid'] == 0, node
            assert node['mode'] & 0o777 == 0o600, node
'''
            base = ['setpriv', '--no-new-privs', f'--reuid={account.pw_uid}',
                    f'--regid={account.pw_gid}', '--clear-groups']
            for mode in ('unreadable', 'backup', 'view'):
                caps = '-all,+dac_read_search' if mode == 'backup' else '-all'
                result = subprocess.run(base + [f'--bounding-set={caps}',
                    f'--inh-caps={caps}', f'--ambient-caps={caps}',
                    sys.executable, '-B', '-c', child, str(source_copy), str(home), mode],
                    capture_output=True, text=True, timeout=90)
                self.assertEqual(result.returncode, 0, f'{mode}: {result.stdout}\n{result.stderr}')
            self.assertTrue(all(p.stat().st_uid == account.pw_uid
                                for p in (home/'repo').rglob('*')))
            self.assertEqual(secret.stat().st_uid, 0)
            self.assertEqual(secret.stat().st_mode & 0o777, 0o600)
            self.assertTrue(list((home/'.cache').glob('q-restic.*.lock')))
            self.assertTrue(all(p.stat().st_uid == account.pw_uid
                                for p in (home/'.cache').rglob('*')))
