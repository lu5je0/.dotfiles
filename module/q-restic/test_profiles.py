"""Profiles, local password setup, and isolation against temporary repositories."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_q_restic import q, SOURCE, snapshot


def profile(root, name, **extra):
    return dict(sources=[str(root / name)], repository=str(root / 'repo'),
                password_file=str(root / 'password'), host='test', **extra)


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.path = self.root / 'config.json'
        self.enterContext(patch.object(q, 'CONFIG_FILE', self.path))
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))

    def test_flat_configuration_is_rejected_and_save_is_atomic_private_json(self):
        self.path.write_text(json.dumps({'source': '/home/test', 'repository': '/repo'}))
        with self.assertRaises(SystemExit):
            q.load_config()
        document = {'version': 2, 'profiles': {'home': profile(self.root, 'home')}}
        q.save_config(document)
        self.assertEqual(q.load_config(), document)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_new_configuration_never_implies_a_home_backup(self):
        self.assertEqual(q.load_config(), {'version': 2, 'profiles': {}})
        with self.assertRaises(SystemExit):
            q.profile_config(q.load_config(), 'home')
        with self.assertRaises(SystemExit):
            q.profile_config({'profiles': {'home': {'repository': 'repo'}}}, 'home')

    def test_paths_resolve_against_configuration_directory(self):
        doc = {'profiles': {'immich': dict(sources=['./media', '$HOME/Documents'],
               repository='./repo', password_file='./password', excludes='./exclude',
               mount_dir='./mount', restore_dir='./restore')}}
        cfg = q.profile_config(doc, 'immich')
        self.assertEqual(cfg['sources'][0], str(self.root / 'media'))
        self.assertEqual(cfg['sources'][1], str(Path.home() / 'Documents'))
        for key, suffix in [('repository', 'repo'), ('password_file', 'password'),
                            ('excludes', 'exclude'), ('mount_dir', 'mount'), ('restore_dir', 'restore')]:
            self.assertEqual(cfg[key], str(self.root / suffix))
        self.assertEqual(cfg['_profile_tag'], 'q-restic:profile:immich')
        self.assertEqual(doc['profiles']['immich']['sources'], ['./media', '$HOME/Documents'])

    def test_profile_selection_is_required_even_with_one_profile(self):
        self.path.write_text(json.dumps({'version': 2, 'profiles': {'home': profile(self.root, 'home')}}))
        for command in ('backup', 'dry-run', 'status', 'snapshots', 'list', 'forget', 'restore', 'check', 'unlock'):
            with self.subTest(command=command), patch.object(sys, 'argv', ['q-restic', '-c', str(self.path), command]):
                with patch.object(q, 'restic_bin') as binary, self.assertRaises(SystemExit):
                    q.main()
                binary.assert_not_called()

    def test_global_options_work_before_and_after_subcommand(self):
        for argv in (['-c', 'example.json', '-p', 'immich', 'backup'],
                     ['backup', '-c', 'example.json', '-p', 'immich']):
            args = q.build_parser().parse_args(argv)
            self.assertEqual((args.config, args.profile), ('example.json', 'immich'))

    def test_config_output_is_json_and_missing_explicit_file_is_not_created(self):
        doc = {'version': 2, 'profiles': {'home': profile(self.root, 'home')}}
        self.path.write_text(json.dumps(doc))
        with patch.object(sys, 'argv', ['q-restic', '-c', str(self.path), 'config']), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.main(), 0)
        self.assertEqual(json.loads(out.getvalue()), doc)
        absent = self.root / 'absent.json'
        with patch.object(sys, 'argv', ['q-restic', '-c', str(absent), '-p', 'home', 'backup']), self.assertRaises(SystemExit):
            q.main()
        self.assertFalse(absent.exists())

    def test_unknown_profile_and_shared_repository_tag_collision_are_rejected(self):
        doc = {'profiles': {name: profile(self.root, name, snapshot_tag='same') for name in ('home', 'immich')}}
        for name in ('missing', 'home'):
            with self.subTest(name=name), self.assertRaises(SystemExit):
                q.profile_config(doc, name)

    def test_multiple_sources_restore_at_target_root(self):
        cfg = {'sources': ['/home/test', '/mnt/media']}
        self.assertEqual(q.restore_root(cfg), '')
        self.assertEqual(q.restore_root(cfg, {'paths': ['/one']}), 'one')


class PasswordTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'private' / 'password'
        self.cfg = {'password_file': str(self.path)}
        self.out, self.err = io.StringIO(), io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.out))
        self.enterContext(contextlib.redirect_stderr(self.err))

    def test_password_is_saved_privately_and_never_echoed(self):
        secret = 'only-a-test-password'
        with patch.object(q.getpass, 'getpass', side_effect=[secret, secret]):
            self.assertEqual(q.set_password_file(self.cfg), 0)
        self.assertEqual(self.path.read_text(), secret + '\n')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(secret, self.out.getvalue() + self.err.getvalue())
        with patch.object(q.getpass, 'getpass') as prompt:
            self.assertEqual(q.set_password_file(self.cfg), 1)
        prompt.assert_not_called()
        self.assertEqual(self.path.read_text(), secret + '\n')

    def test_mismatch_empty_cancel_and_echo_fallback_never_create_file(self):
        for effect in (['', ''], ['one', 'two'], KeyboardInterrupt(), EOFError(), q.getpass.GetPassWarning('echo')):
            with self.subTest(effect=repr(effect)), patch.object(q.getpass, 'getpass', side_effect=effect):
                self.assertNotEqual(q.set_password_file(self.cfg), 0)
            self.assertFalse(self.path.exists())

    def test_dangling_symlink_is_not_followed(self):
        self.path.parent.mkdir()
        target = self.path.parent / 'not-created'
        self.path.symlink_to(target)
        with patch.object(q.getpass, 'getpass') as prompt:
            self.assertEqual(q.set_password_file(self.cfg), 1)
        prompt.assert_not_called()
        self.assertFalse(target.exists())


class WriterLockTests(unittest.TestCase):
    def test_lock_is_released_when_a_tui_write_finishes_or_raises(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp, patch.dict(os.environ, {'XDG_CACHE_HOME': tmp}):
            cfg = {'repository': str(Path(tmp) / 'repo')}
            for fail in (False, True):
                try:
                    with q.writer_lock(cfg):
                        held = q._LOCK_FD
                        self.assertFalse(held.closed)
                        if fail:
                            raise RuntimeError('test error')
                except RuntimeError:
                    pass
                self.assertTrue(held.closed)
                self.assertIsNone(q._LOCK_FD)


@unittest.skipUnless(shutil.which('restic'), 'restic unavailable')
class RepositoryTests(unittest.TestCase):
    def test_shared_repository_list_restore_and_retention_remain_profile_scoped(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            password = root / 'password'
            password.write_text('test-only\n')
            password.chmod(0o600)
            doc = {'version': 2, 'profiles': {name: profile(root, name) for name in ('home', 'immich')}}
            (root / 'extra').mkdir()
            (root / 'extra' / 'shared').write_text('second source')
            doc['profiles']['immich']['sources'].append(str(root / 'extra'))
            cfg_path = root / 'config.json'
            cfg_path.write_text(json.dumps(doc))
            env = dict(os.environ, RESTIC_REPOSITORY=str(root / 'repo'), RESTIC_PASSWORD_FILE=str(password),
                       XDG_CACHE_HOME=str(root / 'cache'), RESTIC_CACHE_DIR=str(root / 'cache/restic'))

            def restic(*args):
                result = subprocess.run(['restic', *args], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                return result

            def cli(*args, expected=0):
                result = subprocess.run([sys.executable, str(SOURCE), '-c', str(cfg_path), *args],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
                return result

            for name in doc['profiles']:
                (root / name).mkdir(exist_ok=True)
                (root / name / 'file').write_text(name)
            cli('-p', 'home', 'dry-run', expected=10)
            self.assertFalse((root / 'repo').exists())
            restic('init')
            for name in doc['profiles']:
                (root / name).mkdir(exist_ok=True)
                (root / name / 'file').write_text(name)
                cli('-p', name, 'backup')
                (root / name / 'file').write_text(name + ' changed')
                cli('backup', '-p', name)
            snapshots = json.loads(restic('snapshots', '--json').stdout)
            groups = {name: [snap for snap in snapshots if 'q-restic:profile:' + name in snap['tags']]
                      for name in doc['profiles']}
            self.assertEqual(set(groups['immich'][0]['paths']), {str(root / 'immich'), str(root / 'extra')})
            for name, snaps in groups.items():
                listing = cli('-p', name, 'status').stdout
                self.assertEqual(len(snaps), 2)
                self.assertTrue(all(snap['short_id'] in listing for snap in snaps))
                other = groups['immich' if name == 'home' else 'home']
                self.assertTrue(all(snap['short_id'] not in listing for snap in other))
            # Explicit snapshot IDs must not bypass the profile filter.
            cli('-p', 'home', 'restore', groups['immich'][0]['id'], str(root / 'wrong'), expected=1)
            self.assertFalse((root / 'wrong').exists())
            cli('-p', 'home', 'restore', 'latest', str(root / 'restored'))
            restored = root / 'restored' / str(root / 'home').lstrip('/') / 'file'
            self.assertEqual(restored.read_text(), 'home changed')
            doc['profiles']['home']['keep'] = {'daily': 1}
            cfg_path.write_text(json.dumps(doc))
            cli('-p', 'home', 'forget', '--dry-run')
            self.assertEqual(len(json.loads(restic('snapshots', '--json').stdout)), 4)
            cli('-p', 'home', 'forget')
            remaining = json.loads(restic('snapshots', '--json').stdout)
            self.assertEqual(len(remaining), 3)
            self.assertTrue(all(snap['id'] in {s['id'] for s in remaining} for snap in groups['immich']))
            # A second profile shares the same writer lock even though its name differs.
            lock_code = "import importlib.util, sys; s=importlib.util.spec_from_file_location('q',sys.argv[1]); q=importlib.util.module_from_spec(s); s.loader.exec_module(q); q.acquire_lock({'repository':sys.argv[2]}); print('ready',flush=True); sys.stdin.read()"
            holder = subprocess.Popen([sys.executable, '-c', lock_code, str(SOURCE), str(root / 'repo')],
                                      env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                self.assertTrue(select.select([holder.stdout], [], [], 5)[0], 'lock holder did not start')
                self.assertEqual(holder.stdout.readline().strip(), 'ready')
                blocked = cli('-p', 'immich', 'backup', expected=1)
                self.assertIn('另一次备份正在运行', blocked.stderr)
            finally:
                holder.communicate(timeout=5)
            restic('check')
