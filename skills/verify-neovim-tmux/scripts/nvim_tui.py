#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


class HarnessError(Exception):
    pass


def run(argv, timeout=5, check=True):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise HarnessError(f"{Path(argv[0]).name} exited {result.returncode}: {detail[:2000]}")
    return result


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def lua_string(text):
    equals = ''
    while f']{equals}]' in text:
        equals += '='
    return f'[{equals}[{text}]{equals}]'


def load_session(path):
    root = Path(path).expanduser().resolve()
    data = json.loads((root / 'session.json').read_text())
    if not isinstance(data, dict) or data.get('kind') != 'neovim-tmux-verification-v1' or data.get('root') != str(root):
        raise HarnessError('Not a verification session created by this script.')
    if not re.fullmatch(r'nvim-tui-[0-9a-f]{32}', data.get('server', '')):
        raise HarnessError('Invalid isolated tmux server name in session.json.')
    if not re.fullmatch(r'%\d+', data.get('pane', '')):
        raise HarnessError('Invalid pane ID in session.json.')
    for key in ('tmux', 'nvim', 'socket', 'cwd', 'config'):
        if not isinstance(data.get(key), str):
            raise HarnessError(f'Missing session field: {key}')
    return data


def tmux(session, *args, **kwargs):
    return run([session['tmux'], '-L', session['server'], *args], **kwargs)


def alive(session):
    return tmux(session, 'has-session', '-t', 'verify', check=False).returncode == 0


def query(session, expression, timeout=3):
    result = run([
        session['nvim'], '--server', session['socket'], '--remote-expr',
        f'json_encode({expression})',
    ], timeout=timeout)
    return json.loads(result.stdout)


def lua(session, expression):
    quoted = json.dumps(expression, ensure_ascii=False)
    return query(session, f'luaeval({quoted})')


def keys(session, text):
    if not alive(session):
        raise HarnessError('Verification session is not running. Start a new instance.')
    run([session['nvim'], '--server', session['socket'], '--remote-send', text])


def pane_text(session, ansi=False):
    args = ['capture-pane', '-p', '-t', session['pane']]
    if ansi:
        args.append('-e')
    return tmux(session, *args).stdout


def capture(session, label):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', label):
        raise HarnessError('Capture label must be 1-64 letters, digits, underscores or hyphens.')
    prefix = Path(session['root']) / 'captures' / f'{time.time_ns()}-{label}'
    text = pane_text(session)
    plain_path = prefix.with_suffix('.txt')
    ansi_path = prefix.with_suffix('.ansi')
    plain_path.write_text(text)
    ansi_path.write_text(pane_text(session, ansi=True))
    return {'text_path': str(plain_path), 'ansi_path': str(ansi_path), 'screen': text}


TRACE_LUA = '''(function()
  _G.__nvim_tui_trace = {system_calls = 0, focus_gained = 0, focus_lost = 0}
  local original = vim.system
  vim.system = function(cmd, opts, callback)
    _G.__nvim_tui_trace.system_calls = _G.__nvim_tui_trace.system_calls + 1
    return original(cmd, opts, callback)
  end
  vim.api.nvim_create_autocmd('FocusGained', {callback = function()
    _G.__nvim_tui_trace.focus_gained = _G.__nvim_tui_trace.focus_gained + 1
  end})
  vim.api.nvim_create_autocmd('FocusLost', {callback = function()
    _G.__nvim_tui_trace.focus_lost = _G.__nvim_tui_trace.focus_lost + 1
  end})
  return true
end)()'''

SNAPSHOT_LUA = '''(function()
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      buffers[#buffers + 1] = {id = buf, name = vim.api.nvim_buf_get_name(buf),
        filetype = vim.bo[buf].filetype, modified = vim.bo[buf].modified,
        changedtick = vim.api.nvim_buf_get_changedtick(buf)}
    end
  end
  return {mode = vim.fn.mode(1), ui_count = #vim.api.nvim_list_uis(),
    version = tostring(vim.version()), executable = vim.v.progpath,
    config = vim.env.MYVIMRC, cwd = vim.fn.getcwd(),
    current_buffer = vim.api.nvim_get_current_buf(), cursor = vim.api.nvim_win_get_cursor(0),
    current_window = vim.api.nvim_get_current_win(), tabpage = vim.api.nvim_get_current_tabpage(),
    tab_windows = vim.api.nvim_tabpage_list_wins(0), tabpages = vim.api.nvim_list_tabpages(),
    buffers = buffers, trace = _G.__nvim_tui_trace or vim.NIL,
    messages = vim.fn.execute('messages'), errmsg = vim.v.errmsg}
end)()'''


def stop(session):
    if not alive(session):
        return {'stopped': True, 'already_stopped': True, 'evidence': session['root']}
    saved = capture(session, 'before-stop')
    try:
        run([
            session['nvim'], '--server', session['socket'], '--remote-expr',
            "execute('qa!')",
        ], timeout=2, check=False)
    except subprocess.TimeoutExpired:
        pass
    deadline = time.monotonic() + 2
    while alive(session) and time.monotonic() < deadline:
        time.sleep(.1)
    forced = alive(session)
    if forced:
        tmux(session, 'kill-session', '-t', 'verify')
    return {'stopped': not alive(session), 'forced': forced, 'evidence': saved['text_path']}


def start(args):
    nvim = shutil.which(args.nvim)
    tmux_bin = shutil.which('tmux')
    if not nvim or not tmux_bin:
        raise HarnessError('Both nvim and tmux must be installed; no headless fallback is allowed.')
    config = Path(args.config).expanduser().resolve()
    if config.is_dir():
        config = config / ('init.lua' if (config / 'init.lua').is_file() else 'init.vim')
    if not config.is_file():
        raise HarnessError(f'Neovim config entry does not exist: {config}')
    cwd = Path(args.cwd).expanduser().resolve() if args.cwd else None
    if cwd and not cwd.is_dir():
        raise HarnessError(f'Fixture cwd does not exist: {cwd}')
    root = Path(tempfile.mkdtemp(prefix='nvim-tui-', dir='/tmp')).resolve()
    (root / 'captures').mkdir()
    if cwd is None:
        cwd = root / 'workspace'
        cwd.mkdir()
    session = {
        'kind': 'neovim-tmux-verification-v1', 'root': str(root),
        'server': 'nvim-tui-' + uuid.uuid4().hex,
        'socket': str(root / 'rpc.sock'), 'nvim': nvim, 'tmux': tmux_bin,
        'cwd': str(cwd), 'config': str(config), 'trace': args.trace,
    }
    command = [
        nvim, '-i', 'NONE', '-u', str(config), '--listen', session['socket'],
        '--cmd', f'lua vim.opt.runtimepath:prepend({lua_string(str(config.parent))})',
    ]
    launch = 'exec env ' + shlex.quote(f'NVIM_LOG_FILE={root / "nvim.log"}') + ' ' + shlex.join(command)
    pane = tmux(
        session, '-f', '/dev/null', 'new-session', '-d', '-s', 'verify', '-n', 'nvim',
        '-x', str(args.width), '-y', str(args.height), '-c', str(cwd),
        '-P', '-F', '#{pane_id}', launch,
    ).stdout.strip()
    session['pane'] = pane
    (root / 'session.json').write_text(json.dumps(session, indent=2))
    deadline = time.monotonic() + args.timeout
    ready = False
    while time.monotonic() < deadline:
        if not alive(session):
            raise HarnessError(f'Neovim exited during startup. Inspect {root / "nvim.log"}; session: {root}')
        if Path(session['socket']).exists():
            try:
                ready = lua(session, '#vim.api.nvim_list_uis()') > 0
            except (HarnessError, subprocess.TimeoutExpired, json.JSONDecodeError):
                pass
        if ready:
            break
        time.sleep(.1)
    if not ready:
        try:
            emit(capture(session, 'startup-timeout'))
        finally:
            tmux(session, 'kill-session', '-t', 'verify', check=False)
        raise HarnessError(f'Startup timed out. Evidence retained at {root}. Do not report PASS.')
    try:
        if args.trace:
            if lua(session, 'type(vim.system)') != 'function':
                raise HarnessError('--trace requires Neovim with vim.system (0.10+).')
            lua(session, TRACE_LUA)
        snapshot = lua(session, SNAPSHOT_LUA)
        saved = capture(session, 'startup')
    except (HarnessError, OSError, ValueError, subprocess.SubprocessError) as error:
        stop(session)
        raise HarnessError(f'Startup inspection failed: {error}; evidence: {root}') from None
    emit({'status': 'READY_NOT_VERIFIED', 'session': str(root), 'cwd': str(cwd),
          'snapshot': snapshot, 'capture': saved})


def wait_screen(session, args):
    deadline = time.monotonic() + args.timeout
    while True:
        text = pane_text(session)
        if (args.text in text) != args.absent:
            saved = capture(session, args.label)
            emit({'status': 'MATCH_NOT_VERDICT', 'expected': args.text, 'absent': args.absent,
                  'capture': saved})
            return
        if time.monotonic() >= deadline:
            saved = capture(session, args.label + '-timeout')
            emit({'status': 'TIMEOUT', 'expected': args.text, 'absent': args.absent, 'capture': saved})
            raise HarnessError('Expected screen state was not observed; inspect the capture, do not continue as PASS.')
        time.sleep(.1)


def inspect(session, seconds):
    before = lua(session, SNAPSHOT_LUA)
    after = before
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        time.sleep(min(.2, max(0, deadline - time.monotonic())))
        after = lua(session, SNAPSHOT_LUA)
    result = {'before': before, 'after': after, 'seconds': seconds}
    path = Path(session['root']) / f'{time.time_ns()}-observation.json'
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    result['evidence'] = str(path)
    result['capture'] = capture(session, 'inspection')
    emit(result)


def duration(value):
    number = float(value)
    if not 0 < number <= 120:
        raise argparse.ArgumentTypeError('must be greater than 0 and at most 120 seconds')
    return number


def dimension(value, maximum=240):
    number = int(value)
    if not 10 <= number <= maximum:
        raise argparse.ArgumentTypeError(f'must be between 10 and {maximum}')
    return number


def label(value):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}', value):
        raise argparse.ArgumentTypeError('use 1-48 letters, digits, underscores or hyphens')
    return value


def nonempty(value):
    if not value:
        raise argparse.ArgumentTypeError('expected text must not be empty')
    return value


def main():
    parser = argparse.ArgumentParser(description='Drive a real, isolated Neovim TUI and retain runtime evidence.')
    subs = parser.add_subparsers(dest='action', required=True)
    launch = subs.add_parser('start', help='Start normal Neovim in a private tmux server')
    launch.add_argument('--config', required=True, help='Config directory or init.lua/init.vim entry')
    launch.add_argument('--cwd', help='Existing disposable fixture directory; defaults to a new empty workspace')
    launch.add_argument('--nvim', default='nvim', help='Neovim executable')
    launch.add_argument('--trace', action='store_true', help='Count future vim.system calls and terminal focus events')
    launch.add_argument('--width', type=dimension, default=140)
    launch.add_argument('--height', type=lambda value: dimension(value, 80), default=42)
    launch.add_argument('--timeout', type=duration, default=15)
    for name, help_text in [
        ('keys', 'Send mapped keys using Neovim key notation'),
        ('focus', 'Inject a terminal focus report, not a desktop focus change'),
        ('capture', 'Save the current pane as plain text and ANSI'),
        ('wait', 'Wait for literal screen text; timeout is an error'),
        ('inspect', 'Read runtime state and optional trace counters'),
        ('stop', 'Close only this isolated session; retain all evidence'),
    ]:
        sub = subs.add_parser(name, help=help_text)
        sub.add_argument('session', help='Absolute session directory returned by start')
        if name == 'keys':
            sub.add_argument('input', help="Example: 'iPROBE<Esc>' or ':edit example.txt<CR>'")
        elif name == 'focus':
            sub.add_argument('state', choices=['gained', 'lost'])
        elif name in ('capture', 'wait'):
            sub.add_argument('--label', type=label, default=name, help='Short filename-safe evidence label')
            if name == 'wait':
                sub.add_argument('--text', type=nonempty, required=True, help='Literal text expected on the pane')
                sub.add_argument('--absent', action='store_true', help='Wait until the text disappears')
                sub.add_argument('--timeout', type=duration, default=5)
        elif name == 'inspect':
            sub.add_argument('--seconds', type=duration, default=0, help='Observe for this duration without injecting input')
    args = parser.parse_args()
    if args.action == 'start':
        start(args)
        return
    session = load_session(args.session)
    if args.action == 'keys':
        keys(session, args.input)
        emit({'status': 'INPUT_SENT_NOT_VERIFIED', 'keys': args.input})
    elif args.action == 'focus':
        tmux(session, 'send-keys', '-t', session['pane'], '-H', '1b', '5b', '49' if args.state == 'gained' else '4f')
        emit({'status': 'FOCUS_REPORT_SENT', 'state': args.state, 'desktop_focus_tested': False})
    elif args.action == 'capture':
        emit(capture(session, args.label))
    elif args.action == 'wait':
        wait_screen(session, args)
    elif args.action == 'inspect':
        inspect(session, args.seconds)
    elif args.action == 'stop':
        emit(stop(session))


if __name__ == '__main__':
    try:
        main()
    except (HarnessError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('INTERRUPTED: use stop with the recorded session path to close the isolated Neovim.', file=sys.stderr)
        sys.exit(130)
