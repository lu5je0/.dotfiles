"""Tests for q-rm. Run with: python3 -m pytest tests/ -v"""
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

import pytest

HERE = Path(__file__).resolve().parent
QTRASH = HERE.parent / "q-trash.py"


def run_qrm(*args, env=None, cwd=None, input_text=None):
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        [sys.executable, str(QTRASH), "rm", *args],
        capture_output=True, text=True, env=e, cwd=cwd, input=input_text,
    )


@pytest.fixture
def fake_home(tmp_path, monkeypatch):
    """Use tmp_path as HOME so trash goes to tmp_path/.local/share/Trash.

    All test files live under tmp_path so they share volume with HOME →
    they go to the home trash.
    """
    home = tmp_path / "home"
    home.mkdir()
    work = tmp_path / "work"
    work.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_DATA_HOME", raising=False)
    return home, work


def home_trash(home: Path) -> Path:
    return home / ".local" / "share" / "Trash"


needs_freedesktop = pytest.mark.skipif(
    sys.platform == "darwin", reason="macOS uses system trash, not freedesktop"
)


@needs_freedesktop
def test_remove_single_file(fake_home):
    home, work = fake_home
    f = work / "a.txt"
    f.write_text("hello")
    r = run_qrm(str(f), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert not f.exists()
    files = list((home_trash(home) / "files").iterdir())
    assert len(files) == 1
    assert files[0].name == "a.txt"
    assert files[0].read_text() == "hello"


def test_remove_directory_requires_r(fake_home):
    home, work = fake_home
    d = work / "d"
    d.mkdir()
    r = run_qrm(str(d), env={"HOME": str(home)})
    assert r.returncode == 1
    assert "Is a directory" in r.stderr
    assert d.exists()


@needs_freedesktop
def test_remove_directory_with_r(fake_home):
    home, work = fake_home
    d = work / "d"
    d.mkdir()
    (d / "inner.txt").write_text("x")
    r = run_qrm("-r", str(d), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert not d.exists()
    files = list((home_trash(home) / "files").iterdir())
    assert files[0].name == "d"
    assert (files[0] / "inner.txt").read_text() == "x"


def test_remove_empty_dir_with_d(fake_home):
    home, work = fake_home
    d = work / "empty"
    d.mkdir()
    r = run_qrm("-d", str(d), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert not d.exists()


def test_force_silences_missing(fake_home):
    home, work = fake_home
    r = run_qrm("-f", str(work / "missing"), env={"HOME": str(home)})
    assert r.returncode == 0
    assert r.stderr == ""


def test_missing_without_force_errors(fake_home):
    home, work = fake_home
    r = run_qrm(str(work / "missing"), env={"HOME": str(home)})
    assert r.returncode == 1
    assert "No such file" in r.stderr


@needs_freedesktop
def test_collision_renaming(fake_home):
    home, work = fake_home
    for i in range(3):
        f = work / "same"
        f.write_text(f"v{i}")
        r = run_qrm(str(f), env={"HOME": str(home)})
        assert r.returncode == 0, r.stderr
    files_dir = home_trash(home) / "files"
    info_dir = home_trash(home) / "info"
    names = sorted(p.name for p in files_dir.iterdir())
    assert names == ["same", "same_2", "same_3"]
    info_names = sorted(p.name for p in info_dir.iterdir())
    assert info_names == ["same.trashinfo", "same_2.trashinfo",
                          "same_3.trashinfo"]


@needs_freedesktop
def test_trashinfo_format(fake_home):
    home, work = fake_home
    f = work / "weird name with space.txt"
    f.write_text("x")
    r = run_qrm(str(f), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    info_files = list((home_trash(home) / "info").iterdir())
    assert len(info_files) == 1
    content = info_files[0].read_text()
    assert content.startswith("[Trash Info]\n")
    lines = content.strip().split("\n")
    assert lines[0] == "[Trash Info]"
    path_line = next(l for l in lines if l.startswith("Path="))
    date_line = next(l for l in lines if l.startswith("DeletionDate="))
    decoded = unquote(path_line[len("Path="):])
    assert decoded == str(f.resolve())
    # ISO 8601 local time, no offset
    import re
    assert re.match(
        r"^DeletionDate=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$", date_line
    )


def test_dot_dotdot_refused(fake_home):
    home, work = fake_home
    r = run_qrm(".", env={"HOME": str(home)}, cwd=str(work))
    assert r.returncode == 1
    assert "refusing" in r.stderr


def test_preserve_root(fake_home):
    home, _ = fake_home
    r = run_qrm("-rf", "/", env={"HOME": str(home)})
    assert r.returncode == 1
    assert "dangerous" in r.stderr


def test_purge_bypasses_trash(fake_home):
    home, work = fake_home
    f = work / "p.txt"
    f.write_text("x")
    r = run_qrm("--purge", str(f), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert not f.exists()
    # No trash dir should be created when purging files outside trash flow
    trash = home_trash(home)
    if trash.exists():
        assert list((trash / "files").iterdir()) == []


def test_double_dash_terminates_options(fake_home):
    home, work = fake_home
    f = work / "-weird"
    f.write_text("x")
    r = run_qrm("--", str(f), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert not f.exists()


def test_verbose_reports(fake_home):
    home, work = fake_home
    f = work / "v.txt"
    f.write_text("x")
    r = run_qrm("-v", str(f), env={"HOME": str(home)})
    assert r.returncode == 0
    assert "removed" in r.stdout


def test_help():
    r = run_qrm("--help")
    assert r.returncode == 0
    assert "Usage:" in r.stdout


def test_missing_operand():
    r = run_qrm()
    assert r.returncode == 1
    assert "missing operand" in r.stderr


def test_force_no_args_ok():
    r = run_qrm("-f")
    assert r.returncode == 0


def test_interactive_decline(fake_home):
    home, work = fake_home
    f = work / "ask.txt"
    f.write_text("x")
    r = run_qrm("-i", str(f), env={"HOME": str(home)}, input_text="n\n")
    assert r.returncode == 0
    assert f.exists()


def test_interactive_accept(fake_home):
    home, work = fake_home
    f = work / "ask.txt"
    f.write_text("x")
    r = run_qrm("-i", str(f), env={"HOME": str(home)}, input_text="y\n")
    assert r.returncode == 0
    assert not f.exists()


def test_trash_list_compat(fake_home):
    """Verify trash-cli's trash-list can read q-rm's trashinfo files."""
    import shutil as _sh
    if not _sh.which("trash-list"):
        pytest.skip("trash-list not installed")
    home, work = fake_home
    f = work / "compat.txt"
    f.write_text("x")
    r = run_qrm(str(f), env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    out = subprocess.run(
        ["trash-list"], capture_output=True, text=True,
        env={**os.environ, "HOME": str(home)},
    )
    assert out.returncode == 0, out.stderr
    assert str(f.resolve()) in out.stdout
