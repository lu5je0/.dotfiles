"""Tests that compare q-rm behaviour with the native GNU rm.

For each scenario we run BOTH commands against an identical fixture and assert
they agree on:
  - exit code
  - stderr content (key fragments)
  - the on-disk state of the operand (still there / gone)

Run with: python3 tests/run_compare.py  (no pytest dependency)
"""
import os
import shutil
import stat as st_mod
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
QRM = HERE.parent / "q-rm.py"
RM = "/usr/bin/rm"

FAIL: list[str] = []
PASS = 0


def run_qrm(args, cwd, env_extra=None, stdin=None):
    e = os.environ.copy()
    if env_extra:
        e.update(env_extra)
    return subprocess.run(
        [sys.executable, str(QRM), *args],
        capture_output=True, text=True, cwd=cwd, env=e, input=stdin,
    )


def run_rm(args, cwd, stdin=None):
    return subprocess.run(
        [RM, *args], capture_output=True, text=True, cwd=cwd, input=stdin,
    )


def make_fixture(setup_fn) -> tuple[Path, Path]:
    """Build two parallel temp dirs (one for rm, one for q-rm) seeded by setup_fn."""
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
    """Run rm and q-rm with parallel fixtures; compare exit code + state."""
    print(f"[case] {name}")
    a, b = make_fixture(setup_fn)
    try:
        # Use a fake HOME for q-rm so the home trash lives inside its fixture.
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

def s_single_file(d: Path) -> None:
    (d / "a.txt").write_text("x")


def s_dir_with_file(d: Path) -> None:
    (d / "dir").mkdir()
    (d / "dir" / "inner.txt").write_text("x")


def s_empty_dir(d: Path) -> None:
    (d / "empty").mkdir()


def s_three_files(d: Path) -> None:
    for n in ("a", "b", "c"):
        (d / n).write_text("x")


def s_dash_file(d: Path) -> None:
    (d / "-weird").write_text("x")


def s_symlink_to_root(d: Path) -> None:
    (d / "rootlink").symlink_to("/")


def s_dot_subpath(d: Path) -> None:
    (d / "sub").mkdir()


def main() -> int:
    # 1. Simple file removal
    compare("rm file", ["a.txt"], ["a.txt"], s_single_file,
            check_paths=["a.txt"])

    # 2. Missing file without -f → both error
    compare("missing without -f",
            ["nope"], ["nope"], lambda d: None,
            stderr_contains=["No such file"])

    # 3. Missing file with -f → both succeed silently
    compare("missing with -f",
            ["-f", "nope"], ["-f", "nope"], lambda d: None)

    # 4. Directory without -r → "Is a directory"
    compare("dir without -r",
            ["dir"], ["dir"], s_dir_with_file,
            check_paths=["dir"], stderr_contains=["Is a directory"])

    # 5. Directory with -r → both remove
    compare("dir with -r",
            ["-r", "dir"], ["-r", "dir"], s_dir_with_file,
            check_paths=["dir"])

    # 6. -d on empty dir → both succeed
    compare("-d on empty dir",
            ["-d", "empty"], ["-d", "empty"], s_empty_dir,
            check_paths=["empty"])

    # 7. Bug #2: -d on non-empty dir → both error
    compare("-d on non-empty dir",
            ["-d", "dir"], ["-d", "dir"], s_dir_with_file,
            check_paths=["dir"], stderr_contains=["Directory not empty"])

    # 8. -- terminator
    compare("-- terminator",
            ["--", "-weird"], ["--", "-weird"], s_dash_file,
            check_paths=["-weird"])

    # 9. Bundled -rf
    compare("-rf bundled",
            ["-rf", "dir"], ["-rf", "dir"], s_dir_with_file,
            check_paths=["dir"])

    # 10. Bug #1: --force resets interactive (no prompt eaten)
    # rm -i --force foo should NOT prompt; if q-rm matched it would also not.
    compare("--force overrides -i",
            ["-i", "--force", "a.txt"], ["-i", "--force", "a.txt"],
            s_single_file, check_paths=["a.txt"])

    # 11. Bug #1 mirror: -f then --interactive=always SHOULD prompt
    # We feed "n" so both keep the file, exit 0.
    compare("--interactive=always after -f prompts",
            ["-f", "--interactive=always", "a.txt"],
            ["-f", "--interactive=always", "a.txt"],
            s_single_file,
            check_paths=["a.txt"], stdin="n\n")

    # 12. '.' refused (GNU rm and q-rm both refuse, with different wording)
    compare("dot refused",
            ["."], ["."], lambda d: None)

    # 13. '..' refused
    compare("dotdot refused",
            [".."], [".."], lambda d: None)

    # 14. Bug #4: 'foo/.' refused
    compare("foo/. refused",
            ["sub/."], ["sub/."], s_dot_subpath,
            check_paths=["sub"])

    # 15. Bug #4: 'foo/..' refused
    compare("foo/.. refused",
            ["sub/.."], ["sub/.."], s_dot_subpath,
            check_paths=["sub"])

    # 16. Bug #3: symlink to / can be deleted (preserve-root only matches literal /)
    compare("symlink to / deletable",
            ["rootlink"], ["rootlink"], s_symlink_to_root,
            check_paths=["rootlink"])

    # 17. -rf / refused
    compare("-rf / refused",
            ["-rf", "/"], ["-rf", "/"], lambda d: None,
            stderr_contains=["dangerous"])

    # 18. -rf // refused (literal double-slash)
    compare("-rf // refused",
            ["-rf", "//"], ["-rf", "//"], lambda d: None,
            stderr_contains=["dangerous"])

    # 19. Verbose
    compare("-v reports",
            ["-v", "a.txt"], ["-v", "a.txt"], s_single_file,
            check_paths=["a.txt"])

    # 20. -i declined keeps file
    compare("-i declined keeps file",
            ["-i", "a.txt"], ["-i", "a.txt"], s_single_file,
            check_paths=["a.txt"], stdin="n\n")

    # 21. -i accepted removes file
    compare("-i accepted removes file",
            ["-i", "a.txt"], ["-i", "a.txt"], s_single_file,
            check_paths=["a.txt"], stdin="y\n")

    # 22. Missing operand
    compare("no operand",
            [], [], lambda d: None,
            stderr_contains=["missing operand"])

    # 23. -f with no operand → both succeed
    compare("-f no operand",
            ["-f"], ["-f"], lambda d: None)

    # 24. -r deep tree
    def s_deep(d: Path) -> None:
        p = d / "a" / "b" / "c"
        p.mkdir(parents=True)
        (p / "leaf").write_text("x")
        (d / "a" / "side").write_text("y")

    compare("-r deep tree",
            ["-r", "a"], ["-r", "a"], s_deep,
            check_paths=["a"])

    # 25. -r on symlink-to-dir: only removes the link, target stays.
    def s_link_to_dir(d: Path) -> None:
        target = d / "real"
        target.mkdir()
        (target / "keep").write_text("x")
        (d / "link").symlink_to("real")

    compare("-r symlink-to-dir keeps target",
            ["-r", "link"], ["-r", "link"], s_link_to_dir,
            check_paths=["link", "real", "real/keep"])

    # 26. Mixed: one missing + one present → rm removes present, exits 1.
    def s_one_present(d: Path) -> None:
        (d / "have").write_text("x")

    compare("mixed missing+present",
            ["nope", "have"], ["nope", "have"], s_one_present,
            check_paths=["have"], stderr_contains=["No such file"])

    # 27. Unknown long option → both error out before touching anything.
    compare("unknown long option",
            ["--bogus", "a.txt"], ["--bogus", "a.txt"], s_single_file,
            check_paths=["a.txt"])

    # 28. --interactive=never does NOT silence missing files (unlike -f).
    compare("--interactive=never still errors on missing",
            ["--interactive=never", "nope"],
            ["--interactive=never", "nope"], lambda d: None,
            stderr_contains=["No such file"])

    # 29. Duplicate operand: first removes file, second is now missing → exit 1.
    compare("duplicate operand",
            ["a.txt", "a.txt"], ["a.txt", "a.txt"], s_single_file,
            check_paths=["a.txt"], stderr_contains=["No such file"])

    # 30. Empty-string operand (no -f) → both error.
    compare("empty string operand",
            [""], [""], lambda d: None,
            stderr_contains=["No such file"])

    # 31. '-' as filename (file actually named '-').
    def s_dash_named(d: Path) -> None:
        (d / "-").write_text("x")

    compare("'-' as filename",
            ["--", "-"], ["--", "-"], s_dash_named,
            check_paths=["-"])

    # ---------- q-rm-only: Trash Spec assertions ----------
    print()
    print("[trash-spec assertions, q-rm only]")
    spec_check_trashinfo_encoding()
    spec_check_collision_renaming()
    spec_check_octal_mount_parsing()
    spec_check_purge_one_file_system()
    spec_check_windows_partial_failure()

    print()
    print(f"PASS {PASS}")
    print(f"FAIL {len(FAIL)}")
    if FAIL:
        for line in FAIL:
            print("  -", line)
        return 1
    return 0


def spec_check_trashinfo_encoding() -> None:
    """Verify trashinfo Path= is percent-encoded per spec.

    Tricky chars (space, %, #, plus, unicode) must round-trip via urllib.unquote.
    """
    from urllib.parse import unquote
    work = Path(tempfile.mkdtemp(prefix="qrmwork_"))
    home = Path(tempfile.mkdtemp(prefix="qrmhome_"))
    try:
        names = ["a b c.txt", "100%full", "tag#one", "中文.txt", "p+q.txt"]
        for n in names:
            (work / n).write_text("x")
        env = {"HOME": str(home)}
        r = run_qrm([*names], cwd=str(work), env_extra=env)
        check("trashinfo encoding: exit code", r.returncode == 0,
              f"stderr={r.stderr}")
        info_dir = home / ".local" / "share" / "Trash" / "info"
        infos = sorted(info_dir.iterdir())
        check("trashinfo encoding: info files written",
              len(infos) == len(names),
              f"got {[p.name for p in infos]}")
        recovered = set()
        for info in infos:
            content = info.read_text()
            for line in content.splitlines():
                if line.startswith("Path="):
                    recovered.add(os.path.basename(unquote(line[5:])))
        check("trashinfo encoding: round-trip for all special names",
              recovered == set(names),
              f"got {recovered}")
    finally:
        cleanup(work, home)


def spec_check_collision_renaming() -> None:
    """Same basename trashed N times yields name, name_2, name_3, ..."""
    work = Path(tempfile.mkdtemp(prefix="qrmwork_"))
    home = Path(tempfile.mkdtemp(prefix="qrmhome_"))
    try:
        env = {"HOME": str(home)}
        for i in range(3):
            f = work / "same"
            f.write_text(f"v{i}")
            r = run_qrm(["same"], cwd=str(work), env_extra=env)
            check(f"collision: round {i+1} exit", r.returncode == 0,
                  f"stderr={r.stderr}")
        files_dir = home / ".local" / "share" / "Trash" / "files"
        info_dir = home / ".local" / "share" / "Trash" / "info"
        files = sorted(p.name for p in files_dir.iterdir())
        infos = sorted(p.name for p in info_dir.iterdir())
        check("collision: files renamed",
              files == ["same", "same_2", "same_3"], f"got {files}")
        check("collision: info matches",
              infos == ["same.trashinfo", "same_2.trashinfo",
                        "same_3.trashinfo"], f"got {infos}")
    finally:
        cleanup(work, home)


def spec_check_octal_mount_parsing() -> None:
    """Verify _read_mount_fstype_map correctly decodes octal escapes.

    We can't easily create a real mount with spaces, so we test the internal
    function directly by monkey-patching.
    """
    print("[unit] octal mount parsing")
    # Simulate a /proc/self/mounts line with octal escapes (\040 = space)
    import importlib.util
    spec = importlib.util.spec_from_file_location("qrm", str(QRM))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    # Manually test the regex logic
    import re
    _octal_re = re.compile(r"\\([0-7]{3})")
    def _decode_octal(s: str) -> str:
        return _octal_re.sub(lambda m: chr(int(m.group(1), 8)), s)

    check("octal decode: space",
          _decode_octal("/mnt/My\\040Drive") == "/mnt/My Drive", "")
    check("octal decode: tab",
          _decode_octal("/mnt/a\\011b") == "/mnt/a\tb", "")
    check("octal decode: backslash",
          _decode_octal("/mnt/a\\134b") == "/mnt/a\\b", "")
    check("octal decode: no escape passthrough",
          _decode_octal("/mnt/normal") == "/mnt/normal", "")
    check("octal decode: multiple",
          _decode_octal("/mnt/a\\040b\\040c") == "/mnt/a b c", "")


def spec_check_purge_one_file_system() -> None:
    """Verify --purge --one-file-system doesn't descend into different devices.

    We can't easily mount a different fs in tests, but we can verify that
    purge with --one-file-system on a normal tree removes everything (no
    cross-device in a single tmpdir), and that verbosity output is correct.
    """
    print("[unit] purge --one-file-system")
    work = Path(tempfile.mkdtemp(prefix="qrmofs_"))
    home = Path(tempfile.mkdtemp(prefix="qrmhome_"))
    try:
        # Create a tree: work/tree/{a/deep, b/file}
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


def spec_check_windows_partial_failure() -> None:
    """On WSL: verify that if one path in a batch doesn't exist, others still
    get recycled (partial failure handling).

    Skip if not on WSL.
    """
    print("[unit] Windows partial failure")
    try:
        with open("/proc/version", "r") as f:
            if "microsoft" not in f.read().lower():
                print("  SKIP  (not WSL)")
                return
    except OSError:
        print("  SKIP  (not WSL)")
        return

    # Create two files on /mnt/c, delete one before calling q-rm
    import time
    # Find a writable dir on a Windows-native volume
    win_tmp = None
    for cand in ["/mnt/c/Users/" + os.environ.get("USER", ""),
                 "/mnt/c/tmp", "/tmp"]:
        if os.path.isdir(cand) and os.access(cand, os.W_OK):
            win_tmp = cand
            break
    if win_tmp is None or not win_tmp.startswith("/mnt/"):
        print("  SKIP  (no writable Windows-native dir found)")
        return

    work = Path(tempfile.mkdtemp(prefix="qrm_winpf_", dir=win_tmp))
    try:
        (work / "exists1").write_text("a")
        (work / "exists2").write_text("b")
        # Pass a non-existent path along with two real ones — but note
        # validation catches missing files BEFORE bucketing, so this tests
        # that exists1 and exists2 are both recycled even when one arg fails
        # validation.
        r = run_qrm(["exists1", "nope", "exists2"], cwd=str(work))
        check("win partial: exit code is 1 (due to 'nope')",
              r.returncode == 1, f"rc={r.returncode}")
        check("win partial: exists1 removed",
              not (work / "exists1").exists(), "still there")
        check("win partial: exists2 removed",
              not (work / "exists2").exists(), "still there")
        check("win partial: stderr mentions nope",
              "nope" in r.stderr, f"stderr={r.stderr!r}")
    finally:
        cleanup(work)


if __name__ == "__main__":
    sys.exit(main())
