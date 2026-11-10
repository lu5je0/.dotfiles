"""Installer integration tests using local release fixtures, without networking."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/setup.d/modules/unix/q-trash.sh"
VERSION = next(line.split('"')[1] for line in (ROOT / "module/q-trash/Cargo.toml").read_text().splitlines() if line.startswith("version = "))


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qtrash_install_")
        self.home = Path(self.tmp.name)
        self.mock = self.home / "mock"
        self.mock.mkdir()
        for name in ("dirname", "sed", "head", "awk", "mkdir", "mktemp", "rm", "chmod", "mv", "sha256sum", "shasum"):
            command = shutil.which(name)
            if command:
                (self.mock / name).symlink_to(command)
        (self.mock / "python3").symlink_to(sys.executable)
        self.release = self.home / "release"
        self.release.mkdir()
        self.target = self.home / ".local/bin/q-trash"
        self.env = {**os.environ, "HOME": str(self.home), "DOTFILES_DIR": str(ROOT),
                    "PATH": str(self.mock),
                    "RELEASE_FIXTURE": str(self.release), "MOCK_OS": "Linux", "MOCK_ARCH": "x86_64"}
        self.env.pop("TERMUX_VERSION", None)
        self.write_exec(self.mock / "uname", '#!/bin/sh\ncase "$1" in -s) echo "$MOCK_OS";; -m) echo "$MOCK_ARCH";; -o) echo GNU/Linux;; esac\n')
        self.write_exec(self.mock / "curl", '''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args=sys.argv[1:]
url=next(a for a in args if a.startswith("https://"))
source=pathlib.Path(os.environ["RELEASE_FIXTURE"])/url.rsplit("/",1)[1]
if not source.exists(): sys.exit(22)
shutil.copyfile(source,args[args.index("-o")+1])
''')

    def tearDown(self):
        self.tmp.cleanup()

    def write_exec(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def fixture(self, name="q-trash-linux-x86_64", version=VERSION):
        payload = self.release / name
        self.write_exec(payload, f"#!/bin/sh\necho 'q-trash {version}'\n")
        digest = hashlib.sha256(payload.read_bytes()).hexdigest()
        (self.release / "SHA256SUMS").write_text(f"{digest}  {name}\n")

    def install(self):
        return subprocess.run([shutil.which("bash"), str(SCRIPT)], env=self.env,
                              capture_output=True, text=True)

    def test_install_and_idempotent(self):
        self.fixture()
        self.assertEqual(self.install().returncode, 0)
        self.assertTrue(os.access(self.target, os.X_OK))
        self.assertIn("already installed", self.install().stdout)
        self.assertEqual(list(self.target.parent.glob(".q-trash.*")), [])

    def test_bad_checksum_keeps_old_binary(self):
        self.write_exec(self.target, "#!/bin/sh\necho old\n")
        self.fixture()
        (self.release / "SHA256SUMS").write_text("0" * 64 + "  q-trash-linux-x86_64\n")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertIn("echo old", self.target.read_text())

    def test_bad_version_keeps_old_binary(self):
        self.write_exec(self.target, "#!/bin/sh\necho old\n")
        self.fixture(version="0.0.0")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertIn("echo old", self.target.read_text())

    def test_download_failure_keeps_old_symlink(self):
        old = self.home / "old.py"
        self.write_exec(old, "#!/bin/sh\necho old\n")
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(old)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertTrue(self.target.is_symlink())
        self.assertIn("echo old", old.read_text())

    def test_replaces_symlink_without_writing_source(self):
        old = self.home / "old.py"
        self.write_exec(old, "#!/bin/sh\necho old\n")
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(old)
        self.fixture()
        self.assertEqual(self.install().returncode, 0)
        self.assertFalse(self.target.is_symlink())
        self.assertIn("echo old", old.read_text())

    def test_macos_arm_asset(self):
        self.env.update(MOCK_OS="Darwin", MOCK_ARCH="arm64")
        self.fixture(name="q-trash-macos-aarch64")
        self.assertEqual(self.install().returncode, 0)

    def test_shell_respects_path_for_both_commands(self):
        zsh = shutil.which("zsh")
        if not zsh:
            self.skipTest("zsh unavailable")
        self.write_exec(self.target, '#!/bin/sh\necho "local $*"\n')
        self.write_exec(self.mock / "q-trash", '#!/bin/sh\necho "system $*"\n')
        config = (ROOT / "zshrc").read_text()
        start = config.index("if [[ -o interactive ]]; then\n  safe_rm()")
        fragment = config[start:config.index("\nalias sudo=", start)]
        script = self.home / "shell.zsh"
        script.write_text(fragment + '\neval "q-trash --version"\nsafe_rm operand\n')
        env = {**self.env, "PATH": str(self.target.parent) + ":" + str(self.mock)}
        for prefix in ("local", "system"):
            with self.subTest(selected=prefix):
                result = subprocess.run([zsh, "-f", "-i", str(script)], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(),
                                 [f"{prefix} --version", f"{prefix} rm operand"])
            if prefix == "local":
                self.target.unlink()

    def test_unsupported_arch(self):
        self.env["MOCK_ARCH"] = "mips"
        self.assertNotEqual(self.install().returncode, 0)
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
