"""Exercise the profile picker and hidden password prompt in a real pseudo-terminal."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import sys
import tempfile
import termios
import time
import unittest

from test_q_restic import SOURCE


class Session:
    def __init__(self, case, root, missing_password=False):
        self.case, self.root = case, root
        self.output = bytearray()
        profiles = {}
        for name in ('home', 'immich'):
            password = root / (name + '.password')
            if name == 'home' or not missing_password:
                password.write_text('test-password\n')
                password.chmod(0o600)
            profiles[name] = dict(repository=str(root / 'repo'), sources=[str(root / name)],
                                  password_file=str(password), host='test')
        self.config = root / 'config.json'
        self.config.write_text(json.dumps({'profiles': profiles}))
        fake = root / 'restic'
        fake.write_text('#!' + sys.executable + '\n' + '''import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
tag = args[args.index('--tag') + 1]
name = tag.rsplit(':', 1)[-1]
with (Path(os.environ['TEST_ROOT']) / 'calls').open('a') as output:
    output.write(args[0] + ' ' + name + '\\n')
if args[0] == 'snapshots':
    time.sleep(.4 if name == 'home' else .05)
    number, letter = ('1', 'a') if name == 'home' else ('2', 'b')
    print(json.dumps([dict(id=letter*64, short_id=letter*8, tags=[tag],
                          time=f'2026-10-0{number}T12:00:00Z')]))
elif args[0] == 'stats':
    print(json.dumps(dict(total_size=111 if name == 'home' else 222)))
else:
    raise SystemExit(1)
''')
        fake.chmod(0o755)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ.update(TERM='xterm-256color', TEST_ROOT=str(root),
                              PATH=str(root) + ':' + os.environ['PATH'])
            os.execv(sys.executable, [sys.executable, str(SOURCE), '-c', str(self.config)])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', 28, 120, 0, 0))
        case.addCleanup(self.close)

    def read_until(self, text):
        recent = bytearray()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if select.select([self.fd], [], [], .05)[0]:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    break
                recent.extend(data)
                self.output.extend(data)
                decoded = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', recent.decode('utf-8', 'replace'))
                if text in decoded:
                    return decoded
        self.case.fail(f'没找到 {text!r}: {recent[-3000:]!r}')

    def write(self, text):
        os.write(self.fd, text.encode())

    def exit(self, keys):
        self.write(keys)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.pid = None
                self.case.assertEqual(status, 0)
                return
            if select.select([self.fd], [], [], .05)[0]:
                with contextlib.suppress(OSError):
                    self.output.extend(os.read(self.fd, 65536))
        self.case.fail('TUI 未正常退出')

    def close(self):
        if self.pid is not None:
            with contextlib.suppress(ProcessLookupError):
                os.kill(self.pid, signal.SIGTERM)
            os.waitpid(self.pid, 0)
        os.close(self.fd)


class ProfileTuiTests(unittest.TestCase):
    def test_picker_does_not_connect_and_menu_can_set_missing_password_without_echo(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            session = Session(self, root, missing_password=True)
            session.read_until('2 个 profile')
            self.assertFalse((root / 'calls').exists())
            session.write('j\r')
            session.read_until('密码文件未配置')
            self.assertFalse((root / 'calls').exists())
            session.write('G\r')
            session.read_until('仓库密码（不回显）:')
            secret = 'pty-only-test-password'
            session.write(secret + '\n')
            session.read_until('再次输入密码:')
            session.write(secret + '\n')
            session.read_until('密码文件已保存')
            self.assertEqual((root / 'immich.password').read_text(), secret + '\n')
            self.assertEqual((root / 'immich.password').stat().st_mode & 0o777, 0o600)
            session.read_until('2026-10-02')
            session.exit('qq')
            self.assertNotIn(secret.encode(), session.output)
            self.assertNotIn('snapshots home', (root / 'calls').read_text())

    def test_switching_profile_discards_old_async_results(self):
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root = Path(tmp)
            session = Session(self, root)
            session.read_until('2 个 profile')
            session.write('\r')
            session.read_until('读取仓库中')
            session.write('q')
            session.read_until('2 个 profile')
            session.write('j\r')
            session.read_until('q-restic · immich')
            session.write('jj\r')
            session.read_until('bbbbbbbb')
            time.sleep(.6)
            session.write('g')
            output = session.read_until('bbbbbbbb')
            self.assertNotIn('aaaaaaaa', output)
            session.exit('hqq')
            self.assertEqual((root / 'calls').read_text().splitlines().count('stats immich'), 1)
