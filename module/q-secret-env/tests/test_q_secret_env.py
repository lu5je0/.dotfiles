"""Exercise encryption formats, shell exports and failure paths with fake secrets."""

import base64
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "q-secret-env.py"
ROOT = SCRIPT.parents[2]
SPEC = importlib.util.spec_from_file_location("q_secret_env", SCRIPT)
q = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(q)
PASSWORD = "test-only-master-password"
KEY = hashlib.sha256(PASSWORD.encode()).hexdigest()


class SecretEnvTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="q-secret-env-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "dotfiles"
        self.config = self.root / "config"
        self.env = dict(os.environ, HOME=str(self.root),
                        DOTFILES_DIR=str(self.repo), XDG_CONFIG_HOME=str(self.config))
        self.environment = patch.dict(os.environ, self.env, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.store = q.SecretEnv()
        self.store.ensure_dirs()
        self.store.pass_file.write_text(f"QSENV2:{KEY}\n")

    def cli(self, *args, expected=0, input_text=None):
        result = subprocess.run([sys.executable, str(SCRIPT), *args],
                                env=self.env, capture_output=True, text=True, input=input_text)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def fixture(self, container="v2", pass_format="v2"):
        if pass_format == "v2":
            local_key, phrase = f"QSENV2:{KEY}", f"QSENV2-{KEY}"
        elif pass_format == "v1":
            local_key, phrase = f"QSENV1:00:10000:{KEY}", f"QSENV1-{KEY}"
        else:
            local_key = phrase = PASSWORD
        self.store.pass_file.write_text(local_key + "\n")
        plaintext = b"FIXTURE\t" + base64.b64encode(b"fixture-value") + b"\n"
        # Independent OpenSSL invocation, with only a public test password in argv.
        encrypted = subprocess.run(
            ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-salt",
             "-pass", f"pass:{phrase}"], input=plaintext, capture_output=True, check=True
        ).stdout
        if container == "v2":
            encrypted = b"QSENVENC2\nNAME\tFIXTURE\nDATA\t" + base64.b64encode(encrypted) + b"\n"
        elif container == "v1":
            encrypted = b"QSENVENC1\n" + base64.encodebytes(encrypted)
        self.store.enc_file.write_bytes(encrypted)

    def test_cli_round_trip_and_mutations(self):
        saved = self.cli("set", "FIRST", "fake-secret-value")
        self.assertEqual(saved.stdout, "")
        self.assertEqual(saved.stderr, "Saved: FIRST\n")
        self.cli("set", "SECOND", "second")
        self.cli("set", "FIRST", "updated")
        self.assertEqual(self.cli("get", "FIRST").stdout, "updated\n")
        self.assertEqual(self.cli("list").stdout, "FIRST\nSECOND\n")
        self.assertEqual(self.cli("list", "--values").stdout,
                         "FIRST\tupdated\nSECOND\tsecond\n")
        removed = self.cli("unset", "FIRST")
        self.assertEqual(removed.stdout, "")
        self.assertEqual(removed.stderr, "Removed: FIRST\n")
        self.assertEqual(self.cli("list").stdout, "SECOND\n")
        self.cli("get", "FIRST", expected=1)
        self.cli("unset", "FIRST", expected=1)
        self.store.env_file.unlink()
        self.cli("sync")
        self.assertIn("SECOND=second", self.store.env_file.read_text())
        self.assertNotIn(b"second", self.store.enc_file.read_bytes())
        for path in (self.store.pass_file, self.store.env_file, self.store.enc_file):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.store.conf_dir.stat().st_mode & 0o777, 0o700)

    def test_shell_exports_preserve_quotes_unicode_and_newlines(self):
        value = "中文 'quote' \"double\" $HOME $(touch nope) `echo nope` \\ tab\t\nlast\n\n"
        self.cli("set", "SPECIAL", value)
        self.cli("set", "EMPTY", "")
        self.assertEqual(self.cli("get", "SPECIAL").stdout, value + "\n")
        self.assertEqual(self.cli("get", "EMPTY").stdout, "\n")
        for shell in ("bash", "zsh"):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                result = subprocess.run(
                    [shell, "-f", "-c", 'source "$1"; printf "%s" "$SPECIAL"',
                     "test", str(self.store.env_file)],
                    env=self.env, cwd=self.root, capture_output=True, text=True, check=True
                )
                self.assertEqual(result.stdout, value)
        self.assertFalse((self.root / "nope").exists())

    def test_read_and_update_all_legacy_formats(self):
        for container in ("raw", "v1", "v2"):
            for pass_format in ("raw", "v1", "v2"):
                with self.subTest(container=container, pass_format=pass_format):
                    self.fixture(container, pass_format)
                    self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")
                    self.cli("set", "ADDED", "new-value")
                    self.assertTrue(self.store.enc_file.read_bytes().startswith(b"QSENVENC2\n"))
                    self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")

    def test_missing_key_lists_index_without_decrypting(self):
        self.fixture()
        self.store.pass_file.unlink()
        self.assertEqual(self.cli("list").stdout, "FIXTURE\n")
        self.assertEqual(self.cli("list", "--values", expected=1).stdout, "")
        self.cli("sync", expected=1)
        self.assertFalse(self.store.env_file.exists())

    def test_failed_operations_preserve_files(self):
        self.fixture()
        self.cli("sync")
        self.store.pass_file.write_text("QSENV2:" + "0" * 64 + "\n")
        before = {path: path.read_bytes() for path in
                  (self.store.enc_file, self.store.env_file, self.store.pass_file)}
        for args in (("sync",), ("set", "NEW", "value"), ("unset", "FIXTURE")):
            self.cli(*args, expected=1)
            self.assertEqual(before, {path: path.read_bytes() for path in before})
        self.store.enc_file.write_bytes(b"QSENVENC2\nNAME\tFIXTURE\nDATA\t!invalid!\n")
        cached = self.store.env_file.read_bytes()
        self.cli("sync", expected=1)
        self.assertEqual(self.store.env_file.read_bytes(), cached)
        self.assertEqual(list(self.store.conf_dir.glob(".env.zsh.*")), [])

    def test_password_rotation_and_unlock(self):
        self.fixture()
        with patch.object(q.os, "isatty", return_value=True), \
             patch.object(q.getpass, "getpass", side_effect=["new-test-pass", "new-test-pass"]), \
             contextlib.redirect_stderr(io.StringIO()):
            self.store.reset_pass()
        expected_key = hashlib.sha256(b"new-test-pass").hexdigest()
        self.assertEqual(self.store.pass_file.read_text(), f"QSENV2:{expected_key}\n")
        self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")
        self.store.pass_file.unlink()
        cached = self.store.env_file.read_bytes()
        with patch.object(q.os, "isatty", return_value=True), \
             patch.object(q.getpass, "getpass", return_value="wrong-test-pass"):
            with self.assertRaises(q.SecretError):
                self.store.unlock()
        self.assertFalse(self.store.pass_file.exists())
        self.assertEqual(self.store.env_file.read_bytes(), cached)
        with patch.object(q.os, "isatty", return_value=True), \
             patch.object(q.getpass, "getpass", return_value="new-test-pass"), \
             contextlib.redirect_stderr(io.StringIO()):
            self.store.unlock()
        self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")

    def test_initial_password_and_mismatch(self):
        self.store.pass_file.unlink()
        with patch.object(q.os, "isatty", return_value=True), \
             patch.object(q.getpass, "getpass", side_effect=[PASSWORD, "mismatch"]):
            with self.assertRaises(q.SecretError):
                self.store.reset_pass()
        self.assertFalse(self.store.pass_file.exists())
        with patch.object(q.os, "isatty", return_value=True), \
             patch.object(q.getpass, "getpass", side_effect=[PASSWORD, PASSWORD]), \
             contextlib.redirect_stderr(io.StringIO()):
            self.store.reset_pass()
        self.assertEqual(self.store.pass_file.read_text(), f"QSENV2:{KEY}\n")

    def test_legacy_config_directory_migration(self):
        self.fixture()
        self.store.legacy_dir.mkdir(parents=True)
        self.store.pass_file.replace(self.store.legacy_dir / "master.pass")
        (self.store.legacy_dir / "env.zsh").write_text("old-cache")
        self.cli("sync")
        self.assertFalse(self.store.legacy_dir.exists())
        self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")

    def test_argparse_help_validation_and_dash_value(self):
        for args in ((), ("-h",), ("--help",), ("set", "--help"), ("list", "--help"),
                     ("unset", "--help"), ("passwd", "--help")):
            self.assertIn("usage:", self.cli(*args).stdout)
        for args in (("unknown",), ("set", "NAME"), ("sync", "extra"),
                     ("set", "NAME", "value", "--stdin")):
            self.cli(*args, expected=2)
        before = self.store.pass_file.read_bytes()
        self.cli("set", "INVALID-NAME", "value", expected=2)
        self.assertEqual(before, self.store.pass_file.read_bytes())
        self.assertFalse(self.store.enc_file.exists())
        self.cli("set", "DASH", "--", "--value")
        self.assertEqual(self.cli("get", "DASH").stdout, "--value\n")
        self.cli("unlock", expected=1)
        self.cli("passwd", expected=1)

    def test_stdin_preserves_values_and_empty_input(self):
        for value in ("中文\tquoted 'value'\nlast\n\n", ""):
            with self.subTest(value=value):
                self.assertEqual(self.cli("set", "STDIN", "--stdin", input_text=value).stdout, "")
                self.assertEqual(self.cli("get", "STDIN").stdout, value + "\n")
        before = self.store.enc_file.read_bytes()
        self.cli("set", "STDIN", "--stdin", input_text="nul\0value", expected=1)
        self.assertEqual(self.store.enc_file.read_bytes(), before)

    def test_hidden_input_and_empty_value(self):
        for value in ("hidden-test-value", ""):
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.object(q.os, "isatty", return_value=True), \
                 patch.object(q.getpass, "getpass", return_value=value) as prompt, \
                 contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(q.main(["set", "HIDDEN"]), 0)
            prompt.assert_called_once()
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "Saved: HIDDEN\n")
            self.assertEqual(self.cli("get", "HIDDEN").stdout, value + "\n")

    def test_read_commands_do_not_change_files(self):
        def snapshot():
            return {str(path.relative_to(self.root)):
                    (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode)
                    for path in self.root.rglob("*") if path.is_file()}

        for pass_format in ("raw", "v1", "v2"):
            with self.subTest(pass_format=pass_format):
                self.fixture("v2", pass_format)
                self.store.env_file.write_text("unchanged cache")
                before = snapshot()
                self.assertEqual(self.cli("list").stdout, "FIXTURE\n")
                self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")
                self.assertEqual(self.cli("list", "--values").stdout, "FIXTURE\tfixture-value\n")
                self.assertEqual(snapshot(), before)
        self.store.legacy_dir.mkdir(parents=True)
        self.store.pass_file.replace(self.store.legacy_dir / "master.pass")
        self.store.env_file.unlink()
        self.store.conf_dir.rmdir()
        before = snapshot()
        self.assertEqual(self.cli("get", "FIXTURE").stdout, "fixture-value\n")
        self.assertEqual(snapshot(), before)
        self.assertFalse(self.store.conf_dir.exists())

    def test_index_listing_needs_neither_key_nor_openssl(self):
        self.fixture()
        self.store.pass_file.unlink()
        self.store.conf_dir.rmdir()
        with patch.object(q, "crypt", side_effect=AssertionError("unexpected decrypt")), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(q.main(["list"]), 0)
        self.assertEqual(output.getvalue(), "FIXTURE\n")
        self.assertFalse(self.store.conf_dir.exists())
        self.store.ensure_dirs()
        self.fixture("v1")
        self.assertIn("list --values", self.cli("list", expected=1).stderr)
        self.assertEqual(self.cli("list", "--values").stdout, "FIXTURE\tfixture-value\n")

    def test_removed_cli_aliases_are_rejected(self):
        self.fixture()
        before = self.store.enc_file.read_bytes()
        for args in (("remove", "FIXTURE"), ("reset-pass",), ("help",),
                     ("list", "--decrypt"), ("list", "-d")):
            with self.subTest(args=args):
                result = self.cli(*args, expected=2)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.store.enc_file.read_bytes(), before)
        listing_help = self.cli("list", "--help").stdout
        self.assertIn("--values", listing_help)
        self.assertNotIn("--decrypt", listing_help)

    def test_wrapper_and_zsh_cache_hit(self):
        (self.repo / "module").mkdir()
        (self.repo / "module/q-secret-env").symlink_to(SCRIPT.parent)
        result = subprocess.run([str(ROOT / "bin/common/q-secret-env"), "--help"],
                                env=self.env, capture_output=True, text=True, check=True)
        self.assertIn("usage: q-secret-env", result.stdout)
        if not shutil.which("zsh"):
            return
        self.fixture()
        # secret-env.zsh currently uses ~/.config rather than XDG_CONFIG_HOME.
        conf = self.root / ".config"
        conf.symlink_to(self.config, target_is_directory=True)
        self.store.env_file.write_text("export CACHE_TEST=cached\n")
        stamp = self.store.enc_file.stat().st_mtime + 10
        os.utime(self.store.env_file, (stamp, stamp))
        result = subprocess.run(
            ["zsh", "-f", "-c", 'q-secret-env() { print -u2 "UNEXPECTED SYNC"; return 1; }; '
             'source "$1"; print -r -- "$CACHE_TEST"', "test", str(ROOT / "zsh/secret-env.zsh")],
            env=self.env, capture_output=True, text=True, check=True
        )
        self.assertEqual(result.stdout, "cached\n")
        self.assertEqual(result.stderr, "")
        # A cache miss invokes the new entry point and loads its regenerated file.
        self.store.env_file.unlink()
        startup_env = dict(self.env, PATH=str(ROOT / "bin/common") + os.pathsep + self.env["PATH"])
        result = subprocess.run(
            ["zsh", "-f", "-c", 'source "$1"; print -r -- "$FIXTURE"',
             "test", str(ROOT / "zsh/secret-env.zsh")],
            env=startup_env, capture_output=True, text=True, check=True
        )
        self.assertEqual(result.stdout, "fixture-value\n")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
