import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'q-txt2kindle.py'
spec = importlib.util.spec_from_file_location('txt2kindle', SCRIPT)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class KindlegenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'XDG_CACHE_HOME': self.temp.name,
                                          'KINDLEGEN_BIN': ''})
        self.env.start()
        self.addCleanup(self.env.stop)
        for target, value in [('shutil.which', None), ('platform.system', 'Linux'),
                              ('platform.machine', 'x86_64')]:
            mock = patch.object(getattr(app, target.split('.')[0]),
                                target.split('.')[1], return_value=value)
            mock.start()
            self.addCleanup(mock.stop)

    def archive(self, name='kindlegen'):
        result = io.BytesIO()
        with tarfile.open(fileobj=result, mode='w:gz') as package:
            member = tarfile.TarInfo(name)
            data = b'#!/bin/sh\nexit 0\n'
            member.size = len(data)
            package.addfile(member, io.BytesIO(data))
        return result.getvalue()

    def test_download_then_reuse_without_network(self):
        data = self.archive()
        with patch.object(app, 'KINDLEGEN_SHA256', hashlib.sha256(data).hexdigest()), \
                patch.object(app.request, 'urlopen', return_value=io.BytesIO(data)) as download:
            binary = Path(app.resolve_kindlegen())
        self.assertEqual(download.call_count, 1)
        self.assertTrue(os.access(binary, os.X_OK))
        self.assertEqual(binary.read_bytes(), b'#!/bin/sh\nexit 0\n')
        with patch.object(app.request, 'urlopen', side_effect=AssertionError('network')):
            self.assertEqual(app.resolve_kindlegen(), str(binary))

    def test_checksum_failure_leaves_no_partial_cache(self):
        with patch.object(app.request, 'urlopen', return_value=io.BytesIO(b'bad download')):
            with self.assertRaisesRegex(RuntimeError, 'SHA-256'):
                app.resolve_kindlegen()
        self.assertEqual(list((self.directory / 'q-txt2kindle').iterdir()), [])

    def test_archive_path_is_not_extracted(self):
        data = self.archive('../escaped')
        with patch.object(app, 'KINDLEGEN_SHA256', hashlib.sha256(data).hexdigest()), \
                patch.object(app.request, 'urlopen', return_value=io.BytesIO(data)):
            with self.assertRaises(RuntimeError):
                app.resolve_kindlegen()
        self.assertFalse((self.directory / 'escaped').exists())

    def test_override_and_path_take_priority(self):
        binary = self.directory / 'custom kindlegen'
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
        with patch.object(app.request, 'urlopen', side_effect=AssertionError('network')):
            with patch.dict(os.environ, {'KINDLEGEN_BIN': str(binary)}):
                self.assertEqual(app.resolve_kindlegen(), str(binary))
            with patch.object(app.shutil, 'which', return_value=str(binary)):
                self.assertEqual(app.resolve_kindlegen(), str(binary))

    def test_invalid_override_and_unsupported_platform_fail_clearly(self):
        with patch.dict(os.environ, {'KINDLEGEN_BIN': str(self.directory / 'missing')}):
            with self.assertRaisesRegex(RuntimeError, 'KINDLEGEN_BIN 不可执行'):
                app.resolve_kindlegen()
        with patch.object(app.platform, 'machine', return_value='aarch64'):
            with self.assertRaisesRegex(RuntimeError, '仅支持 Linux'):
                app.resolve_kindlegen()

    def test_epub_dry_run_and_help_do_not_resolve_kindlegen(self):
        novel = self.directory / 'book.txt'
        novel.write_text('第一章 开始\n这是测试内容。\n', encoding='utf-8')
        for flags in (['-f', 'epub'], ['--dry-run'], ['--help']):
            with self.subTest(flags=flags), \
                    patch.object(app, 'resolve_kindlegen', side_effect=AssertionError('download')), \
                    patch.object(app.sys, 'argv', [str(SCRIPT), str(novel), '-o',
                                                 str(self.directory / 'out'), *flags]), \
                    patch('sys.stdout', new_callable=io.StringIO):
                try:
                    app.main()
                except SystemExit as exc:
                    self.assertEqual(exc.code, 0)


if __name__ == '__main__':
    unittest.main()
