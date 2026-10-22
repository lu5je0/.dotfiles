"""Profile execution identity, fresh environment, and TUI session boundaries."""
import contextlib
import fcntl
import io
import json
import os
from pathlib import Path
import pty
import pwd
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
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from test_q_restic import q, SOURCE, raw_profile, test_config


class RunAsTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        self.account = SimpleNamespace(pw_name='backup', pw_uid=4242, pw_gid=4343,
                                       pw_dir='/home/backup', pw_shell='/bin/bash')
        self.cfg = test_config(run_as={'user':'backup','extra_groups':['docker']})

    def identity_mocks(self):
        self.enterContext(patch.object(q.pwd,'getpwnam',return_value=self.account))
        self.enterContext(patch.object(q.os,'getgrouplist',return_value=[4343,99]))
        self.enterContext(patch.object(q.grp,'getgrnam',return_value=SimpleNamespace(gr_gid=777)))

    def test_configuration_is_strict_and_does_not_mutate_input(self):
        for value in [None, 'backup', {}, {'user':''}, {'user':1}, {'user':'backup','group':'docker'},
                      {'user':'backup','extra_groups':'docker'}, {'user':'backup','extra_groups':[1]}]:
            with self.subTest(value=value), self.assertRaises(SystemExit):test_config(run_as=value)
        original={'user':'backup','extra_groups':['docker','docker']}
        cfg=test_config(run_as=original)
        self.assertEqual(cfg['run_as'],{'user':'backup','extra_groups':['docker']})
        self.assertEqual(original['extra_groups'],['docker','docker'])

    def test_root_drops_groups_gid_uid_then_reexecutes_with_target_environment(self):
        self.identity_mocks()
        events=[]
        class Reexecuted(Exception):pass
        def execute(executable,argv,env):
            events.append(('exec',executable))
            self.assertEqual(env['HOME'],'/home/backup')
            self.assertEqual(env['USER'],'backup')
            self.assertEqual(env['LOGNAME'],'backup')
            self.assertEqual(env['XDG_CACHE_HOME'],'/home/backup/.cache')
            self.assertEqual(env['XDG_CONFIG_HOME'],'/home/backup/.config')
            self.assertNotIn('XDG_RUNTIME_DIR',env)
            parsed=q.build_parser().parse_args(argv[2:])
            self.assertEqual(parsed.profile,'home')
            self.assertTrue(Path(parsed.config).is_absolute())
            self.assertEqual(parsed.dir,'-target')
            raise Reexecuted()
        with patch.object(q.os,'geteuid',return_value=0), patch.object(q.os,'getegid',return_value=0), patch.object(q.os,'getgroups',return_value=[0]), patch.object(q.os,'setgroups',side_effect=lambda value:events.append(('groups',value))), patch.object(q.os,'setgid',side_effect=lambda value:events.append(('gid',value))), patch.object(q.os,'setuid',side_effect=lambda value:events.append(('uid',value))), patch.object(q.os,'execve',side_effect=execute), patch.dict(os.environ,{'HOME':'/root','XDG_RUNTIME_DIR':'/run/user/0'}), patch.object(sys,'argv',['q-restic','-p','other','restore','latest','--','-target']):
            with self.assertRaises(Reexecuted):q.switch_profile_identity(self.cfg)
        self.assertEqual(events[:3],[('groups',[99,777,4343]),('gid',4343),('uid',4242)])

    def test_unknown_user_and_group_fail_before_any_privilege_change(self):
        with patch.object(q.pwd,'getpwnam',side_effect=KeyError('unknown')), patch.object(q.os,'setuid') as change:
            with self.assertRaises(SystemExit):q.switch_profile_identity(self.cfg)
            change.assert_not_called()
        self.identity_mocks()
        with patch.object(q.grp,'getgrnam',side_effect=KeyError('unknown')), patch.object(q.os,'setuid') as change:
            with self.assertRaises(SystemExit):q.switch_profile_identity(self.cfg)
            change.assert_not_called()

    def test_nonroot_cannot_switch_to_another_account(self):
        self.identity_mocks()
        with patch.object(q.os,'geteuid',return_value=1000), patch.object(q.os,'getegid',return_value=1000), patch.object(q.os,'setgroups') as groups, patch.object(q.os,'execve') as execute:
            with self.assertRaises(SystemExit):q.switch_profile_identity(self.cfg)
            groups.assert_not_called();execute.assert_not_called()

    def test_same_user_can_read_without_extra_group_but_backup_requires_it(self):
        self.identity_mocks()
        env=q.identity_environment(self.account)
        with patch.object(q.os,'geteuid',return_value=4242), patch.object(q.os,'getegid',return_value=4343), patch.object(q.os,'getgroups',return_value=[99,4343]), patch.dict(os.environ,env), patch.object(q.os,'execve') as execute:
            q.switch_profile_identity(self.cfg)
            execute.assert_not_called()
            with self.assertRaises(SystemExit):q.require_backup_groups(self.cfg)
        with patch.object(q.os,'geteuid',return_value=4242), patch.object(q.os,'getegid',return_value=4343), patch.object(q.os,'getgroups',return_value=[99,777,4343]):
            q.require_backup_groups(self.cfg)

    def test_root_setup_failure_never_starts_profile(self):
        self.identity_mocks()
        with patch.object(q.os,'geteuid',return_value=0), patch.object(q.os,'getegid',return_value=0), patch.object(q.os,'getgroups',return_value=[0]), patch.object(q.os,'setgroups',side_effect=PermissionError), patch.object(q.os,'setgid') as gid, patch.object(q.os,'setuid') as uid, patch.object(q.os,'execve') as execute:
            with self.assertRaises(SystemExit):q.switch_profile_identity(self.cfg)
            gid.assert_not_called();uid.assert_not_called();execute.assert_not_called()

    def test_parent_tui_keeps_identity_and_child_session_returns_to_picker(self):
        app=q.App({'profiles':{'home':raw_profile(run_as={'user':'backup'})}})
        app.term=Mock()
        with patch.object(q,'identity_needs_restart',return_value=True), patch.object(q,'run_profile_tui',return_value=0) as child, patch.object(q,'load_config',return_value=app.document):
            app.select_profile('home')
        child.assert_called_once_with('home')
        self.assertEqual(app.screen,'profiles')
        self.assertIsNone(app.profile)
        self.assertEqual([c[0] for c in app.term.mock_calls],['suspend','resume'])
        session=q.App({'profiles':{'home':raw_profile()}},profile='home',profile_session=True)
        self.assertEqual(session.go_back(),'quit')

    def test_parent_signal_exit_restores_terminal_without_waiting_for_key(self):
        app=q.App({'profiles':{'home':raw_profile()}})
        app.term=Mock()
        with self.assertRaises(SystemExit):
            app.run_suspended(lambda:(_ for _ in ()).throw(SystemExit(143)),propagate_exit=True)
        self.assertEqual([c[0] for c in app.term.mock_calls],['suspend','resume'])
    def test_parent_forwards_termination_and_restores_signal_handlers(self):
        handlers={}
        def install(signum, handler):
            old=handlers.get(signum, signal.SIG_DFL)
            handlers[signum]=handler
            return old
        process=Mock()
        process.__enter__=Mock(return_value=process)
        process.__exit__=Mock(return_value=False)
        def wait():
            handlers[signal.SIGTERM](signal.SIGTERM,None)
            return 143
        process.wait.side_effect=wait
        with patch.object(q.subprocess,'Popen',return_value=process), patch.object(q.signal,'signal',side_effect=install):
            with self.assertRaises(SystemExit) as exit:
                q.run_profile_tui('home')
        self.assertEqual(exit.exception.code,143)
        process.send_signal.assert_called_once_with(signal.SIGTERM)
        self.assertTrue(all(handler==signal.SIG_DFL for handler in handlers.values()))


class NativeIdentityTests(unittest.TestCase):
    def test_preflight_uses_target_environment_without_repository_or_password(self):
        account=pwd.getpwuid(os.geteuid())
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root=Path(tmp);cfg=root/'config.json'
            cfg.write_text(json.dumps({'profiles':{'home':dict(sources=['./data'],repository=str(root/'repo'),password_file=str(root/'no-password'),run_as={'user':account.pw_name},hooks={'preflight':[sys.executable,'-c','import os,json; from pathlib import Path; Path("result.json").write_text(json.dumps([os.getuid(),os.environ["HOME"],os.getcwd()]))']})}}))
            env=dict(os.environ,HOME=str(root/'old-home'),XDG_CACHE_HOME=str(root/'old-cache'))
            result=subprocess.run([sys.executable,str(SOURCE),'-c',str(cfg),'-p','home','preflight'],capture_output=True,text=True,env=env,cwd='/tmp')
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(json.loads((root/'result.json').read_text()),[account.pw_uid,account.pw_dir,str(root)])
            self.assertFalse((root/'repo').exists())
            self.assertFalse((root/'no-password').exists())
    @unittest.skipUnless(shutil.which('restic'),'restic unavailable')
    def test_cli_reloads_home_paths_and_backup_hook_runs_as_profile_user(self):
        account=pwd.getpwuid(os.geteuid())
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root=Path(tmp);(root/'data').mkdir()
            password=root/'password';password.write_text('test-only\n');password.chmod(0o600)
            cfg=root/'config.json'
            cfg.write_text(json.dumps({'profiles':{'home':dict(sources=['./data'],repository=str(root/'repo'),password_file=str(password),host='test',run_as={'user':account.pw_name},hooks={'before_backup':[sys.executable,'-c',
                'import os,json; from pathlib import Path; Path("data/identity.json").write_text(json.dumps({"uid":os.getuid(),"gid":os.getgid(),"home":os.environ["HOME"],"cache":os.environ["XDG_CACHE_HOME"]})); Path("data/db.sql").write_text("fresh dump")']})}}))
            env=dict(os.environ,HOME=str(root/'wrong-home'),XDG_CACHE_HOME=str(root/'wrong-cache'),XDG_CONFIG_HOME=str(root/'wrong-config'))
            def cli(command):return subprocess.run([sys.executable,str(SOURCE),'-c',str(cfg),'-p','home',command],capture_output=True,text=True,env=env,cwd='/tmp')
            parsed=cli('config');self.assertEqual(parsed.returncode,0,parsed.stderr)
            resolved=json.loads(parsed.stdout)
            self.assertEqual(resolved['restore_dir'],str(Path(account.pw_dir)/'restic-restore/home'))
            result=cli('backup');self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            identity=json.loads((root/'data/identity.json').read_text())
            self.assertEqual(identity,dict(uid=account.pw_uid,gid=account.pw_gid,home=account.pw_dir,cache=str(Path(account.pw_dir)/'.cache')))
            self.assertEqual((root/'repo/config').stat().st_uid,account.pw_uid)
            self.assertEqual((root/'data/db.sql').stat().st_uid,account.pw_uid)
            cache=Path(account.pw_dir)/'.cache'
            lock=cache/('q-restic.'+q.hashlib.sha256(str(root/'repo').encode()).hexdigest()[:12]+'.lock')
            self.assertEqual(lock.stat().st_uid,account.pw_uid)
            lock.unlink()

    def test_real_pty_profile_session_returns_to_parent_picker(self):
        account=pwd.getpwuid(os.geteuid())
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            root=Path(tmp);password=root/'password';password.write_text('test\n')
            config=root/'config.json'
            config.write_text(json.dumps({'profiles':{'home':dict(sources=[str(root/'data')],repository=str(root/'repo'),password_file=str(password),run_as={'user':account.pw_name})}}))
            fake=root/'restic'
            fake.write_text('#!'+sys.executable+'\nimport os,json,sys\nfrom pathlib import Path\nPath('+repr(str(root/'identity'))+').write_text(os.environ["HOME"])\nprint("[]" if sys.argv[1]=="snapshots" else json.dumps({"total_size":0}))\n')
            fake.chmod(0o755)
            pid,fd=pty.fork()
            if pid==0:
                os.environ.update(TERM='xterm-256color',HOME=str(root/'old-home'),XDG_CACHE_HOME=str(root/'old-cache'),PATH=str(root)+':'+os.environ['PATH'])
                os.execv(sys.executable,[sys.executable,str(SOURCE),'-c',str(config)])
            fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',28,120,0,0))
            def read_until(text):
                output=bytearray();deadline=time.monotonic()+6
                while time.monotonic()<deadline:
                    if select.select([fd],[],[],.05)[0]:
                        try:output.extend(os.read(fd,65536))
                        except OSError:break
                        decoded=re.sub(r'\x1b\[[0-9;?]*[A-Za-z]','',output.decode('utf-8','replace'))
                        if text in decoded:return
                self.fail(f'missing {text!r}: {output[-2500:]!r}')
            try:
                read_until('1 个 profile');os.write(fd,b'\r');read_until('q-restic · home')
                deadline=time.monotonic()+3
                while not (root/'identity').exists() and time.monotonic()<deadline:time.sleep(.02)
                self.assertEqual((root/'identity').read_text(),account.pw_dir)
                os.write(fd,b'q');read_until('1 个 profile');os.write(fd,b'q')
                deadline=time.monotonic()+3
                while time.monotonic()<deadline:
                    child,status=os.waitpid(pid,os.WNOHANG)
                    if child:
                        pid=None;self.assertEqual(status,0);break
                    if select.select([fd],[],[],.05)[0]:
                        with contextlib.suppress(OSError):os.read(fd,65536)
                self.assertIsNone(pid)
            finally:
                if pid is not None:
                    with contextlib.suppress(ProcessLookupError):os.kill(pid,signal.SIGTERM)
                    os.waitpid(pid,0)
                os.close(fd)
