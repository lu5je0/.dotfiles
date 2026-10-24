import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "nixos/modules/desktop-icons.py"
APP = "io.github.example.Player.desktop"
LAUNCHER = """[Desktop Entry]
Name=播放器
Exec=flatpak run io.github.example.Player @@u %U @@
Icon = original
MimeType=audio/flac;
Actions=NewWindow;
X-Flatpak=io.github.example.Player

[Desktop Action NewWindow]
Name=New Window
Exec=player --new-window
Icon=action-icon
"""


class DesktopIconsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.data = self.root / "data"
        self.state = self.root / "state"
        self.flatpak = self.root / "flatpak"
        self.system = self.root / "system"
        self.icon = self.root / "custom icon.svg"
        self.icon.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        self.destination = self.data / "applications" / APP
        self.config = self.root / "config.json"
        self.env = {
            **os.environ,
            "PYTHONDONTWRITEBYTECODE": "1",
            "XDG_DATA_HOME": str(self.data),
            "XDG_STATE_HOME": str(self.state),
            "XDG_DATA_DIRS": f"{self.flatpak}:{self.system}",
        }

    def install_launcher(self, root, text=LAUNCHER, name=APP):
        path = root / "applications" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_overrides(self, overrides=None):
        self.config.write_text(json.dumps({APP: str(self.icon)} if overrides is None else overrides))
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.config)],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_preserves_launcher_and_actions_using_xdg_precedence(self):
        self.install_launcher(self.flatpak)
        self.install_launcher(self.system, LAUNCHER.replace("Name=播放器", "Name=Wrong priority"))
        result = self.run_overrides()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual(
            self.destination.read_text(),
            LAUNCHER.replace("[Desktop Entry]\n", f"[Desktop Entry]\nIcon={self.icon}\n")
            .replace("Icon = original\n", ""),
        )
        self.assertEqual((self.flatpak / "applications" / APP).read_text(), LAUNCHER)

    def test_refreshes_from_upstream_and_removes_last_override(self):
        upstream = self.install_launcher(self.system)
        self.assertEqual(self.run_overrides().returncode, 0)
        updated = LAUNCHER.replace("Exec=flatpak run", "Exec=flatpak --verbose run")
        upstream.write_text(updated)
        self.assertEqual(self.run_overrides().returncode, 0)
        self.assertIn("Exec=flatpak --verbose run", self.destination.read_text())
        self.assertEqual(self.run_overrides({}).returncode, 0)
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.destination.is_symlink())
        self.assertEqual(upstream.read_text(), updated)

    def test_leaves_existing_user_launcher_untouched(self):
        self.install_launcher(self.system)
        self.install_launcher(self.data, "user-owned launcher")
        result = self.run_overrides()
        self.assertEqual(result.returncode, 1)
        self.assertIn("existing user launcher", result.stderr)
        self.assertEqual(self.destination.read_text(), "user-owned launcher")

    def test_cleanup_does_not_remove_user_replacement(self):
        self.install_launcher(self.system)
        self.assertEqual(self.run_overrides().returncode, 0)
        self.destination.unlink()
        self.destination.write_text("user replacement")
        self.assertEqual(self.run_overrides({}).returncode, 0)
        self.assertEqual(self.destination.read_text(), "user replacement")

    def test_uninstalled_application_does_not_leave_stale_launcher(self):
        upstream = self.install_launcher(self.system)
        self.assertEqual(self.run_overrides().returncode, 0)
        upstream.unlink()
        self.assertEqual(self.run_overrides().returncode, 0)
        self.assertFalse(self.destination.is_symlink())

    def test_finds_nested_desktop_id_and_inserts_missing_icon(self):
        nested_name = APP.replace(".Player.desktop", "/Player.desktop")
        flattened = nested_name.replace("/", "-")
        self.install_launcher(self.system, "[Desktop Entry]\nName=Nested\nExec=player\n", nested_name)
        result = self.run_overrides({flattened: str(self.icon)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Icon={self.icon}", (self.data / "applications" / flattened).read_text())


if __name__ == "__main__":
    unittest.main()
