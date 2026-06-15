"""Tests that compare q-trash rm (Rust) behaviour with native GNU rm.

For each scenario we run BOTH commands against an identical fixture and assert
they agree on exit code, stderr fragments, and on-disk state.

Run with: python3 tests/run_compare.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
QTRASH = HERE.parent / "target" / "release" / "q-trash"
RM = shutil.which("rm") or "/usr/bin/rm"

FAIL: list[str] = []
PASS = 0


def run_qrm(args, cwd, env_extra=None, stdin=None):
    e = os.environ.copy()
    if env_extra:
        e.update(env_extra)
    return subprocess.run(
        [str(QTRASH), "rm", *args],
        capture_output=True, text=True, cwd=cwd, env=e, input=stdin,
    )


def run_rm(args, cwd, stdin=None):
    return subprocess.run(
        [RM, *args], capture_output=True, text=True, cwd=cwd, input=stdin,
    )


def make_fixture(setup_fn) -> tuple[Path, Path]:
    a = Path(tempfile.mkdtemp(prefix="rm_"))
    b = Path(tempfile.mkdtemp(prefix="qrm_"))
    setup_fn(a)
    setup_fn(b)
    return a, b


def cleanup(*dirs: Path) -> None:
    for d in dirs:
        shutil.rmtree(d, ignore_errors=True)


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL.append(f"{name}: {detail}")
        print(f"  FAIL  {name}: {detail}")


def compare(name: str, args_rm, args_qrm, setup_fn, *,
            check_paths: list[str] | None = None,
            stderr_contains: list[str] | None = None,
            stdin: str | None = None,
            qrm_env: dict | None = None) -> None:
    print(f"[case] {name}")
    a, b = make_fixture(setup_fn)
    try:
        fake_home = b / ".__home__"
        fake_home.mkdir()
        env = {"HOME": str(fake_home)}
        if qrm_env:
            env.update(qrm_env)

        ra = run_rm(args_rm, cwd=str(a), stdin=stdin)
        rb = run_qrm(args_qrm, cwd=str(b), env_extra=env, stdin=stdin)

        check(f"{name}: exit code", ra.returncode == rb.returncode,
              f"rm={ra.returncode} qrm={rb.returncode}\nrm.stderr={ra.stderr}\nqrm.stderr={rb.stderr}")

        if check_paths:
            for p in check_paths:
                pa = (a / p).exists() or (a / p).is_symlink()
                pb = (b / p).exists() or (b / p).is_symlink()
                check(f"{name}: '{p}' presence agrees",
                      pa == pb, f"rm_present={pa} qrm_present={pb}")

        if stderr_contains is not None:
            for frag in stderr_contains:
                in_a = frag in ra.stderr
                in_b = frag in rb.stderr
                check(f"{name}: stderr contains '{frag}'",
                      in_a and in_b,
                      f"rm.stderr={ra.stderr!r}, qrm.stderr={rb.stderr!r}")
    finally:
        cleanup(a, b)


# ---------- scenarios ----------

def s_single_file(d): (d / "a.txt").write_text("x")
def s_dir_with_file(d): (d / "dir").mkdir(); (d / "dir" / "inner.txt").write_text("x")
def s_empty_dir(d): (d / "empty").mkdir()
def s_dash_file(d): (d / "-weird").write_text("x")
def s_symlink_to_root(d): (d / "rootlink").symlink_to("/")
def s_dot_subpath(d): (d / "sub").mkdir()


def main() -> int:
    if not QTRASH.exists():
        print(f"ERROR: Rust binary not found at {QTRASH}")
        print("Run `cargo build --release` first.")
        return 1

    compare("rm file", ["a.txt"], ["a.txt"], s_single_file, check_paths=["a.txt"])
    compare("missing without -f", ["nope"], ["nope"], lambda d: None, stderr_contains=["No such file"])
    compare("missing with -f", ["-f", "nope"], ["-f", "nope"], lambda d: None)
    compare("dir without -r", ["dir"], ["dir"], s_dir_with_file, check_paths=["dir"], stderr_contains=["Is a directory"])
    compare("dir with -r", ["-r", "dir"], ["-r", "dir"], s_dir_with_file, check_paths=["dir"])
    compare("-d on empty dir", ["-d", "empty"], ["-d", "empty"], s_empty_dir, check_paths=["empty"])
    compare("-d on non-empty dir", ["-d", "dir"], ["-d", "dir"], s_dir_with_file, check_paths=["dir"], stderr_contains=["Directory not empty"])
    compare("-- terminator", ["--", "-weird"], ["--", "-weird"], s_dash_file, check_paths=["-weird"])
    compare("-rf bundled", ["-rf", "dir"], ["-rf", "dir"], s_dir_with_file, check_paths=["dir"])
    compare("--force overrides -i", ["-i", "--force", "a.txt"], ["-i", "--force", "a.txt"], s_single_file, check_paths=["a.txt"])
    compare("--interactive=always after -f prompts", ["-f", "--interactive=always", "a.txt"], ["-f", "--interactive=always", "a.txt"], s_single_file, check_paths=["a.txt"], stdin="n\n")
    compare("dot refused", ["."], ["."], lambda d: None)
    compare("dotdot refused", [".."], [".."], lambda d: None)
    compare("foo/. refused", ["sub/."], ["sub/."], s_dot_subpath, check_paths=["sub"])
    compare("foo/.. refused", ["sub/.."], ["sub/.."], s_dot_subpath, check_paths=["sub"])
    compare("symlink to / deletable", ["rootlink"], ["rootlink"], s_symlink_to_root, check_paths=["rootlink"])
    compare("-rf / refused", ["-rf", "/"], ["-rf", "/"], lambda d: None, stderr_contains=["dangerous"])
    compare("-rf // refused", ["-rf", "//"], ["-rf", "//"], lambda d: None, stderr_contains=["dangerous"])
    compare("-v reports", ["-v", "a.txt"], ["-v", "a.txt"], s_single_file, check_paths=["a.txt"])
    compare("-i declined keeps file", ["-i", "a.txt"], ["-i", "a.txt"], s_single_file, check_paths=["a.txt"], stdin="n\n")
    compare("-i accepted removes file", ["-i", "a.txt"], ["-i", "a.txt"], s_single_file, check_paths=["a.txt"], stdin="y\n")
    compare("no operand", [], [], lambda d: None, stderr_contains=["missing operand"])
    compare("-f no operand", ["-f"], ["-f"], lambda d: None)

    def s_deep(d):
        p = d / "a" / "b" / "c"; p.mkdir(parents=True)
        (p / "leaf").write_text("x"); (d / "a" / "side").write_text("y")
    compare("-r deep tree", ["-r", "a"], ["-r", "a"], s_deep, check_paths=["a"])

    def s_link_to_dir(d):
        target = d / "real"; target.mkdir()
        (target / "keep").write_text("x"); (d / "link").symlink_to("real")
    compare("-r symlink-to-dir keeps target", ["-r", "link"], ["-r", "link"], s_link_to_dir, check_paths=["link", "real", "real/keep"])

    def s_one_present(d): (d / "have").write_text("x")
    compare("mixed missing+present", ["nope", "have"], ["nope", "have"], s_one_present, check_paths=["have"], stderr_contains=["No such file"])

    compare("unknown long option", ["--bogus", "a.txt"], ["--bogus", "a.txt"], s_single_file, check_paths=["a.txt"])
    compare("--interactive=never still errors on missing", ["--interactive=never", "nope"], ["--interactive=never", "nope"], lambda d: None, stderr_contains=["No such file"])
    compare("duplicate operand", ["a.txt", "a.txt"], ["a.txt", "a.txt"], s_single_file, check_paths=["a.txt"])
    compare("empty string operand", [""], [""], lambda d: None, stderr_contains=["No such file"])

    def s_dash_named(d): (d / "-").write_text("x")
    compare("'-' as filename", ["--", "-"], ["--", "-"], s_dash_named, check_paths=["-"])

    # ---------- purge spec ----------
    print()
    print("[purge tests]")
    spec_check_purge_one_file_system()

    print()
    print(f"PASS {PASS}")
    print(f"FAIL {len(FAIL)}")
    if FAIL:
        for line in FAIL:
            print("  -", line)
        return 1
    return 0


def spec_check_purge_one_file_system() -> None:
    print("[unit] purge --one-file-system")
    work = Path(tempfile.mkdtemp(prefix="qrmofs_"))
    home = Path(tempfile.mkdtemp(prefix="qrmhome_"))
    try:
        tree = work / "tree"
        (tree / "a").mkdir(parents=True)
        (tree / "a" / "deep").write_text("x")
        (tree / "b").mkdir()
        (tree / "b" / "file").write_text("y")

        env = {"HOME": str(home)}
        r = run_qrm(["--purge", "--one-file-system", "-rv", "tree"],
                    cwd=str(work), env_extra=env)
        check("purge --one-file-system: exit code", r.returncode == 0,
              f"stderr={r.stderr}")
        check("purge --one-file-system: tree removed",
              not (work / "tree").exists(), "tree still exists")
        check("purge --one-file-system: verbose mentions files",
              "removed" in r.stdout, f"stdout={r.stdout!r}")
    finally:
        cleanup(work, home)


if __name__ == "__main__":
    sys.exit(main())
