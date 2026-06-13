"""Tests for q-trash. Run with: python3 tests/run_qtrash.py"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
QTRASH = HERE.parent / "q-trash.py"
QRM = HERE.parent / "q-rm.py"

FAIL: list[str] = []
PASS = 0


def run_qtrash(*args, env_extra=None, cwd=None, stdin=None):
    e = os.environ.copy()
    if env_extra:
        e.update(env_extra)
    return subprocess.run(
        [sys.executable, str(QTRASH), *args],
        capture_output=True, text=True, env=e, cwd=cwd, input=stdin,
    )


def run_qrm(*args, env_extra=None, cwd=None):
    e = os.environ.copy()
    if env_extra:
        e.update(env_extra)
    return subprocess.run(
        [sys.executable, str(QRM), *args],
        capture_output=True, text=True, env=e, cwd=cwd,
    )


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL.append(f"{name}: {detail}")
        print(f"  FAIL  {name}: {detail}")


def cleanup(*dirs: Path) -> None:
    for d in dirs:
        shutil.rmtree(d, ignore_errors=True)


def make_env(home: Path) -> dict:
    return {"HOME": str(home)}


# ---------- list ----------

def test_list_empty():
    """list on empty trash prints 'No trashed files.'"""
    print("[case] list empty trash")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    try:
        r = run_qtrash("list", env_extra=make_env(home))
        check("list empty: exit 0", r.returncode == 0)
        check("list empty: says no files",
              "No trashed files" in r.stderr or "No trashed files" in r.stdout,
              f"stdout={r.stdout!r} stderr={r.stderr!r}")
    finally:
        cleanup(home)


def test_list_shows_trashed_file():
    """Trash a file, verify it appears in list."""
    print("[case] list shows trashed file")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        (work / "hello.txt").write_text("x")
        env = make_env(home)
        run_qrm(str(work / "hello.txt"), env_extra=env)
        r = run_qtrash("list", env_extra=env)
        check("list shows file: exit 0", r.returncode == 0)
        check("list shows file: path in output",
              "hello.txt" in r.stdout, f"stdout={r.stdout!r}")
    finally:
        cleanup(home, work)


def test_list_filter_path():
    """list with a path filter only shows files from that path."""
    print("[case] list filter by path")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    other = Path(tempfile.mkdtemp(prefix="qto_"))
    try:
        (work / "a.txt").write_text("a")
        (other / "b.txt").write_text("b")
        env = make_env(home)
        run_qrm(str(work / "a.txt"), env_extra=env)
        run_qrm(str(other / "b.txt"), env_extra=env)

        r = run_qtrash("list", str(work), env_extra=env)
        check("list filter: a.txt shown", "a.txt" in r.stdout)
        check("list filter: b.txt hidden", "b.txt" not in r.stdout)
    finally:
        cleanup(home, work, other)


# ---------- restore ----------

def test_restore_exact():
    """restore an exact path restores the file."""
    print("[case] restore exact path")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        f = work / "doc.txt"
        f.write_text("content")
        env = make_env(home)
        run_qrm(str(f), env_extra=env)
        check("restore exact: file gone after rm", not f.exists())

        r = run_qtrash("restore", str(f), env_extra=env)
        check("restore exact: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore exact: file restored", f.exists())
        check("restore exact: content intact", f.read_text() == "content")
    finally:
        cleanup(home, work)


def test_restore_latest_of_duplicates():
    """When same path trashed multiple times, restore picks the latest."""
    print("[case] restore picks latest duplicate")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        f = work / "dup.txt"
        env = make_env(home)
        f.write_text("v1")
        run_qrm(str(f), env_extra=env)
        f.write_text("v2")
        run_qrm(str(f), env_extra=env)
        f.write_text("v3")
        run_qrm(str(f), env_extra=env)

        r = run_qtrash("restore", str(f), env_extra=env)
        check("restore latest: exit 0", r.returncode == 0,
              f"stderr={r.stderr} stdout={r.stdout}")
        check("restore latest: file exists", f.exists(),
              f"stderr={r.stderr} stdout={r.stdout}")
        if f.exists():
            check("restore latest: content is v3", f.read_text() == "v3",
                  f"got {f.read_text()!r}")
    finally:
        cleanup(home, work)


def test_restore_refuses_existing():
    """restore refuses when target already exists (without --overwrite)."""
    print("[case] restore refuses existing target")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        f = work / "conflict.txt"
        f.write_text("old")
        env = make_env(home)
        run_qrm(str(f), env_extra=env)
        f.write_text("new")

        r = run_qtrash("restore", str(f), env_extra=env)
        check("restore refuses: exit 1", r.returncode == 1)
        check("restore refuses: already exists in stderr",
              "already exists" in r.stderr, f"stderr={r.stderr!r}")
        check("restore refuses: existing file untouched",
              f.read_text() == "new")
    finally:
        cleanup(home, work)


def test_restore_overwrite():
    """restore --overwrite replaces existing file."""
    print("[case] restore --overwrite")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        f = work / "ow.txt"
        f.write_text("trashed_content")
        env = make_env(home)
        run_qrm(str(f), env_extra=env)
        f.write_text("blocker")

        r = run_qtrash("restore", "--overwrite", str(f), env_extra=env)
        check("restore overwrite: exit 0", r.returncode == 0,
              f"stderr={r.stderr}")
        check("restore overwrite: content is trashed one",
              f.read_text() == "trashed_content")
    finally:
        cleanup(home, work)


def test_restore_all():
    """restore --all restores all files from a directory."""
    print("[case] restore --all")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        for name in ("x.txt", "y.txt", "z.txt"):
            (work / name).write_text(name)
            run_qrm(str(work / name), env_extra=env)

        r = run_qtrash("restore", "--all", str(work), env_extra=env)
        check("restore all: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        for name in ("x.txt", "y.txt", "z.txt"):
            check(f"restore all: {name} restored", (work / name).exists())
    finally:
        cleanup(home, work)


def test_restore_creates_parent():
    """restore creates parent directories if needed."""
    print("[case] restore creates parent dir")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        subdir = work / "deep" / "sub"
        subdir.mkdir(parents=True)
        f = subdir / "nested.txt"
        f.write_text("deep")
        run_qrm(str(f), env_extra=env)
        # Remove the parent dirs
        shutil.rmtree(work / "deep")
        check("restore parent: parent gone", not subdir.exists())

        r = run_qtrash("restore", str(f), env_extra=env)
        check("restore parent: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore parent: file exists", f.exists())
        check("restore parent: content ok", f.read_text() == "deep")
    finally:
        cleanup(home, work)


def test_restore_interactive_quit():
    """restore in interactive mode: typing 'q' quits without restoring."""
    print("[case] restore interactive quit")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "a").write_text("a")
        (work / "b").write_text("b")
        run_qrm(str(work / "a"), env_extra=env)
        run_qrm(str(work / "b"), env_extra=env)

        r = run_qtrash("restore", str(work), env_extra=env, stdin="q\n")
        check("restore quit: exit 0", r.returncode == 0)
        check("restore quit: a not restored", not (work / "a").exists())
        check("restore quit: b not restored", not (work / "b").exists())
    finally:
        cleanup(home, work)


def test_restore_interactive_select():
    """restore in interactive mode: select index."""
    print("[case] restore interactive select")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "first").write_text("1")
        (work / "second").write_text("2")
        run_qrm(str(work / "first"), env_extra=env)
        run_qrm(str(work / "second"), env_extra=env)

        # Select index 0 only
        r = run_qtrash("restore", str(work), env_extra=env, stdin="0\n")
        check("restore select: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore select: first restored", (work / "first").exists())
        check("restore select: second NOT restored",
              not (work / "second").exists())
    finally:
        cleanup(home, work)


# ---------- empty ----------

def test_empty_all():
    """empty --force removes all items."""
    print("[case] empty --force")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        for name in ("a", "b", "c"):
            (work / name).write_text(name)
            run_qrm(str(work / name), env_extra=env)

        r = run_qtrash("empty", "--force", env_extra=env)
        check("empty all: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("empty all: reports deleted",
              "Deleted 3 item" in r.stdout, f"stdout={r.stdout!r}")

        # Verify trash is empty
        r2 = run_qtrash("list", env_extra=env)
        check("empty all: list empty after",
              "No trashed files" in r2.stderr)
    finally:
        cleanup(home, work)


def test_empty_days_filter():
    """empty --days N only removes items older than N days."""
    print("[case] empty --days filter")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "recent").write_text("x")
        run_qrm(str(work / "recent"), env_extra=env)

        # File was just trashed (0 days old), --days 1 should NOT delete it
        r = run_qtrash("empty", "--force", "--days", "1", env_extra=env)
        check("empty days: exit 0", r.returncode == 0)
        check("empty days: nothing deleted (too recent)",
              "empty" in r.stdout.lower() or "Deleted 0" in r.stdout
              or "already empty" in r.stdout.lower(),
              f"stdout={r.stdout!r}")

        # Verify still in trash
        r2 = run_qtrash("list", env_extra=env)
        check("empty days: file still in trash",
              "recent" in r2.stdout, f"stdout={r2.stdout!r}")
    finally:
        cleanup(home, work)


def test_empty_confirm_no():
    """empty without --force asks confirmation; 'n' cancels."""
    print("[case] empty confirm no")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "keep").write_text("x")
        run_qrm(str(work / "keep"), env_extra=env)

        r = run_qtrash("empty", env_extra=env, stdin="n\n")
        check("empty confirm no: exit 0", r.returncode == 0)
        check("empty confirm no: cancelled",
              "Cancelled" in r.stdout, f"stdout={r.stdout!r}")

        r2 = run_qtrash("list", env_extra=env)
        check("empty confirm no: file still in trash",
              "keep" in r2.stdout)
    finally:
        cleanup(home, work)


# ---------- size ----------

def test_size_empty():
    """size on empty trash."""
    print("[case] size empty")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    try:
        r = run_qtrash("size", env_extra=make_env(home))
        check("size empty: exit 0", r.returncode == 0)
        check("size empty: says empty",
              "empty" in r.stdout.lower(), f"stdout={r.stdout!r}")
    finally:
        cleanup(home)


def test_size_nonempty():
    """size shows usage after trashing files."""
    print("[case] size non-empty")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "big").write_text("x" * 10000)
        run_qrm(str(work / "big"), env_extra=env)

        r = run_qtrash("size", env_extra=env)
        check("size nonempty: exit 0", r.returncode == 0)
        check("size nonempty: shows item count",
              "1 item" in r.stdout, f"stdout={r.stdout!r}")
        check("size nonempty: shows size",
              "KB" in r.stdout or "B" in r.stdout, f"stdout={r.stdout!r}")
    finally:
        cleanup(home, work)


# ---------- rm subcommand ----------

def test_rm_subcommand():
    """q-trash rm delegates to q-rm correctly."""
    print("[case] q-trash rm")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        (work / "via_rm.txt").write_text("hello")
        r = run_qtrash("rm", "-v", str(work / "via_rm.txt"), env_extra=env)
        check("rm sub: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("rm sub: file removed", not (work / "via_rm.txt").exists())
        check("rm sub: verbose output", "removed" in r.stdout)

        r2 = run_qtrash("list", env_extra=env)
        check("rm sub: appears in list",
              "via_rm.txt" in r2.stdout, f"stdout={r2.stdout!r}")
    finally:
        cleanup(home, work)


def test_rm_subcommand_rf():
    """q-trash rm -rf removes directory."""
    print("[case] q-trash rm -rf")
    home = Path(tempfile.mkdtemp(prefix="qth_"))
    work = Path(tempfile.mkdtemp(prefix="qtw_"))
    try:
        env = make_env(home)
        d = work / "mydir"
        d.mkdir()
        (d / "inner").write_text("x")
        r = run_qtrash("rm", "-rf", str(d), env_extra=env)
        check("rm -rf: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("rm -rf: dir removed", not d.exists())
    finally:
        cleanup(home, work)


# ---------- misc ----------

def test_help():
    """--help works."""
    print("[case] help")
    r = run_qtrash("--help")
    check("help: exit 0", r.returncode == 0)
    check("help: shows commands", "list" in r.stdout and "restore" in r.stdout)


def test_version():
    """--version works."""
    print("[case] version")
    r = run_qtrash("--version")
    check("version: exit 0", r.returncode == 0)
    check("version: shows q-trash", "q-trash" in r.stdout)


def test_unknown_command():
    """Unknown command errors."""
    print("[case] unknown command")
    r = run_qtrash("bogus")
    check("unknown cmd: exit 1", r.returncode == 1)
    check("unknown cmd: stderr message",
          "unknown command" in r.stderr, f"stderr={r.stderr!r}")


# ---------- main ----------

def main() -> int:
    test_help()
    test_version()
    test_unknown_command()
    test_list_empty()
    test_list_shows_trashed_file()
    test_list_filter_path()
    test_restore_exact()
    test_restore_latest_of_duplicates()
    test_restore_refuses_existing()
    test_restore_overwrite()
    test_restore_all()
    test_restore_creates_parent()
    test_restore_interactive_quit()
    test_restore_interactive_select()
    test_empty_all()
    test_empty_days_filter()
    test_empty_confirm_no()
    test_size_empty()
    test_size_nonempty()
    test_rm_subcommand()
    test_rm_subcommand_rf()

    print()
    print(f"PASS {PASS}")
    print(f"FAIL {len(FAIL)}")
    if FAIL:
        for line in FAIL:
            print("  -", line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
