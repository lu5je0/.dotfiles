#!/usr/bin/env python3
"""q-rm — rm-compatible CLI that moves files to a freedesktop.org trash.

Strict Trash Spec 1.0 implementation. Same volume only — no cross-volume copy.
Compatible with trash-cli (`trash-list`, `trash-restore --trash-dir=...`).
"""
from __future__ import annotations

import errno
import functools
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime
from typing import List, Optional, Tuple
from urllib.parse import quote

VERSION = "0.1.0"
PROG = "q-rm"

HELP_TEXT = f"""\
Usage: {PROG} [OPTION]... [FILE]...
Move FILEs to the freedesktop.org trash (rm-compatible).

  -f, --force           ignore nonexistent files and arguments, never prompt
  -i                    prompt before every removal
  -I                    prompt once before removing more than three files,
                          or when removing recursively
      --interactive[=WHEN]  prompt according to WHEN: never, once (-I), always (-i)
  -r, -R, --recursive   remove directories and their contents recursively
  -d, --dir             remove empty directories
  -v, --verbose         explain what is being done
      --preserve-root   do not remove '/' (default)
      --no-preserve-root  do not treat '/' specially
      --one-file-system  when recursive, skip directories on different filesystems
      --purge           bypass trash, delete permanently (q-rm extension)
      --help            display this help and exit
      --version         output version information and exit

Trash location:
  Linux           freedesktop.org Trash Spec 1.0 (same volume only)
                    home volume → $XDG_DATA_HOME/Trash
                    other volume → $top/.Trash/$UID or $top/.Trash-$UID
  WSL             paths on Windows-native drives (drvfs/9p/virtiofs, e.g.
                    /mnt/c/...) go to the Windows Recycle Bin via PowerShell.
                    Linux-side paths use the Linux Trash Spec above.
  macOS           uses the system `trash` command.

Cross-volume moves are refused on Linux; use --purge to delete permanently.
"""


# ---------- argv parsing ----------

class Args:
    __slots__ = (
        "force", "interactive", "recursive", "dir_only", "verbose",
        "preserve_root", "one_file_system", "purge", "files",
    )

    def __init__(self) -> None:
        self.force = False
        self.interactive = "never"  # never | once | always
        self.recursive = False
        self.dir_only = False
        self.verbose = False
        self.preserve_root = True
        self.one_file_system = False
        self.purge = False
        self.files: List[str] = []


def die(msg: str, code: int = 1) -> None:
    print(f"{PROG}: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_argv(argv: List[str]) -> Args:
    a = Args()

    i = 0
    end_of_opts = False
    while i < len(argv):
        s = argv[i]
        i += 1
        if end_of_opts or s == "" or not s.startswith("-") or s == "-":
            a.files.append(s)
            continue
        if s == "--":
            end_of_opts = True
            continue
        if s.startswith("--"):
            name, _, val = s[2:].partition("=")
            has_val = "=" in s
            if name == "help":
                sys.stdout.write(HELP_TEXT)
                sys.exit(0)
            elif name == "version":
                print(f"{PROG} {VERSION}")
                sys.exit(0)
            elif name == "force":
                a.force = True
                a.interactive = "never"
            elif name == "recursive":
                a.recursive = True
            elif name == "dir":
                a.dir_only = True
            elif name == "verbose":
                a.verbose = True
            elif name == "preserve-root":
                a.preserve_root = True
            elif name == "no-preserve-root":
                a.preserve_root = False
            elif name == "one-file-system":
                a.one_file_system = True
            elif name == "purge":
                a.purge = True
            elif name == "interactive":
                if not has_val or val in ("always", "yes"):
                    a.interactive = "always"
                    a.force = False
                elif val == "once":
                    a.interactive = "once"
                    a.force = False
                elif val in ("never", "no", "none"):
                    a.interactive = "never"
                else:
                    die(f"invalid argument '{val}' for '--interactive'")
            else:
                die(f"unrecognized option '--{name}'")
            continue
        # short options, possibly bundled
        for ch in s[1:]:
            if ch == "f":
                a.force = True
                a.interactive = "never"
            elif ch == "i":
                a.interactive = "always"
                a.force = False
            elif ch == "I":
                a.interactive = "once"
                a.force = False
            elif ch in ("r", "R"):
                a.recursive = True
            elif ch == "d":
                a.dir_only = True
            elif ch == "v":
                a.verbose = True
            else:
                die(f"invalid option -- '{ch}'")
    return a


# ---------- volume/mount detection ----------

def volume_of(path: str) -> str:
    """Return the mount point of the volume the path lives on.

    Looks at the parent directory (so a symlink's own volume is reported,
    not its target's). Path must exist (or its parent must).
    """
    abs_path = os.path.abspath(path)
    parent = os.path.dirname(abs_path) or "/"
    parent = os.path.realpath(parent)
    try:
        dev = os.stat(parent).st_dev
    except OSError:
        return parent
    cur = parent
    while True:
        up = os.path.dirname(cur)
        if up == cur:
            return cur
        try:
            if os.stat(up).st_dev != dev:
                return cur
        except OSError:
            return cur
        cur = up


# ---------- platform-specific recycle bin ----------

_IS_WSL: Optional[bool] = None
_IS_MACOS: bool = sys.platform == "darwin"
_WIN_FSTYPES = {"drvfs", "9p", "virtiofs"}


def is_wsl() -> bool:
    global _IS_WSL
    if _IS_WSL is None:
        _IS_WSL = False
        if sys.platform == "linux":
            try:
                with open("/proc/version", "r", encoding="utf-8",
                          errors="replace") as f:
                    _IS_WSL = "microsoft" in f.read().lower()
            except OSError:
                pass
    return _IS_WSL


@functools.cache
def _read_mount_fstype_map() -> dict[str, str]:
    """Parse /proc/self/mounts → {mountpoint: fstype}."""
    import re
    _octal_re = re.compile(r"\\([0-7]{3})")

    def _decode_octal(s: str) -> str:
        return _octal_re.sub(lambda m: chr(int(m.group(1), 8)), s)

    out: dict[str, str] = {}
    try:
        with open("/proc/self/mounts", "r", encoding="utf-8",
                  errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3:
                    mp = _decode_octal(parts[1])
                    out[mp] = parts[2]
    except OSError:
        pass
    return out


def fstype_of(mount_point: str) -> str:
    return _read_mount_fstype_map().get(mount_point, "")


def is_windows_native_path(abs_path: str) -> bool:
    if not is_wsl():
        return False
    vol = volume_of(abs_path)
    return fstype_of(vol) in _WIN_FSTYPES


def to_windows_path(abs_path: str) -> Optional[str]:
    try:
        r = subprocess.run(
            ["wslpath", "-w", abs_path],
            capture_output=True, text=True, check=True,
        )
        return r.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


_PS_FALLBACKS = (
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
)


def find_powershell() -> Optional[str]:
    p = shutil.which("powershell.exe")
    if p:
        return p
    for cand in _PS_FALLBACKS:
        if os.path.exists(cand):
            return cand
    return None


def delete_via_windows_recycle(paths: List[str]) -> None:
    """Send paths to Windows Recycle Bin via PowerShell.

    Batched: one PowerShell invocation for all paths to amortize startup cost.
    Raises RuntimeError on failure.
    """
    ps = find_powershell()
    if not ps:
        raise RuntimeError(
            "powershell.exe not found; cannot use Windows Recycle Bin"
        )
    win_paths: List[str] = []
    for p in paths:
        wp = to_windows_path(os.path.abspath(p))
        if wp is None:
            raise RuntimeError(f"wslpath failed for '{p}'")
        win_paths.append(wp)

    # Build a PowerShell script that recycles each path, picking File vs Dir.
    ps_lines = [
        "$failed=@()",
        "Add-Type -AssemblyName Microsoft.VisualBasic",
        "$paths=@(",
    ]
    for wp in win_paths:
        escaped = wp.replace("'", "''")
        ps_lines.append(f"  '{escaped}',")
    if ps_lines[-1].endswith(","):
        ps_lines[-1] = ps_lines[-1].rstrip(",")
    ps_lines.append(")")
    ps_lines.append(
        "foreach ($p in $paths) {"
        " try {"
        "  if (Test-Path -LiteralPath $p -PathType Container) {"
        "   [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory("
        "$p,'OnlyErrorDialogs','SendToRecycleBin')"
        "  } else {"
        "   [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
        "$p,'OnlyErrorDialogs','SendToRecycleBin')"
        "  }"
        " } catch { $failed += \"${p}: $($_.Exception.Message)\" }"
        "}"
        " if ($failed.Count -gt 0) {"
        " $failed | ForEach-Object { [Console]::Error.WriteLine($_) };"
        " exit 1 }"
    )
    script = "\n".join(ps_lines)
    r = subprocess.run(
        [ps, "-NoProfile", "-NonInteractive",
         "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip().splitlines()
        last = msg[-1] if msg else f"exit {r.returncode}"
        raise RuntimeError(f"Windows Recycle Bin failed: {last}")


def delete_via_macos_trash(paths: List[str]) -> None:
    if not shutil.which("trash"):
        raise RuntimeError(
            "'trash' command not found; install one (e.g. `brew install trash`) "
            "or use --purge"
        )
    r = subprocess.run(
        ["trash", *paths],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip().splitlines()
        last = msg[-1] if msg else f"exit {r.returncode}"
        raise RuntimeError(f"macOS trash failed: {last}")


def home_trash_dir() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(base, "Trash")


def is_safe_top_trash(top_trash: str) -> bool:
    """$top/.Trash must be a real dir (not symlink) with sticky bit."""
    if os.path.islink(top_trash):
        return False
    try:
        st = os.stat(top_trash)
    except OSError:
        return False
    if not stat.S_ISDIR(st.st_mode):
        return False
    if not (st.st_mode & stat.S_ISVTX):
        return False
    return True


def pick_trash_dir(file_path: str) -> Tuple[str, str, str]:
    """Return (trash_dir, volume_root, path_style).

    path_style: "absolute" (home trash) or "relative" (volume trash).
    Raises RuntimeError if no usable trash dir on the file's volume.
    """
    file_vol = volume_of(file_path)
    home = os.path.expanduser("~")
    home_vol = volume_of(home) if os.path.exists(home) else None

    if home_vol is not None and file_vol == home_vol:
        d = home_trash_dir()
        return d, home_vol, "absolute"

    uid = os.getuid()
    top_trash = os.path.join(file_vol, ".Trash")
    if is_safe_top_trash(top_trash):
        d = os.path.join(top_trash, str(uid))
        return d, file_vol, "relative"

    d = os.path.join(file_vol, f".Trash-{uid}")
    return d, file_vol, "relative"


def ensure_trash_dirs(trash_dir: str) -> None:
    files_dir = os.path.join(trash_dir, "files")
    info_dir = os.path.join(trash_dir, "info")
    for d in (trash_dir, files_dir, info_dir):
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
        except OSError as e:
            raise RuntimeError(f"cannot create '{d}': {e.strerror}") from e


# ---------- trash move ----------

def encode_path(p: str) -> str:
    # spec: percent-encode like RFC 2396; keep '/'
    return quote(p, safe="/")


def now_local_iso() -> str:
    # Trash Spec: ISO 8601 local time, no timezone offset.
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def reserve_info_file(info_dir: str, base_name: str) -> Tuple[str, str]:
    """Atomically reserve info/<name>.trashinfo. Return (name, info_path)."""
    n = 1
    while True:
        name = base_name if n == 1 else f"{base_name}_{n}"
        info_path = os.path.join(info_dir, name + ".trashinfo")
        try:
            fd = os.open(info_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(fd)
            return name, info_path
        except FileExistsError:
            n += 1
            if n > 10000:
                raise RuntimeError(
                    f"too many name collisions in {info_dir}"
                )


def write_info(info_path: str, original_path: str, path_style: str,
               volume_root: str) -> None:
    if path_style == "absolute":
        rel = os.path.abspath(original_path)
    else:
        abs_path = os.path.abspath(original_path)
        if abs_path == volume_root:
            rel = ""
        elif abs_path.startswith(volume_root.rstrip("/") + "/"):
            rel = abs_path[len(volume_root.rstrip("/")) + 1:]
        else:
            rel = abs_path  # fallback, shouldn't happen
    body = (
        "[Trash Info]\n"
        f"Path={encode_path(rel)}\n"
        f"DeletionDate={now_local_iso()}\n"
    )
    with open(info_path, "w", encoding="utf-8") as f:
        f.write(body)


def trash_one(path: str) -> None:
    """Move a single path into the appropriate trash. Same-volume only."""
    abs_path = os.path.abspath(path)
    trash_dir, volume_root, path_style = pick_trash_dir(abs_path)

    try:
        ensure_trash_dirs(trash_dir)
    except RuntimeError as e:
        raise RuntimeError(
            f"cannot use trash dir for '{path}': {e}. "
            f"Use --purge to delete permanently."
        ) from e

    files_dir = os.path.join(trash_dir, "files")
    info_dir = os.path.join(trash_dir, "info")
    base_name = os.path.basename(abs_path.rstrip("/")) or "_"

    name, info_path = reserve_info_file(info_dir, base_name)
    dest = os.path.join(files_dir, name)
    try:
        write_info(info_path, abs_path, path_style, volume_root)
        try:
            os.rename(abs_path, dest)
        except OSError as e:
            if e.errno == errno.EXDEV:
                os.unlink(info_path)
                raise RuntimeError(
                    f"'{path}' lives on a different volume from its trash dir "
                    f"('{trash_dir}'). q-rm refuses cross-volume moves; "
                    f"use --purge to delete permanently."
                ) from e
            os.unlink(info_path)
            raise RuntimeError(f"cannot move '{path}': {e.strerror}") from e
    except Exception:
        # info_path may be cleaned up already; ignore double-unlink
        try:
            os.unlink(info_path)
        except OSError:
            pass
        raise


# ---------- rm semantics ----------

def is_dot_or_dotdot(path: str) -> bool:
    """Return True if path's final component (textually) is '.' or '..'.

    Matches GNU rm: rejects 'foo/.', 'foo/..', './', '../', '.', '..'.
    Does not resolve symlinks.
    """
    p = path
    while len(p) > 1 and p.endswith("/"):
        p = p[:-1]
    base = p.rsplit("/", 1)[-1]
    return base in (".", "..")


def is_root_path(path: str) -> bool:
    """Match GNU rm: refuse '/' or '//' as a literal absolute path.

    Does not follow symlinks; a symlink whose target is '/' is fine to delete.
    """
    p = os.path.normpath(os.path.abspath(path))
    return p == "/" or p == "//"


def prompt(msg: str) -> bool:
    sys.stderr.write(f"{PROG}: {msg}")
    sys.stderr.flush()
    try:
        line = sys.stdin.readline()
    except KeyboardInterrupt:
        return False
    if not line:
        return False
    return line.strip().lower().startswith("y")


def purge_one(path: str, verbose: bool, one_fs: bool) -> None:
    if os.path.islink(path) or not os.path.isdir(path):
        os.unlink(path)
        if verbose:
            print(f"removed '{path}'")
        return
    if one_fs:
        top_dev = os.lstat(path).st_dev
        for root, dirs, files in os.walk(path, topdown=True):
            dirs[:] = [
                d for d in dirs
                if os.lstat(os.path.join(root, d)).st_dev == top_dev
            ]
            for name in files:
                p = os.path.join(root, name)
                try:
                    os.unlink(p)
                    if verbose:
                        print(f"removed '{p}'")
                except OSError:
                    pass
        for root, dirs, _files in os.walk(path, topdown=False):
            for name in dirs:
                p = os.path.join(root, name)
                try:
                    if os.lstat(p).st_dev != top_dev:
                        continue
                    os.rmdir(p)
                    if verbose:
                        print(f"removed directory '{p}'")
                except OSError:
                    pass
        os.rmdir(path)
    else:
        shutil.rmtree(path)
    if verbose:
        print(f"removed directory '{path}'")


def validate_one(path: str, args: Args) -> Tuple[bool, bool]:
    """Validate a single path against rm semantics.

    Returns (ok_to_continue, should_delete):
      ok_to_continue: True if no error to flag; False if this path failed.
      should_delete: True if the path should be deleted; False to skip silently
                     (e.g., declined by -i prompt, or -f on missing file).
    """
    if path == "":
        if args.force:
            return True, False
        print(f"{PROG}: cannot remove '': No such file or directory",
              file=sys.stderr)
        return False, False

    if is_dot_or_dotdot(path):
        print(
            f"{PROG}: refusing to remove '.' or '..' directory: skipping '{path}'",
            file=sys.stderr,
        )
        return False, False

    if args.preserve_root and is_root_path(path):
        print(
            f"{PROG}: it is dangerous to operate recursively on '/'\n"
            f"{PROG}: use --no-preserve-root to override this failsafe",
            file=sys.stderr,
        )
        return False, False

    try:
        st = os.lstat(path)
    except FileNotFoundError:
        if args.force:
            return True, False
        print(f"{PROG}: cannot remove '{path}': No such file or directory",
              file=sys.stderr)
        return False, False
    except OSError as e:
        print(f"{PROG}: cannot stat '{path}': {e.strerror}", file=sys.stderr)
        return False, False

    is_dir = stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode)
    if is_dir and not (args.recursive or args.dir_only):
        print(f"{PROG}: cannot remove '{path}': Is a directory",
              file=sys.stderr)
        return False, False
    if is_dir and args.dir_only and not args.recursive:
        try:
            if any(True for _ in os.scandir(path)):
                print(f"{PROG}: cannot remove '{path}': Directory not empty",
                      file=sys.stderr)
                return False, False
        except OSError as e:
            print(f"{PROG}: cannot remove '{path}': {e.strerror}",
                  file=sys.stderr)
            return False, False

    if args.interactive == "always":
        kind = "directory" if is_dir else "regular file"
        if not prompt(f"remove {kind} '{path}'? "):
            return True, False

    return True, True


def bucket_for(path: str, args: Args) -> str:
    """Return target bucket name for a validated path."""
    if args.purge:
        return "purge"
    if _IS_MACOS:
        return "macos"
    if is_wsl():
        try:
            abs_path = os.path.abspath(path)
            if is_windows_native_path(abs_path):
                return "windows"
        except OSError:
            pass
    return "spec"


def maybe_prompt_once(args: Args) -> bool:
    if args.interactive != "once":
        return True
    n_files = len(args.files)
    if args.recursive:
        msg = (f"remove {n_files} argument{'s' if n_files != 1 else ''} "
               f"recursively? ")
        return prompt(msg)
    if n_files > 3:
        return prompt(f"remove {n_files} arguments? ")
    return True


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    args = parse_argv(argv)

    if not args.files:
        if args.force:
            return 0
        print(f"{PROG}: missing operand\n"
              f"Try '{PROG} --help' for more information.", file=sys.stderr)
        return 1

    if not maybe_prompt_once(args):
        return 0

    ok = True
    buckets: dict[str, List[str]] = {
        "purge": [], "macos": [], "windows": [], "spec": [],
    }
    for f in args.files:
        cont, do_del = validate_one(f, args)
        if not cont:
            ok = False
            continue
        if not do_del:
            continue
        buckets[bucket_for(f, args)].append(f)

    # Execute each bucket.
    if buckets["purge"]:
        for p in buckets["purge"]:
            try:
                purge_one(p, args.verbose, args.one_file_system)
            except OSError as e:
                print(f"{PROG}: cannot remove '{p}': {e.strerror}",
                      file=sys.stderr)
                ok = False

    if buckets["macos"]:
        try:
            delete_via_macos_trash(buckets["macos"])
            if args.verbose:
                for p in buckets["macos"]:
                    print(f"removed '{p}'")
        except RuntimeError as e:
            print(f"{PROG}: {e}", file=sys.stderr)
            ok = False

    if buckets["windows"]:
        try:
            delete_via_windows_recycle(buckets["windows"])
            if args.verbose:
                for p in buckets["windows"]:
                    print(f"removed '{p}'")
        except RuntimeError as e:
            print(f"{PROG}: {e}", file=sys.stderr)
            ok = False

    if buckets["spec"]:
        for p in buckets["spec"]:
            try:
                trash_one(p)
                if args.verbose:
                    print(f"removed '{p}'")
            except RuntimeError as e:
                print(f"{PROG}: {e}", file=sys.stderr)
                ok = False
            except OSError as e:
                print(f"{PROG}: cannot remove '{p}': {e.strerror}",
                      file=sys.stderr)
                ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
