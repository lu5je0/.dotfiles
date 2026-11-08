"""Run pi setup against an isolated HOME with mock package commands."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PI_DIR = Path(__file__).resolve().parents[1]
SETUP = PI_DIR.parent / "scripts/setup.d/modules/unix/pi.sh"
MOCK = r'''
import json, os, shutil, sys
from pathlib import Path

root = Path(os.environ["HOME"]) / ".pi/agent/npm"
manifest = root / "package.json"
data = json.loads(manifest.read_text()) if manifest.exists() else {"dependencies": {}}
dependencies = data["dependencies"]
command = Path(sys.argv[0]).name
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([command, *sys.argv[1:]]) + "\n")
if command == "npm":
    assert sys.argv[1:8] == ["uninstall", "--prefix", str(root), "--legacy-peer-deps", "--no-audit", "--no-fund", "--"]
    if os.environ.get("FAIL_UNINSTALL"):
        sys.exit(9)
    for name in sys.argv[8:]:
        dependencies.pop(name)
        shutil.rmtree(root / "node_modules" / name, ignore_errors=True)
else:
    assert sys.argv[1] == "install"
    spec = sys.argv[2].removeprefix("npm:")
    name = spec.rsplit("@", 1)[0] if "@" in spec[1:] else spec
    dependencies[name] = "*"
    (root / "node_modules" / name).mkdir(parents=True, exist_ok=True)
manifest.write_text(json.dumps(data))
'''


class PackageSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pi-setup-packages-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "dotfiles/pi"
        self.source.mkdir(parents=True)
        shutil.copy(PI_DIR / "jsonc.py", self.source)
        self.agent = self.root / "home/.pi/agent"
        self.npm_root = self.agent / "npm"
        self.npm_root.mkdir(parents=True)
        self.settings = self.agent / "settings.json"
        self.settings.write_text(json.dumps({"theme": "keep", "packages": ["npm:obsolete"]}))
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name in ["npm", "pi"]:
            command = bin_dir / name
            command.write_text(f"#!{sys.executable}\n" + MOCK)
            command.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root / "home"),
                        DOTFILES_DIR=str(self.source.parent),
                        PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                        COMMAND_LOG=str(self.root / "commands"))

    def configure(self, text, installed):
        (self.source / "settings.jsonc").write_text(text)
        (self.npm_root / "package.json").write_text(json.dumps({"dependencies": installed}))
        for name in installed:
            (self.npm_root / "node_modules" / name).mkdir(parents=True, exist_ok=True)

    def run_setup(self):
        return subprocess.run(["bash", str(SETUP)], env=self.env, capture_output=True, text=True)

    def commands(self):
        log = self.root / "commands"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_removed_comments_scopes_versions_and_idempotence(self):
        self.configure('''{"packages": [
            // "npm:obsolete",
            "npm:keep@^2.0", {"source": "npm:@scope/keep@3", "extensions": []},
            "npm:@scope/missing@1", "git:github.com/example/plugin@main", "/local/plugin",
        ]}''', {"keep": "^1", "@scope/keep": "2", "obsolete": "1", "@scope/old": "1"})
        transitive = self.npm_root / "node_modules/transitive"
        transitive.mkdir()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.commands()
        self.assertEqual(calls[0][0:2], ["npm", "uninstall"])
        self.assertEqual(calls[0][-2:], ["@scope/old", "obsolete"])
        self.assertEqual(calls[1], ["pi", "install", "npm:@scope/missing@1"])
        self.assertTrue(transitive.exists())
        self.assertEqual(json.loads(self.settings.read_text())["theme"], "keep")
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertEqual(self.commands(), calls)

    def test_empty_list_uninstalls_all_direct_packages(self):
        self.configure('{"packages": []}', {"obsolete": "1"})
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertEqual(self.commands()[0][-1], "obsolete")

    def test_unmanaged_packages_are_untouched(self):
        self.configure('{"editorPaddingX": 2}', {"keep": "1"})
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_invalid_config_does_not_uninstall(self):
        for config in ['{"packages": [', '{"packages": "invalid"}']:
            with self.subTest(config=config):
                self.configure(config, {"keep": "1"})
                self.assertNotEqual(self.run_setup().returncode, 0)
                self.assertEqual(self.commands(), [])

    def test_uninstall_failure_is_reported(self):
        self.configure('{"packages": ["npm:missing"]}', {"obsolete": "1"})
        self.env["FAIL_UNINSTALL"] = "1"
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual(len(self.commands()), 1)
        self.assertEqual(self.commands()[0][0], "npm")


if __name__ == "__main__":
    unittest.main()
