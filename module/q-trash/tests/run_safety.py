"""Filesystem regression tests; all writes stay inside temporary fake homes."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BIN = Path(os.environ.get("QTRASH_BIN", Path(__file__).resolve().parents[1] / "target/debug/q-trash")).resolve()


@unittest.skipUnless(sys.platform.startswith("linux"), "isolated freedesktop tests")
class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qtrash_safety_")
        self.home = Path(self.tmp.name)
        self.work = self.home / "work"
        self.work.mkdir()
        self.trash = self.home / ".local/share/Trash"
        self.env = {**os.environ, "HOME": str(self.home)}
        self.env.pop("XDG_DATA_HOME", None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, **kwargs):
        return subprocess.run([str(BIN), *args], env=self.env, cwd=self.work,
                              capture_output=True, **kwargs)

    def put(self, name="item", content="backup"):
        p = self.work / name
        p.write_text(content)
        result = self.run_cli("rm", str(p))
        self.assertEqual(result.returncode, 0, result.stderr)
        return p

    def test_orphan_backup_is_not_overwritten(self):
        self.trash.joinpath("files").mkdir(parents=True, mode=0o700)
        self.trash.chmod(0o700)
        orphan = self.trash / "files/item"
        orphan.write_text("keep")
        self.put()
        self.assertEqual(orphan.read_text(), "keep")
        self.assertEqual((self.trash / "files/item_2").read_text(), "backup")
        self.assertFalse((self.trash / "info/item.trashinfo").exists())

    def test_concurrent_same_basename(self):
        sources = []
        for i in range(16):
            d = self.work / str(i)
            d.mkdir()
            p = d / "same"
            p.write_text(str(i))
            sources.append(p)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda p: self.run_cli("rm", str(p)), sources))
        self.assertTrue(all(r.returncode == 0 for r in results), [r.stderr for r in results])
        files = list((self.trash / "files").iterdir())
        self.assertEqual({p.read_text() for p in files}, {str(i) for i in range(16)})
        self.assertEqual(len(list((self.trash / "info").iterdir())), 16)

    def test_symlink_trash_refused(self):
        outside = self.home / "outside"
        outside.mkdir()
        self.trash.parent.mkdir(parents=True)
        self.trash.symlink_to(outside, target_is_directory=True)
        source = self.work / "keep"
        source.write_text("keep")
        self.assertEqual(self.run_cli("rm", str(source)).returncode, 1)
        self.assertEqual(source.read_text(), "keep")
        self.assertEqual(list(outside.iterdir()), [])

    def test_non_utf8_round_trip_and_equals_destination(self):
        original = os.fsencode(self.work) + b"/raw-\xff"
        with open(original, "wb") as f:
            f.write(b"bytes")
        self.assertEqual(self.run_cli("rm", original).returncode, 0)
        info = next((self.trash / "info").iterdir()).read_text()
        self.assertIn("raw-%FF", info)
        dest = os.fsencode(self.work) + b"/dest-\xfe"
        result = self.run_cli("restore", original, b"--dest=" + dest)
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(dest, "rb") as f:
            self.assertEqual(f.read(), b"bytes")

    def test_failed_move_cleans_metadata(self):
        self.put()
        self.assertEqual(self.run_cli("rm", "missing").returncode, 1)
        self.assertEqual(len(list((self.trash / "info").iterdir())), 1)

    def test_restore_preserves_dangling_target(self):
        original = self.put()
        original.symlink_to("missing-target")
        result = self.run_cli("restore", str(original))
        self.assertEqual(result.returncode, 1)
        self.assertTrue(original.is_symlink())
        self.assertEqual((self.trash / "files/item").read_text(), "backup")

    def test_restore_does_not_delete_own_backup(self):
        original = self.put()
        backup = self.trash / "files/item"
        result = self.run_cli("restore", "--overwrite", str(original), "--dest", str(backup))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(backup.read_text(), "backup")

    def test_restore_cannot_remove_backup_parent(self):
        original = self.put(name="files")
        result = self.run_cli("restore", "--overwrite", str(original), "--dest", str(self.trash))
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.trash / "files/files").read_text(), "backup")

    def test_restore_symlink_can_overwrite_file(self):
        source = self.work / "dangling"
        source.symlink_to("absent")
        self.assertEqual(self.run_cli("rm", str(source)).returncode, 0)
        source.write_text("blocker")
        result = self.run_cli("restore", "--overwrite", str(source))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(source.is_symlink())
        self.assertEqual(os.readlink(source), "absent")

    def test_relative_metadata_cannot_escape_volume(self):
        self.put()
        info = self.trash / "info/item.trashinfo"
        info.write_text("[Trash Info]\nPath=../../escape\nDeletionDate=2026-01-01T00:00:00\n")
        result = self.run_cli("list")
        self.assertNotIn(b"escape", result.stdout)
        self.assertEqual((self.trash / "files/item").read_text(), "backup")

    def test_dot_checks_do_not_strip_filename_spaces(self):
        p = self.work / ".. "
        p.mkdir()
        self.assertEqual(self.run_cli("rm", "-r", ".. ").returncode, 0)
        self.assertFalse(p.exists())

    def test_current_disk(self):
        original = self.put()
        result = self.run_cli("list", "--current-disk")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(os.fsencode(original), result.stdout)

    def test_days_old_item(self):
        self.put()
        info = self.trash / "info/item.trashinfo"
        text = info.read_text()
        text = "\n".join("DeletionDate=2000-01-01T00:00:00" if l.startswith("DeletionDate=") else l for l in text.splitlines()) + "\n"
        info.write_text(text)
        result = self.run_cli("empty", "-f", "--days", "30")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.trash / "files/item").exists())

    def test_latest_of_many_duplicates(self):
        for i in range(12):
            original = self.put(content=str(i))
        result = self.run_cli("restore", str(original))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(original.read_text(), "11")

    def test_short_flags_order(self):
        p = self.work / "a"
        p.write_text("x")
        result = self.run_cli("rm", "-fi", "a", input=b"n\n")
        self.assertEqual(result.returncode, 0)
        self.assertTrue(p.exists())
        self.assertEqual(self.run_cli("rm", "-if", "a").returncode, 0)
        self.assertFalse(p.exists())


if __name__ == "__main__":
    unittest.main()
