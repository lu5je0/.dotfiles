"""配置导入、来源路径与编辑；不访问真实备份仓库。"""

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

from test_q_restic import q


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.path = self.root / 'config.json'
        self.source = self.root / 'host' / 'home.json'
        self.raw = dict(sources=['./data'], repository='./repo', password_file='./password',
                        excludes='./excludes', mount_dir='./mount', restore_dir='./restore')
        self.source.parent.mkdir()
        self.write(self.source, {'profiles': {'home': self.raw}})
        self.write(self.path, {'imports': ['host/home.json'], 'profiles': {}})
        self.enterContext(patch.object(q, 'CONFIG_FILE', self.path))
        self.err = self.enterContext(contextlib.redirect_stderr(io.StringIO()))

    def write(self, path, document):
        path.write_text(json.dumps(document))

    def test_recursive_imports_local_profiles_and_each_sources_relative_paths(self):
        self.write(self.root / 'entry.json', {'imports': ['./host/home.json']})
        self.write(self.path, {'imports': ['./entry.json'], 'profiles': {'other': dict(self.raw)}})
        document = q.load_config()
        self.assertEqual(set(document['profiles']), {'home', 'other'})
        for name, base in [('home', self.source.parent), ('other', self.root)]:
            cfg = q.profile_config(document, name)
            self.assertEqual(cfg['sources'], [str(base / 'data')])
            for key, suffix in [('repository', 'repo'), ('password_file', 'password'),
                                ('excludes', 'excludes'), ('mount_dir', 'mount'), ('restore_dir', 'restore')]:
                self.assertEqual(cfg[key], str(base / suffix))

    def test_missing_invalid_cyclic_and_duplicate_imports_fail_without_writing(self):
        for imports in (['missing.json'], 'host/home.json', [1], [''], ['config.json'],
                        ['host/home.json', 'host/home.json']):
            with self.subTest(imports=imports):
                self.write(self.path, {'imports': imports})
                original = self.path.read_bytes()
                with self.assertRaises(SystemExit):
                    q.load_config()
                self.assertEqual(self.path.read_bytes(), original)
        self.write(self.path, {'imports': ['host/home.json'], 'profiles': {'home': self.raw}})
        with self.assertRaises(SystemExit):
            q.load_config()
        self.assertIn('重名', self.err.getvalue())
        self.write(self.source, {'imports': ['../config.json']})
        self.write(self.path, {'imports': ['host/home.json']})
        with self.assertRaises(SystemExit):
            q.load_config()
        self.assertIn('循环', self.err.getvalue())

    def test_symlink_imports_resolve_paths_beside_declared_file_not_store_target(self):
        (self.root / 'target').mkdir()
        target = self.root / 'target' / 'config.json'
        self.source.rename(target)
        self.source.symlink_to(target)
        cfg = q.profile_config(q.load_config(), 'home')
        self.assertEqual(cfg['sources'], [str(self.source.parent / 'data')])
        self.assertEqual(cfg['_config_file'], str(self.source))

    def test_save_preserves_imports_without_flattening_and_config_stdout_has_no_metadata(self):
        raw = json.loads(self.path.read_text())
        document = q.load_config()
        q.save_config(document)
        self.assertEqual(json.loads(self.path.read_text()), raw)
        with patch.object(sys, 'argv', ['q-restic', 'config']), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.main(), 0)
        self.assertEqual(json.loads(out.getvalue()), {'profiles': {'home': self.raw}})
        with patch.object(sys, 'argv', ['q-restic', '-p', 'home', 'config']), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.main(), 0)
        self.assertFalse(any(key.startswith('_') for key in json.loads(out.getvalue())))

    def test_repository_tag_collision_uses_each_profile_source_directory(self):
        other = self.root / 'other.json'
        self.write(other, {'profiles': {'other': dict(self.raw, repository='./host/repo', snapshot_tag='same')}})
        self.write(self.source, {'profiles': {'home': dict(self.raw, snapshot_tag='same')}})
        self.write(self.path, {'imports': ['host/home.json', 'other.json']})
        with self.assertRaises(SystemExit):
            q.profile_config(q.load_config(), 'home')
        self.assertIn('标签冲突', self.err.getvalue())

    def test_imported_hook_uses_source_directory_but_keeps_root_entry_in_environment(self):
        code = 'import os,json; open("hook.json","w").write(json.dumps([os.getcwd(),os.environ["Q_RESTIC_CONFIG"]]))'
        self.write(self.source, {'profiles': {'home': dict(self.raw, hooks={'preflight': [sys.executable, '-c', code]})}})
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(q.run_backup_hook(q.profile_config(q.load_config(), 'home'), 'preflight'), 0)
        self.assertEqual(json.loads((self.source.parent / 'hook.json').read_text()),
                         [str(self.source.parent), str(self.path)])

    def test_cli_and_tui_edit_imported_source_and_reject_readonly_files(self):
        for command, target in [('edit-config', self.source), ('edit-excludes', self.source.parent / 'excludes')]:
            target.touch(exist_ok=True)
            with patch.object(sys, 'argv', ['q-restic', '-p', 'home', command]), patch.object(q.subprocess, 'call', return_value=0) as editor:
                self.assertEqual(q.main(), 0)
                self.assertEqual(editor.call_args.args[0][-1], str(target))
            target.chmod(0o444)
            with patch.object(sys, 'argv', ['q-restic', '-p', 'home', command]), patch.object(q.subprocess, 'call') as editor:
                with self.assertRaises(SystemExit):
                    q.main()
                editor.assert_not_called()
            target.chmod(0o644)
        self.assertIn('Nix', q.editable_config('/nix/store/test-config'))
        app = q.App.__new__(q.App)
        app.cfg = q.profile_config(q.load_config(), 'home')
        app.document, app.profile, app.screen = q.load_config(), 'home', 'menu'
        app.term, app.set_message = Mock(), Mock()
        self.source.chmod(0o444)
        app.act_edit_policy()
        app.term.suspend.assert_not_called()
        self.assertIn('只读', app.set_message.call_args.args[0])


class DefaultConfigTests(unittest.TestCase):
    write = ImportTests.write

    def setUp(self):
        ImportTests.setUp(self)
        self.system = self.root / 'system' / 'config.json'
        self.system.parent.mkdir()
        self.enterContext(patch.object(q, 'DEFAULT_CONFIG_FILE', self.path))
        self.enterContext(patch.object(q, 'SYSTEM_CONFIG_FILE', self.system))

    def test_defaults_merge_profiles_and_preserve_source_paths_and_user_document(self):
        self.write(self.system, {'profiles': {'system': self.raw}})
        document = q.load_config()
        self.assertEqual(set(document['profiles']), {'system', 'home'})
        cfg = q.profile_config(document, 'system')
        self.assertEqual(cfg['sources'], [str(self.system.parent / 'data')])
        self.assertEqual(cfg['_config_file'], str(self.system))
        original = json.loads(self.path.read_text())
        q.save_config(document)
        self.assertEqual(json.loads(self.path.read_text()), original)
        with patch.object(sys, 'argv', ['q-restic', 'config']), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.main(), 0)
        self.assertEqual(set(json.loads(out.getvalue())['profiles']), {'system', 'home'})
        self.assertEqual(q.command_hint(cfg, 'unlock'), 'q-restic -p system unlock')

    def test_system_only_and_no_configs_do_not_create_or_copy_profiles(self):
        self.path.unlink()
        self.write(self.system, {'profiles': {'system': self.raw}})
        document = q.load_config()
        self.assertEqual(document, {'profiles': {'system': self.raw}})
        self.assertFalse(self.path.exists())
        q.save_config(document)
        self.assertEqual(json.loads(self.path.read_text()), {'profiles': {}})
        self.path.unlink()
        self.system.unlink()
        self.assertEqual(q.load_config(), {'profiles': {}})

    def test_system_imports_and_duplicate_or_invalid_system_configuration(self):
        self.write(self.system, {'imports': ['../host/home.json']})
        with self.assertRaises(SystemExit):
            q.load_config()
        self.assertIn('重名', self.err.getvalue())
        self.write(self.path, {'profiles': {}})
        cfg = q.profile_config(q.load_config(), 'home')
        self.assertEqual(cfg['_config_file'], str(self.source))
        self.write(self.system, {'profiles': []})
        with self.assertRaises(SystemExit):
            q.load_config()

    def test_explicit_other_entry_does_not_load_system_config(self):
        self.system.write_text('invalid json')
        with patch.object(sys, 'argv', ['q-restic', '-c', str(self.source), 'config']), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.main(), 0)
        self.assertEqual(json.loads(out.getvalue()), {'profiles': {'home': self.raw}})
