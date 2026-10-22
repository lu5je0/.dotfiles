import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import venv


SOURCE = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="q-python-install-", dir="/tmp")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "dotfiles repo"
        installer = self.root / "module/python-install"
        installer.mkdir(parents=True)
        for name in ("q-python-install.py", "runner.sh"):
            shutil.copy2(SOURCE / name, installer / name)
        self.generator = installer / "q-python-install.py"
        self.project = self.root / "module/demo project"
        self.project.mkdir()
        self.script = self.project / "demo.py"
        self.script.write_text("")
        mock_bin = self.base / "mock bin"
        mock_bin.mkdir()
        uv = mock_bin / "uv"
        uv.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "print(json.dumps(sys.argv[1:]))\n"
        )
        uv.chmod(0o755)
        self.env = dict(os.environ, HOME="/root", PATH=f"{mock_bin}:{os.environ['PATH']}")
        self.env.pop("DOTFILES_DIR", None)
        self.cwd = self.base / "unrelated cwd"
        self.cwd.mkdir()

    def generate(self, *options, script=None):
        result = subprocess.run(
            [sys.executable, str(self.generator), str(script or self.script), *map(str, options)],
            cwd=self.cwd, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def launch(self, launcher, *args, env=None, as_root=False):
        command = [str(launcher), *args]
        if as_root and os.geteuid() != 0:
            unshare = shutil.which("unshare")
            if not unshare:
                self.skipTest("root branch requires Linux user namespaces")
            prefix = [unshare, "--user", "--map-root-user", "--"]
            probe = subprocess.run([*prefix, "true"], capture_output=True, text=True)
            if probe.returncode:
                self.skipTest(f"user namespaces unavailable: {probe.stderr.strip()}")
            command = [*prefix, *command]
        return subprocess.run(
            command, cwd=self.cwd, env=env or self.env,
            capture_output=True, text=True, timeout=15,
        )

    def run_launcher(self, launcher, *args, env=None, as_root=False):
        result = self.launch(launcher, *args, env=env, as_root=as_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_home_independent_paths_and_argument_forwarding(self):
        self.generate()
        launcher = self.root / "bin/common/demo"
        env = dict(self.env, PATH=f"{launcher.parent}:{self.env['PATH']}")
        for command in (launcher, os.path.relpath(launcher, self.cwd), "demo"):
            with self.subTest(command=str(command)):
                self.assertEqual(
                    self.run_launcher(command, "--flag", "value with spaces", "$HOME", env=env),
                    ["run", "--project", str(self.project), str(self.script),
                     "--flag", "value with spaces", "$HOME"],
                )

    def test_custom_output_symlink_chain_and_script_settings(self):
        (self.project / ".script").write_text(
            'TARGET_NAME=custom-name\nSCRIPT_EXTRAS="first second"\n'
        )
        output = self.base / "custom bin"
        self.generate("-o", output)
        self.assertTrue((output / "custom-name").is_file())
        self.generate("-o", output, "--output-name", "alias tool")
        first = self.base / "links with spaces/relative link"
        first.parent.mkdir()
        first.symlink_to(os.path.relpath(output / "alias tool", first.parent))
        second = self.base / "absolute link"
        second.symlink_to(first)
        self.assertEqual(
            self.run_launcher(second),
            ["run", "--project", str(self.project), "--extra", "first", "--extra", "second",
             str(self.script)],
        )

    def test_exported_cdpath_with_relative_launcher_and_symlink(self):
        self.generate()
        launcher = self.root / "bin/common/demo"
        link = self.base / "links/demo"
        link.parent.mkdir()
        link.symlink_to(os.path.relpath(launcher, link.parent))
        self.cwd = self.base
        env = dict(self.env, CDPATH=".")
        for path in (launcher, link):
            with self.subTest(path=str(path)):
                self.assertEqual(
                    self.run_launcher(os.path.relpath(path, self.cwd), env=env),
                    ["run", "--project", str(self.project), str(self.script)],
                )

    def test_repository_relocation(self):
        self.generate()
        moved = self.base / "moved repo"
        self.root.rename(moved)
        project = moved / self.project.relative_to(self.root)
        self.assertEqual(
            self.run_launcher(moved / "bin/common/demo"),
            ["run", "--project", str(project), str(project / self.script.name)],
        )

    def test_explicit_dotfiles_directory(self):
        self.generate()
        override = self.base / "override repo"
        shutil.copytree(self.root, override)
        project = override / self.project.relative_to(self.root)
        self.assertEqual(
            self.run_launcher(self.root / "bin/common/demo", env=dict(self.env, DOTFILES_DIR=str(override))),
            ["run", "--project", str(project), str(project / self.script.name)],
        )

    def test_external_project_and_shell_characters(self):
        project = self.base / "dotfiles repo-other's $project"
        project.mkdir()
        script = project / "tool's $name.py"
        script.write_text("")
        output = self.base / "output's $dir"
        self.generate("-o", output, script=script)
        self.assertEqual(
            self.run_launcher(output / script.stem),
            ["run", "--project", str(project), str(script)],
        )

    def test_macos_ocr_extras_survive_regeneration(self):
        shutil.copy2(SOURCE.parent / "iocr/.script", self.project / ".script")
        uname = self.base / "mock bin/uname"
        uname.write_text("#!/bin/bash\nprintf '%s\\n' Darwin\n")
        uname.chmod(0o755)
        self.generate()
        self.assertEqual(
            self.run_launcher(self.root / "bin/common/oo"),
            ["run", "--project", str(self.project), "--extra", "macos", str(self.script)],
        )

    def disallow_uv(self):
        (self.base / "mock bin/uv").write_text("#!/bin/bash\necho 'uv must not run' >&2\nexit 97\n")

    def write_probe_script(self):
        (self.project / "local_module.py").write_text("VALUE = 'local import'\n")
        self.script.write_text(
            "import json, os, subprocess, sys\n"
            "import local_module\n"
            "print(json.dumps({\n"
            "    'uid': os.geteuid(), 'argv': sys.argv[1:],\n"
            "    'module': local_module.VALUE,\n"
            "    'no_bytecode': sys.dont_write_bytecode,\n"
            "    'child_no_bytecode': subprocess.check_output(\n"
            "        [sys.executable, '-c', 'import sys; print(sys.dont_write_bytecode)'],\n"
            "        text=True).strip(),\n"
            "    'venv': os.environ.get('VIRTUAL_ENV'),\n"
            "    'path': os.environ['PATH'].split(os.pathsep)[0],\n"
            "}))\n"
        )

    def snapshot_project(self):
        return {
            str(path.relative_to(self.project)): (
                path.lstat().st_mode, path.lstat().st_uid, path.lstat().st_gid,
                path.lstat().st_size, path.lstat().st_mtime_ns,
            )
            for path in self.project.rglob("*")
        }

    def test_system_python_without_uv(self):
        (self.project / ".script").write_text("SCRIPT_RUNNER=python3\n")
        self.write_probe_script()
        self.generate()
        self.disallow_uv()
        before = self.snapshot_project()
        result = self.run_launcher(self.root / "bin/common/demo", "--flag", "a b")
        self.assertEqual(result["argv"], ["--flag", "a b"])
        self.assertEqual(result["module"], "local import")
        self.assertTrue(result["no_bytecode"])
        self.assertEqual(self.snapshot_project(), before)

    def test_root_system_python_does_not_write_bytecode(self):
        shutil.copy2(SOURCE.parent / "q-restic/.script", self.project / ".script")
        self.write_probe_script()
        self.generate()
        self.disallow_uv()
        before = self.snapshot_project()
        result = self.run_launcher(self.root / "bin/common/demo", "a b", as_root=True)
        self.assertEqual(result["uid"], 0)
        self.assertEqual(result["argv"], ["a b"])
        self.assertTrue(result["no_bytecode"])
        self.assertEqual(result["child_no_bytecode"], "True")
        self.assertEqual(self.snapshot_project(), before)

    def test_root_uses_prepared_environment_without_mutations(self):
        venv_dir = self.project / ".venv"
        venv.EnvBuilder(with_pip=False, symlinks=True).create(venv_dir)
        self.write_probe_script()
        (self.project / "uv.lock").write_text("unchanged lockfile\n")
        self.generate()
        self.disallow_uv()
        before = self.snapshot_project()
        result = self.run_launcher(
            self.root / "bin/common/demo", "--flag", "a b", as_root=True,
            env=dict(self.env, VIRTUAL_ENV="wrong environment", PYTHONDONTWRITEBYTECODE=""),
        )
        self.assertEqual(result["uid"], 0)
        self.assertEqual(result["argv"], ["--flag", "a b"])
        self.assertEqual(result["module"], "local import")
        self.assertEqual(result["venv"], str(venv_dir))
        self.assertEqual(result["path"], str(venv_dir / "bin"))
        self.assertTrue(result["no_bytecode"])
        self.assertEqual(result["child_no_bytecode"], "True")
        self.assertEqual(self.snapshot_project(), before)

    def test_root_reports_missing_or_broken_environment(self):
        self.generate()
        self.disallow_uv()
        for broken in (False, True):
            with self.subTest(broken=broken):
                if broken:
                    python = self.project / ".venv/bin/python"
                    python.parent.mkdir(parents=True)
                    python.symlink_to(self.base / "missing interpreter")
                before = self.snapshot_project()
                result = self.launch(self.root / "bin/common/demo", as_root=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("prepared Python environment not found", result.stderr)
                self.assertIn("regular user", result.stderr)
                self.assertEqual(self.snapshot_project(), before)

    def test_unknown_runner_reports_configuration_error(self):
        (self.project / ".script").write_text("SCRIPT_RUNNER=unknown\n")
        self.generate()
        self.disallow_uv()
        result = self.launch(self.root / "bin/common/demo")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("unknown SCRIPT_RUNNER: unknown", result.stderr)


if __name__ == "__main__":
    unittest.main()
