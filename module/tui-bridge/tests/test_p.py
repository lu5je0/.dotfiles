"""Run with python3 -m unittest discover -s module/tui-bridge/tests."""
import base64
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


PASTE = Path(__file__).resolve().parents[3] / 'bin/common/p'
PNG = b'\x89PNG\r\n\x1a\n\x00binary image'


class PasteTests(unittest.TestCase):
    def paste(self, replies, args=(), terminal=False):
        output = io.TextIOWrapper(io.BytesIO(), encoding='utf-8')
        output.isatty = lambda: terminal
        errors = io.StringIO()
        methods = []

        def respond(command, **kwargs):
            request = json.loads(command[2])
            methods.append(request['method'])
            reply = replies[request['method']]
            return subprocess.CompletedProcess(command, 0, json.dumps(reply).encode(), b'')

        with patch.object(sys, 'platform', 'darwin'), \
                patch.object(sys, 'argv', [str(PASTE), *args]), \
                patch.object(sys, 'stdout', output), \
                patch.object(sys, 'stderr', errors), \
                patch.dict('os.environ', {}, clear=True), \
                patch('shutil.which', return_value='/fake/tui-bridge'), \
                patch('subprocess.run', side_effect=respond):
            with self.assertRaises(SystemExit) as exited:
                runpy.run_path(str(PASTE), run_name='__main__')
        output.flush()
        return exited.exception.code, output.buffer.getvalue(), errors.getvalue(), methods

    @staticmethod
    def ok(result):
        return {'id': 1, 'ok': True, 'result': result}

    def image_reply(self, data=PNG, mime='image/png'):
        return {'image': self.ok({'mime': mime, 'data': base64.b64encode(data).decode()})}

    def test_redirect_image(self):
        code, data, error, methods = self.paste(self.image_reply())
        self.assertEqual((code, data, error, methods), (0, PNG, '', ['image']))

    def test_terminal_rejects_image(self):
        code, data, error, methods = self.paste(self.image_reply(), terminal=True)
        self.assertEqual((code, data, methods), (1, b'', ['image']))
        self.assertIn('use -f', error)

    def test_force_terminal_image(self):
        code, data, error, _ = self.paste(self.image_reply(), args=('-f',), terminal=True)
        self.assertEqual((code, data, error), (0, PNG, ''))

    def test_unicode_text(self):
        replies = self.image_reply(b'')
        replies['output'] = self.ok({'text': '中文\nsecond line\n'})
        code, data, error, methods = self.paste(replies, terminal=True)
        self.assertEqual((code, data, error), (0, '中文\nsecond line\n'.encode(), ''))
        self.assertEqual(methods, ['image', 'output'])

    def test_empty_clipboard(self):
        replies = self.image_reply(b'')
        replies['output'] = self.ok({'text': ''})
        code, data, error, _ = self.paste(replies)
        self.assertEqual((code, data, error), (0, b'', ''))

    def test_old_bridge_gives_upgrade_hint(self):
        reply = {'id': 1, 'ok': False, 'error': {'code': 'INVALID_METHOD'}}
        code, data, error, _ = self.paste({'image': reply})
        self.assertEqual((code, data), (1, b''))
        self.assertIn('rebuild', error)

    def test_unknown_mime_is_rejected(self):
        code, data, error, _ = self.paste(self.image_reply(mime='image/jpeg'))
        self.assertEqual((code, data), (1, b''))
        self.assertIn('invalid image response', error)

    def test_invalid_base64_is_rejected(self):
        reply = self.ok({'mime': 'image/png', 'data': '!bad!'})
        code, data, error, _ = self.paste({'image': reply})
        self.assertEqual((code, data), (1, b''))
        self.assertIn('invalid image data', error)


if __name__ == '__main__':
    unittest.main()
