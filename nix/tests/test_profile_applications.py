import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "nixos/modules/gnome/profile-applications/sync.py"
spec = importlib.util.spec_from_file_location("profile_applications", SCRIPT)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)
DESKTOP_DATABASE = os.environ.get("UPDATE_DESKTOP_DATABASE") or shutil.which("update-desktop-database")
GJS = shutil.which("gjs")

LAUNCHER = """[Desktop Entry]
Type=Application
Name=示例
Exec=player %U
Icon=player
MimeType=audio/flac;
Actions=New;

[Desktop Action New]
Exec=player --new
Icon=player
"""


class ProfileApplicationsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / "data"
        self.state = self.root / "state"
        self.profile = self.root / "profile"
        self.system = self.root / "system"
        self.applications = self.data / "applications"

    def generation(self, name, launcher=LAUNCHER, desktop_id="player.desktop"):
        generation = self.root / name
        applications = generation / "share/applications"
        applications.mkdir(parents=True)
        if launcher is not None:
            destination = applications / desktop_id
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(launcher)
        icons = generation / "share/icons/hicolor/scalable/apps"
        icons.mkdir(parents=True)
        (icons / "player.svg").write_text("<svg/>")
        return generation

    def switch(self, generation, profile=None):
        profile = profile or self.profile
        temporary = profile.with_suffix(".tmp")
        temporary.symlink_to(generation)
        temporary.replace(profile)

    def run_sync(self, excluded=(), force=False, desktop_database=None):
        return sync.sync([self.profile, self.system], self.data, self.state, excluded, force, desktop_database)

    @unittest.skipUnless(DESKTOP_DATABASE and shutil.which("gio"), "requires desktop-file-utils and gio")
    def test_gio_registers_and_unregisters_mime_handlers(self):
        desktop_id = "io.github.example.TestFiles.desktop"
        launcher = LAUNCHER.replace("audio/flac", "inode/directory").replace("Exec=player", f"Exec={sys.executable}")
        self.switch(self.generation("first", launcher, desktop_id))
        self.run_sync(desktop_database=DESKTOP_DATABASE)
        env = {**os.environ, "XDG_DATA_HOME": str(self.data), "XDG_STATE_HOME": str(self.state),
               "XDG_CONFIG_HOME": str(self.root / "config"), "XDG_DATA_DIRS": str(self.profile / "share")}

        def handlers():
            return subprocess.run(["gio", "mime", "inode/directory"], env=env,
                                  text=True, capture_output=True, check=True).stdout

        self.assertIn(desktop_id, handlers())
        self.switch(self.generation("empty", None))
        self.run_sync(desktop_database=DESKTOP_DATABASE)
        self.assertNotIn(desktop_id, handlers())

    def test_retries_failed_mime_update_without_losing_file_ownership(self):
        self.switch(self.generation("first"))
        from unittest.mock import patch
        with patch.object(sync.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "updater")):
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_sync(desktop_database="updater")
        with patch.object(sync.subprocess, "run") as update:
            self.assertTrue(self.run_sync(desktop_database="updater"))
            update.assert_called_once()
        manifest = json.loads((self.state / "nix-profile-applications/manifest.json").read_text())
        self.assertTrue(manifest["mime_cache_ready"])
        self.assertIn("player.desktop", manifest["entries"])

    def test_install_upgrade_and_uninstall_preserve_launcher_fields(self):
        first = self.generation("first")
        self.switch(first)
        self.assertTrue(self.run_sync())
        destination = self.applications / "player.desktop"
        source = self.state / "nix-profile-applications/launchers/player.desktop"
        icon = first / "share/icons/hicolor/scalable/apps/player.svg"
        self.assertEqual(source.read_text(), LAUNCHER.replace("Icon=player", f"Icon={icon}"))
        self.assertIn("MimeType=audio/flac;", destination.read_text())
        self.assertIn("Actions=New;", destination.read_text())
        command = next(line for line in destination.read_text().splitlines() if line.startswith("Exec="))
        self.assertFalse(destination.is_symlink())
        second = self.generation("second", LAUNCHER.replace("Exec=player", "Exec=player-v2"))
        self.switch(second)
        self.run_sync()
        self.assertIn("Exec=player-v2 %U", source.read_text())
        self.assertIn(command, destination.read_text())
        self.assertIn(str(second), destination.read_text())
        self.assertNotIn(str(first), destination.read_text())
        self.switch(self.generation("empty", None))
        self.run_sync()
        self.assertFalse(destination.exists())
        self.assertFalse(source.exists())

    @unittest.skipUnless(GJS and shutil.which("gio"), "requires GJS and GIO")
    def test_cached_launcher_uses_latest_command_arguments_cwd_and_actions(self):
        # Keep an old desktop entry, as Shell does, while upgrading its source.
        self.state = self.root / 'state % "$`\\'
        recorder = self.root / "record.py"
        result = self.root / "result.json"
        recorder.write_text("import json,os,sys\nfrom pathlib import Path\n"
                            "Path(sys.argv[1]).write_text(json.dumps([os.getcwd(), sys.argv[2:]]))\n")
        cwd = self.root / "working directory"
        cwd.mkdir()
        source = LAUNCHER.replace("Exec=player", f'Exec={sys.executable} "{recorder}" "{result}" old')
        source = source.replace("Icon=player", "Icon=player\nPath=" + str(cwd))
        self.switch(self.generation("first", source))
        self.run_sync()
        cached = self.root / "cached.desktop"
        cached.write_bytes((self.applications / "player.desktop").read_bytes())
        source = source.replace(" old", " new").replace("--new", "--updated-action")
        self.switch(self.generation("second", source))
        self.run_sync()
        uri = "file:///tmp/example%20file.txt"
        remote_uri = "https://example.invalid/example%20file.txt"
        subprocess.run(["gio", "launch", str(cached), uri, remote_uri], check=True, capture_output=True)

        def recorded():
            deadline = time.monotonic() + 5
            while not result.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(result.exists(), "application did not launch")
            return json.loads(result.read_text())

        self.assertEqual(recorded(), [str(cwd), ["new", "/tmp/example file.txt", remote_uri]])
        result.unlink()
        script = self.root / "action.js"
        script.write_text("import GioUnix from 'gi://GioUnix';\n"
                          "GioUnix.DesktopAppInfo.new_from_filename(ARGV[0]).launch_action('New', null);\n")
        subprocess.run([GJS, "-m", str(script), str(cached)], check=True, capture_output=True)
        self.assertEqual(recorded(), [str(cwd), ["new", "--updated-action"]])

    def test_proxy_leaves_terminal_and_dbus_activation_to_latest_source(self):
        source = LAUNCHER.replace("Type=Application", "Type=Application\nTerminal=true\nDBusActivatable=true\nPath=/old/path\nTryExec=/old/binary")
        self.switch(self.generation("first", source))
        self.run_sync()
        text = (self.applications / "player.desktop").read_text()
        self.assertIn("Terminal=false\nDBusActivatable=false\n", text)
        self.assertNotIn("Path=/old/path", text)
        self.assertNotIn("TryExec=/old/binary", text)
        self.assertIn("Terminal=true\nDBusActivatable=true", (self.state / "nix-profile-applications/launchers/player.desktop").read_text())

    def test_restores_missing_dispatcher_and_source_without_generation_change(self):
        self.switch(self.generation("first"))
        self.run_sync()
        for name in ["launch.js", "launchers/player.desktop"]:
            target = self.state / "nix-profile-applications" / name
            original = target.read_bytes()
            target.unlink()
            self.assertTrue(self.run_sync())
            self.assertEqual(target.read_bytes(), original)

    def test_system_switch_and_user_priority(self):
        self.switch(self.generation("system-v1", LAUNCHER.replace("Name=示例", "Name=System")), self.system)
        self.run_sync()
        destination = self.applications / "player.desktop"
        self.assertIn("Name=System", destination.read_text())
        self.switch(self.generation("user"))
        self.run_sync()
        self.assertIn("Name=示例", destination.read_text())
        self.profile.unlink()
        self.switch(self.generation("system-v2", LAUNCHER.replace("Name=示例", "Name=System v2")), self.system)
        self.run_sync()
        self.assertIn("Name=System v2", destination.read_text())

    def test_unchanged_generation_does_not_rewrite_files(self):
        self.switch(self.generation("first"))
        self.run_sync()
        destination = self.applications / "player.desktop"
        before = destination.stat()
        self.assertFalse(self.run_sync())
        self.assertEqual(destination.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(destination.stat().st_ino, before.st_ino)

    def test_restores_missing_managed_launcher_without_generation_change(self):
        self.switch(self.generation("first"))
        self.run_sync()
        destination = self.applications / "player.desktop"
        original = destination.read_bytes()
        destination.unlink()
        self.assertTrue(self.run_sync())
        self.assertEqual(destination.read_bytes(), original)
        self.assertFalse(self.run_sync())

    def test_preserves_manual_files_and_links(self):
        self.switch(self.generation("first"))
        self.applications.mkdir(parents=True)
        destination = self.applications / "player.desktop"
        destination.write_text("manual")
        self.run_sync()
        self.assertEqual(destination.read_text(), "manual")
        destination.unlink()
        destination.symlink_to(self.root / "missing-custom-launcher")
        self.run_sync(force=True)
        self.assertTrue(destination.is_symlink())
        self.assertEqual(destination.readlink(), self.root / "missing-custom-launcher")

    def test_preserves_user_edits_on_upgrade_and_uninstall(self):
        self.switch(self.generation("first"))
        self.run_sync()
        destination = self.applications / "player.desktop"
        destination.write_text("user modified")
        self.switch(self.generation("second"))
        self.run_sync()
        self.assertEqual(destination.read_text(), "user modified")
        self.switch(self.generation("empty", None))
        self.run_sync()
        self.assertEqual(destination.read_text(), "user modified")

    def test_adopts_direct_profile_links_and_respects_icon_overrides(self):
        self.switch(self.generation("first"))
        self.applications.mkdir(parents=True)
        destination = self.applications / "player.desktop"
        destination.symlink_to(self.profile / "share/applications/player.desktop")
        self.run_sync()
        self.assertFalse(destination.is_symlink())
        self.run_sync(excluded=["player.desktop"])
        self.assertFalse(destination.exists())
        destination.symlink_to(self.root / "custom-icon-override")
        self.run_sync(excluded=["player.desktop"], force=True)
        self.assertTrue(destination.is_symlink())
        destination.unlink()
        destination.symlink_to(self.profile / "share/applications/player.desktop")
        self.run_sync(excluded=["player.desktop"], force=True)
        self.assertFalse(destination.is_symlink())

    def test_nested_and_symlinked_directories_and_unknown_icons(self):
        generation = self.generation("first", LAUNCHER + "Icon=unknown-theme-icon\n", "nested/player.desktop")
        hicolor = generation / "share/icons/hicolor"
        icon_package = self.root / "icon-package"
        hicolor.rename(icon_package)
        hicolor.symlink_to(icon_package)
        self.switch(generation)
        self.run_sync()
        text = (self.applications / "nested-player.desktop").read_text()
        self.assertIn(f"Icon={icon_package}/scalable/apps/player.svg", text)
        self.assertIn("Icon=unknown-theme-icon", text)

    def test_cleans_dangling_direct_profile_links_only(self):
        self.applications.mkdir(parents=True)
        dangling = self.applications / "removed.desktop"
        dangling.symlink_to(self.profile / "share/applications/removed.desktop")
        custom = self.applications / "custom.desktop"
        custom.symlink_to(self.root / "missing")
        self.run_sync()
        self.assertFalse(dangling.is_symlink())
        self.assertTrue(custom.is_symlink())

    def test_reconciles_a_switch_during_sync(self):
        first = self.generation("first")
        second = self.generation("second", LAUNCHER.replace("Name=示例", "Name=Second"))
        self.switch(first)
        original = sync.icon_index

        def index_and_switch(share):
            result = original(share)
            if share == first / "share":
                self.switch(second)
            return result

        from unittest.mock import patch
        with patch.object(sync, "icon_index", side_effect=index_and_switch):
            self.run_sync()
        self.assertIn("Name=Second", (self.applications / "player.desktop").read_text())
        manifest = json.loads((self.state / "nix-profile-applications/manifest.json").read_text())
        self.assertEqual(manifest["identity"]["generations"][0], str(second))


if __name__ == "__main__":
    unittest.main()
