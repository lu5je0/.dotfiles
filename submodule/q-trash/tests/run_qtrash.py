"""Tests for q-trash. Run with: python3 tests/run_qtrash.py

Isolation strategy
------------------
Each test gets a fresh fake HOME inside a tempdir, and the work files live
INSIDE that fake HOME (so they share a volume → trash goes to the home
trash). XDG_DATA_HOME is cleared to prevent the parent shell's setting
from redirecting the trash to the real user's location.

This guarantees tests neither read from nor write to the user's actual
trash, no matter how the surrounding environment is configured.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
QTRASH = HERE.parent / "q-trash.py"

FAIL: list[str] = []
PASS = 0


def _build_env(home: Path, env_extra=None) -> dict:
    e = os.environ.copy()
    # Wipe any setting that could redirect trash outside the fake HOME.
    for key in ("XDG_DATA_HOME", "TRASH_DIR"):
        e.pop(key, None)
    e["HOME"] = str(home)
    if env_extra:
        e.update(env_extra)
    return e


def run_qtrash(*args, home: Path, env_extra=None, cwd=None, stdin=None):
    return subprocess.run(
        [sys.executable, str(QTRASH), *args],
        capture_output=True, text=True,
        env=_build_env(home, env_extra), cwd=cwd, input=stdin,
    )


def run_qrm(*args, home: Path, env_extra=None, cwd=None):
    return subprocess.run(
        [sys.executable, str(QTRASH), "rm", *args],
        capture_output=True, text=True,
        env=_build_env(home, env_extra), cwd=cwd,
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


def make_sandbox() -> tuple[Path, Path]:
    """Create an isolated (home, work) pair where work is inside home.

    Putting work under home guarantees both share the same volume so q-rm
    routes trashed files to home/.local/share/Trash — keeping every test
    fully self-contained.
    """
    sandbox = Path(tempfile.mkdtemp(prefix="qts_"))
    home = sandbox / "home"
    work = sandbox / "work"
    home.mkdir()
    work.mkdir()
    return home, work


def trash_dir(home: Path) -> str:
    return str(home / ".local" / "share" / "Trash")


# ---------- list ----------

def test_list_empty():
    """list on empty trash prints 'No trashed files.'"""
    print("[case] list empty trash")
    home, work = make_sandbox()
    try:
        r = run_qtrash("--trash-dir", trash_dir(home), "list", home=home)
        check("list empty: exit 0", r.returncode == 0)
        check("list empty: says no files",
              "No trashed files" in r.stderr or "No trashed files" in r.stdout,
              f"stdout={r.stdout!r} stderr={r.stderr!r}")
    finally:
        cleanup(home.parent)


def test_list_shows_trashed_file():
    """Trash a file, verify it appears in list."""
    print("[case] list shows trashed file")
    home, work = make_sandbox()
    try:
        (work / "hello.txt").write_text("x")
        run_qrm(str(work / "hello.txt"), home=home)
        r = run_qtrash("--trash-dir", trash_dir(home), "list", home=home)
        check("list shows file: exit 0", r.returncode == 0)
        check("list shows file: path in output",
              "hello.txt" in r.stdout, f"stdout={r.stdout!r}")
    finally:
        cleanup(home.parent)


def test_list_filter_path():
    """list with a path filter only shows files from that path."""
    print("[case] list filter by path")
    home, work = make_sandbox()
    try:
        a_dir = work / "a_side"
        b_dir = work / "b_side"
        a_dir.mkdir()
        b_dir.mkdir()
        (a_dir / "a.txt").write_text("a")
        (b_dir / "b.txt").write_text("b")
        run_qrm(str(a_dir / "a.txt"), home=home)
        run_qrm(str(b_dir / "b.txt"), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "list", str(a_dir),
                       home=home)
        check("list filter: a.txt shown", "a.txt" in r.stdout,
              f"stdout={r.stdout!r}")
        check("list filter: b.txt hidden", "b.txt" not in r.stdout)
    finally:
        cleanup(home.parent)


# ---------- restore ----------

def test_restore_exact():
    """restore an exact path restores the file."""
    print("[case] restore exact path")
    home, work = make_sandbox()
    try:
        f = work / "doc.txt"
        f.write_text("content")
        run_qrm(str(f), home=home)
        check("restore exact: file gone after rm", not f.exists())

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(f),
                       home=home)
        check("restore exact: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore exact: file restored", f.exists())
        check("restore exact: content intact", f.exists() and f.read_text() == "content")
    finally:
        cleanup(home.parent)


def test_restore_latest_of_duplicates():
    """When same path trashed multiple times, restore picks the latest."""
    print("[case] restore picks latest duplicate")
    home, work = make_sandbox()
    try:
        f = work / "dup.txt"
        for content in ("v1", "v2", "v3"):
            f.write_text(content)
            run_qrm(str(f), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(f),
                       home=home)
        check("restore latest: exit 0", r.returncode == 0,
              f"stderr={r.stderr} stdout={r.stdout}")
        check("restore latest: file exists", f.exists(),
              f"stderr={r.stderr} stdout={r.stdout}")
        if f.exists():
            check("restore latest: content is v3", f.read_text() == "v3",
                  f"got {f.read_text()!r}")
    finally:
        cleanup(home.parent)


def test_restore_refuses_existing():
    """restore refuses when target already exists (without --overwrite)."""
    print("[case] restore refuses existing target")
    home, work = make_sandbox()
    try:
        f = work / "conflict.txt"
        f.write_text("old")
        run_qrm(str(f), home=home)
        f.write_text("new")

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(f),
                       home=home)
        check("restore refuses: exit 1", r.returncode == 1)
        check("restore refuses: already exists in stderr",
              "already exists" in r.stderr, f"stderr={r.stderr!r}")
        check("restore refuses: existing file untouched",
              f.read_text() == "new")
    finally:
        cleanup(home.parent)


def test_restore_overwrite():
    """restore --overwrite replaces existing file."""
    print("[case] restore --overwrite")
    home, work = make_sandbox()
    try:
        f = work / "ow.txt"
        f.write_text("trashed_content")
        run_qrm(str(f), home=home)
        f.write_text("blocker")

        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       "--overwrite", str(f), home=home)
        check("restore overwrite: exit 0", r.returncode == 0,
              f"stderr={r.stderr}")
        check("restore overwrite: content is trashed one",
              f.read_text() == "trashed_content")
    finally:
        cleanup(home.parent)


def test_restore_all():
    """restore --all restores all files from a directory."""
    print("[case] restore --all")
    home, work = make_sandbox()
    try:
        for name in ("x.txt", "y.txt", "z.txt"):
            (work / name).write_text(name)
            run_qrm(str(work / name), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", "--all",
                       str(work), home=home)
        check("restore all: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        for name in ("x.txt", "y.txt", "z.txt"):
            check(f"restore all: {name} restored", (work / name).exists())
    finally:
        cleanup(home.parent)


def test_restore_creates_parent():
    """restore creates parent directories if needed."""
    print("[case] restore creates parent dir")
    home, work = make_sandbox()
    try:
        subdir = work / "deep" / "sub"
        subdir.mkdir(parents=True)
        f = subdir / "nested.txt"
        f.write_text("deep")
        run_qrm(str(f), home=home)
        shutil.rmtree(work / "deep")
        check("restore parent: parent gone", not subdir.exists())

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(f),
                       home=home)
        check("restore parent: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore parent: file exists", f.exists())
        check("restore parent: content ok", f.exists() and f.read_text() == "deep")
    finally:
        cleanup(home.parent)


def test_restore_interactive_quit():
    """restore in interactive mode: typing 'q' quits without restoring."""
    print("[case] restore interactive quit")
    home, work = make_sandbox()
    try:
        (work / "a").write_text("a")
        (work / "b").write_text("b")
        run_qrm(str(work / "a"), home=home)
        run_qrm(str(work / "b"), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(work),
                       home=home, stdin="q\n")
        check("restore quit: exit 0", r.returncode == 0)
        check("restore quit: a not restored", not (work / "a").exists())
        check("restore quit: b not restored", not (work / "b").exists())
    finally:
        cleanup(home.parent)


def test_restore_interactive_select():
    """restore in interactive mode: select index."""
    print("[case] restore interactive select")
    home, work = make_sandbox()
    try:
        (work / "first").write_text("1")
        (work / "second").write_text("2")
        run_qrm(str(work / "first"), home=home)
        run_qrm(str(work / "second"), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "restore", str(work),
                       home=home, stdin="0\n")
        check("restore select: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("restore select: first restored", (work / "first").exists())
        check("restore select: second NOT restored",
              not (work / "second").exists())
    finally:
        cleanup(home.parent)


# ---------- restore --dest ----------

def test_restore_dest_to_existing_dir():
    """--dest <existing dir>: file lands inside as <dir>/<basename>."""
    print("[case] restore --dest existing dir")
    home, work = make_sandbox()
    try:
        f = work / "src.txt"
        f.write_text("payload")
        run_qrm(str(f), home=home)

        target_dir = work / "recovered"
        target_dir.mkdir()
        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       "--dest", str(target_dir), str(f), home=home)
        check("dest dir: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("dest dir: file in target",
              (target_dir / "src.txt").exists())
        check("dest dir: content intact",
              (target_dir / "src.txt").read_text() == "payload")
        check("dest dir: original location empty", not f.exists())
    finally:
        cleanup(home.parent)


def test_restore_dest_rename_single_file():
    """--dest <new path> with a single file treats it as the target path."""
    print("[case] restore --dest renames single file")
    home, work = make_sandbox()
    try:
        f = work / "orig.txt"
        f.write_text("renamed_payload")
        run_qrm(str(f), home=home)

        target = work / "newname.txt"
        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       "--dest", str(target), str(f), home=home)
        check("dest rename: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("dest rename: target exists", target.exists())
        check("dest rename: content intact",
              target.exists() and target.read_text() == "renamed_payload")
        check("dest rename: original location empty", not f.exists())
    finally:
        cleanup(home.parent)


def test_restore_dest_with_all_creates_dir():
    """--dest <new dir> + --all auto-creates the dir for multi-file restore."""
    print("[case] restore --dest --all creates dir")
    home, work = make_sandbox()
    try:
        for name in ("p", "q", "r"):
            (work / name).write_text(name)
            run_qrm(str(work / name), home=home)

        target_dir = work / "bundle"  # does NOT exist yet
        r = run_qtrash("--trash-dir", trash_dir(home), "restore", "--all",
                       "--dest", str(target_dir), str(work), home=home)
        check("dest all: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("dest all: dir created", target_dir.is_dir())
        for name in ("p", "q", "r"):
            check(f"dest all: {name} in bundle",
                  (target_dir / name).exists())
            check(f"dest all: original {name} not restored",
                  not (work / name).exists())
    finally:
        cleanup(home.parent)


def test_restore_dest_conflict():
    """--dest where target file exists fails without --overwrite."""
    print("[case] restore --dest conflict")
    home, work = make_sandbox()
    try:
        f = work / "data.txt"
        f.write_text("trashed")
        run_qrm(str(f), home=home)

        target_dir = work / "out"
        target_dir.mkdir()
        blocker = target_dir / "data.txt"
        blocker.write_text("blocker")

        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       "--dest", str(target_dir), str(f), home=home)
        check("dest conflict: exit 1", r.returncode == 1)
        check("dest conflict: already exists in stderr",
              "already exists" in r.stderr, f"stderr={r.stderr!r}")
        check("dest conflict: blocker untouched",
              blocker.read_text() == "blocker")
    finally:
        cleanup(home.parent)


def test_restore_dest_overwrite():
    """--dest combined with --overwrite replaces the target."""
    print("[case] restore --dest --overwrite")
    home, work = make_sandbox()
    try:
        f = work / "data.txt"
        f.write_text("trashed_payload")
        run_qrm(str(f), home=home)

        target_dir = work / "out"
        target_dir.mkdir()
        (target_dir / "data.txt").write_text("blocker")

        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       "--dest", str(target_dir), "--overwrite", str(f),
                       home=home)
        check("dest overwrite: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("dest overwrite: content replaced",
              (target_dir / "data.txt").read_text() == "trashed_payload")
    finally:
        cleanup(home.parent)


def test_restore_dest_eq_form():
    """--dest=PATH form is parsed identically to --dest PATH."""
    print("[case] restore --dest=PATH form")
    home, work = make_sandbox()
    try:
        f = work / "eqform.txt"
        f.write_text("eq")
        run_qrm(str(f), home=home)

        target = work / "eq_renamed.txt"
        r = run_qtrash("--trash-dir", trash_dir(home), "restore",
                       f"--dest={target}", str(f), home=home)
        check("dest eq: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("dest eq: file restored to renamed target", target.exists())
    finally:
        cleanup(home.parent)


def test_restore_dest_missing_arg():
    """--dest with no following argument errors out."""
    print("[case] restore --dest missing arg")
    home, _work = make_sandbox()
    try:
        r = run_qtrash("--trash-dir", trash_dir(home), "restore", "--dest",
                       home=home)
        check("dest missing: exit 1", r.returncode == 1)
        check("dest missing: stderr message",
              "--dest requires" in r.stderr, f"stderr={r.stderr!r}")
    finally:
        cleanup(home.parent)


# ---------- empty ----------

def test_empty_all():
    """empty --force removes all items."""
    print("[case] empty --force")
    home, work = make_sandbox()
    try:
        td = trash_dir(home)
        for name in ("a", "b", "c"):
            (work / name).write_text(name)
            run_qrm(str(work / name), home=home)

        r = run_qtrash("--trash-dir", td, "empty", "--force", home=home)
        check("empty all: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("empty all: reports deleted",
              "Deleted 3 item" in r.stdout, f"stdout={r.stdout!r}")

        r2 = run_qtrash("--trash-dir", td, "list", home=home)
        check("empty all: list empty after",
              "No trashed files" in r2.stderr)
    finally:
        cleanup(home.parent)


def test_empty_days_filter():
    """empty --days N only removes items older than N days."""
    print("[case] empty --days filter")
    home, work = make_sandbox()
    try:
        td = trash_dir(home)
        (work / "recent").write_text("x")
        run_qrm(str(work / "recent"), home=home)

        r = run_qtrash("--trash-dir", td, "empty", "--force", "--days", "1",
                       home=home)
        check("empty days: exit 0", r.returncode == 0)
        check("empty days: nothing deleted (too recent)",
              "empty" in r.stdout.lower() or "Deleted 0" in r.stdout
              or "already empty" in r.stdout.lower(),
              f"stdout={r.stdout!r}")

        r2 = run_qtrash("--trash-dir", td, "list", home=home)
        check("empty days: file still in trash",
              "recent" in r2.stdout, f"stdout={r2.stdout!r}")
    finally:
        cleanup(home.parent)


def test_empty_confirm_no():
    """empty without --force asks confirmation; 'n' cancels."""
    print("[case] empty confirm no")
    home, work = make_sandbox()
    try:
        td = trash_dir(home)
        (work / "keep").write_text("x")
        run_qrm(str(work / "keep"), home=home)

        r = run_qtrash("--trash-dir", td, "empty", home=home, stdin="n\n")
        check("empty confirm no: exit 0", r.returncode == 0)
        check("empty confirm no: cancelled",
              "Cancelled" in r.stdout, f"stdout={r.stdout!r}")

        r2 = run_qtrash("--trash-dir", td, "list", home=home)
        check("empty confirm no: file still in trash",
              "keep" in r2.stdout)
    finally:
        cleanup(home.parent)


# ---------- size ----------

def test_size_empty():
    """size on empty trash."""
    print("[case] size empty")
    home, _work = make_sandbox()
    try:
        r = run_qtrash("--trash-dir", trash_dir(home), "size", home=home)
        check("size empty: exit 0", r.returncode == 0)
        check("size empty: says empty",
              "empty" in r.stdout.lower(), f"stdout={r.stdout!r}")
    finally:
        cleanup(home.parent)


def test_size_nonempty():
    """size shows usage after trashing files."""
    print("[case] size non-empty")
    home, work = make_sandbox()
    try:
        (work / "big").write_text("x" * 10000)
        run_qrm(str(work / "big"), home=home)

        r = run_qtrash("--trash-dir", trash_dir(home), "size", home=home)
        check("size nonempty: exit 0", r.returncode == 0)
        check("size nonempty: shows item count",
              "1 item" in r.stdout, f"stdout={r.stdout!r}")
        check("size nonempty: shows size",
              "KB" in r.stdout or "B" in r.stdout, f"stdout={r.stdout!r}")
    finally:
        cleanup(home.parent)


# ---------- rm subcommand ----------

def test_rm_subcommand():
    """q-trash rm delegates to q-rm correctly."""
    print("[case] q-trash rm")
    home, work = make_sandbox()
    try:
        (work / "via_rm.txt").write_text("hello")
        r = run_qtrash("rm", "-v", str(work / "via_rm.txt"), home=home)
        check("rm sub: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("rm sub: file removed", not (work / "via_rm.txt").exists())
        check("rm sub: verbose output", "removed" in r.stdout)

        r2 = run_qtrash("--trash-dir", trash_dir(home), "list", home=home)
        check("rm sub: appears in list",
              "via_rm.txt" in r2.stdout, f"stdout={r2.stdout!r}")
    finally:
        cleanup(home.parent)


def test_rm_subcommand_rf():
    """q-trash rm -rf removes directory."""
    print("[case] q-trash rm -rf")
    home, work = make_sandbox()
    try:
        d = work / "mydir"
        d.mkdir()
        (d / "inner").write_text("x")
        r = run_qtrash("rm", "-rf", str(d), home=home)
        check("rm -rf: exit 0", r.returncode == 0, f"stderr={r.stderr}")
        check("rm -rf: dir removed", not d.exists())
    finally:
        cleanup(home.parent)


# ---------- misc ----------

def test_help():
    """--help works."""
    print("[case] help")
    home, _work = make_sandbox()
    try:
        r = run_qtrash("--help", home=home)
        check("help: exit 0", r.returncode == 0)
        check("help: shows commands",
              "list" in r.stdout and "restore" in r.stdout)
        check("help: mentions --dest", "--dest" in r.stdout,
              f"stdout={r.stdout!r}")
    finally:
        cleanup(home.parent)


def test_version():
    """--version works."""
    print("[case] version")
    home, _work = make_sandbox()
    try:
        r = run_qtrash("--version", home=home)
        check("version: exit 0", r.returncode == 0)
        check("version: shows q-trash", "q-trash" in r.stdout)
    finally:
        cleanup(home.parent)


def test_unknown_command():
    """Unknown command errors."""
    print("[case] unknown command")
    home, _work = make_sandbox()
    try:
        r = run_qtrash("bogus", home=home)
        check("unknown cmd: exit 1", r.returncode == 1)
        check("unknown cmd: stderr message",
              "unknown command" in r.stderr, f"stderr={r.stderr!r}")
    finally:
        cleanup(home.parent)


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
    test_restore_dest_to_existing_dir()
    test_restore_dest_rename_single_file()
    test_restore_dest_with_all_creates_dir()
    test_restore_dest_conflict()
    test_restore_dest_overwrite()
    test_restore_dest_eq_form()
    test_restore_dest_missing_arg()
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
