import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "switch_source", Path(__file__).resolve().parents[1] / "switch-source.py"
)
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class SwitchSourceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "nix.conf"
        self.selection = self.root / "source.conf"
        self.daemon = self.root / "nix-daemon.plist"
        self.daemon.touch()
        self.config.write_text(
            "substituters = https://cache.nixos.org/ https://example.invalid/cache\n"
            f"!include {self.selection}\n"
        )
        paths = patch.multiple(
            source,
            NIX_CONFIG=self.config,
            SOURCE_CONFIG=self.selection,
            DAEMON_PLIST=self.daemon,
        )
        paths.start()
        self.addCleanup(paths.stop)

    def test_non_mac_stops_before_reading_config_or_running_commands(self):
        with (
            patch.object(source.sys, "platform", "linux"),
            patch.object(source, "ensure_ready") as ready,
            patch.object(source.subprocess, "run") as run,
            contextlib.redirect_stderr(io.StringIO()) as errors,
        ):
            self.assertEqual(source.main([]), 1)
        ready.assert_not_called()
        run.assert_not_called()
        self.assertIn("仅支持 macOS", errors.getvalue())

    def test_missing_selection_defaults_to_official(self):
        self.assertEqual(source.read_source(), ("official", None))
        self.assertFalse(self.selection.exists())

    def test_requires_system_config_to_include_selection(self):
        self.config.write_text("substituters = https://cache.nixos.org/\n")
        with self.assertRaisesRegex(RuntimeError, "setup.py"):
            source.ensure_ready()

    def test_refuses_unmanaged_content_and_symlinks(self):
        self.selection.write_text("substituters = https://example.invalid/private\n")
        with self.assertRaisesRegex(RuntimeError, "非本工具管理"):
            source.read_source()
        self.selection.unlink()
        self.selection.symlink_to(self.config)
        with self.assertRaisesRegex(RuntimeError, "软链接"):
            source.read_source()

    def test_switches_both_ways_and_restarts_daemon(self):
        with patch.object(source, "restart_daemon") as restart:
            source.apply_source("sjtug")
            self.assertEqual(source.read_source()[0], "sjtug")
            self.assertEqual(self.selection.stat().st_mode & 0o777, 0o644)
            source.apply_source("official")
            self.assertEqual(source.read_source()[0], "official")
            self.assertEqual(restart.call_count, 2)

    def test_restart_failure_restores_previous_config(self):
        previous = source.source_config("sjtug")
        self.selection.write_bytes(previous)
        failure = subprocess.CalledProcessError(1, ["launchctl"])
        with patch.object(source, "restart_daemon", side_effect=[failure, None]) as restart:
            with self.assertRaisesRegex(RuntimeError, "已恢复原来的源配置"):
                source.apply_source("official")
        self.assertEqual(self.selection.read_bytes(), previous)
        self.assertEqual(restart.call_count, 2)

    def test_restart_failure_restores_missing_selection(self):
        failure = subprocess.CalledProcessError(1, ["launchctl"])
        with patch.object(source, "restart_daemon", side_effect=[failure, None]):
            with self.assertRaises(RuntimeError):
                source.apply_source("sjtug")
        self.assertFalse(self.selection.exists())

    def test_tui_cancel_and_current_source_order(self):
        with (
            patch.object(source.shutil, "which", return_value="/fzf"),
            patch.object(source.subprocess, "run", return_value=SimpleNamespace(returncode=130)) as run,
        ):
            self.assertIsNone(source.pick_source("sjtug"))
        self.assertTrue(run.call_args.kwargs["input"].startswith("sjtug\t"))

    def test_private_apply_requires_root(self):
        with (
            patch.object(source.sys, "platform", "darwin"),
            patch.object(source.os, "geteuid", return_value=501),
            patch.object(source, "apply_source") as apply,
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(source.main(["--apply", "sjtug"]), 1)
        apply.assert_not_called()

    def test_real_nix_reads_global_selection_and_retains_existing_caches(self):
        nix = shutil.which("nix")
        if not nix:
            self.skipTest("Nix is not installed")
        env = dict(os.environ, NIX_CONF_DIR=str(self.root), NIX_USER_CONF_FILES="", NIX_CONFIG="")
        for selected in ("sjtug", "official"):
            with self.subTest(source=selected), patch.object(source, "restart_daemon"):
                source.apply_source(selected)
                result = subprocess.run(
                    [nix, "--extra-experimental-features", "nix-command", "show-config", "--json"],
                    env=env, capture_output=True, text=True, check=True,
                )
                caches = json.loads(result.stdout)["substituters"]["value"]
                self.assertIn("https://cache.nixos.org/", caches)
                self.assertIn("https://example.invalid/cache", caches)
                self.assertEqual(source.MIRROR in caches, selected == "sjtug")


if __name__ == "__main__":
    unittest.main()
