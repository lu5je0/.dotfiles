#!/usr/bin/env python3
"""q-trash — manage freedesktop.org trash (list / restore / empty / size).

Companion to q-rm. Scans all trash directories by reading /proc/self/mounts
directly (no psutil dependency), so it works on WSL2 virtiofs where trash-cli
fails. Shared mount/sticky-bit helpers are imported from q-rm.py via importlib
to avoid duplication.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import sys
from datetime import datetime
from typing import List, Optional, Tuple
from urllib.parse import unquote

VERSION = "0.1.0"
PROG = "q-trash"

HELP_TEXT = f"""\
Usage: {PROG} <command> [options]

Commands:
  list [PATH]              list trashed files (optionally filter by original path)
  restore [PATTERN]        interactively restore trashed files
  empty [--days N]         permanently delete trashed files
  size                     show trash disk usage
  rm [OPTION]... [FILE]... move files to trash (same as q-rm)

Options:
  --trash-dir DIR          operate on a specific trash directory only
  --help                   display this help
  --version                show version

Examples:
  {PROG} list                   # list all trashed files
  {PROG} list .                 # list files trashed from current directory
  {PROG} restore                # interactive restore (current dir)
  {PROG} restore /path/to/file  # restore specific file (latest match)
  {PROG} restore --all .        # restore all files from current dir
  {PROG} empty                  # empty all trash (with confirmation)
  {PROG} empty --days 30        # empty items older than 30 days
  {PROG} size                   # show trash usage per volume
"""


# ---------- shared helpers from q-rm ----------

def _load_qrm():
    self_real = os.path.realpath(__file__)
    qrm_path = os.path.join(os.path.dirname(self_real), "q-rm.py")
    spec = importlib.util.spec_from_file_location("qrm", qrm_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_qrm = _load_qrm()


# ---------- mount/trash discovery ----------

def read_mount_points() -> dict[str, str]:
    """Return {mountpoint: fstype} for all relevant mount points."""
    if sys.platform == "darwin":
        return _read_mount_points_macos()
    return _qrm._read_mount_fstype_map()


def _read_mount_points_macos() -> dict[str, str]:
    """Discover mount points on macOS via /Volumes and /."""
    out: dict[str, str] = {"/": "apfs"}
    volumes = "/Volumes"
    if os.path.isdir(volumes):
        try:
            for entry in os.scandir(volumes):
                if entry.is_dir(follow_symlinks=True):
                    out[entry.path] = "apfs"
        except OSError:
            pass
    return out


def discover_trash_dirs(specific_dir: Optional[str] = None) -> List[Tuple[str, str]]:
    """Return list of (trash_dir, volume_root).

    If specific_dir is given, only return that one (caller opt-in, no
    sticky-bit check). Otherwise apply Trash Spec 1.0 reader checks:
    $top/.Trash must be a sticky non-symlink dir; $top/.Trash-$UID must
    not itself be a symlink.
    """
    if specific_dir:
        vol = _guess_volume_of_trash(specific_dir)
        return [(specific_dir, vol)]

    uid = os.getuid()
    results: List[Tuple[str, str]] = []

    # Home trash
    ht = _qrm.home_trash_dir()
    if os.path.isdir(os.path.join(ht, "info")):
        home = os.path.expanduser("~")
        home_vol = _volume_of_dir(home)
        results.append((ht, home_vol))

    # Volume-level trash dirs
    mounts = read_mount_points()
    for mp in mounts:
        # $top/.Trash/$UID — only when $top/.Trash is sticky, non-symlink
        top_trash = os.path.join(mp, ".Trash")
        if _qrm.is_safe_top_trash(top_trash):
            d = os.path.join(top_trash, str(uid))
            if os.path.isdir(os.path.join(d, "info")):
                results.append((d, mp))
        # $top/.Trash-$UID — must not be a symlink itself
        d = os.path.join(mp, f".Trash-{uid}")
        if (not os.path.islink(d)
                and os.path.isdir(os.path.join(d, "info"))
                and not any(x[0] == d for x in results)):
            results.append((d, mp))

    return results


def _volume_of_dir(path: str) -> str:
    """Walk up to find mount point by st_dev change."""
    path = os.path.realpath(path)
    try:
        dev = os.stat(path).st_dev
    except OSError:
        return "/"
    cur = path
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


def _guess_volume_of_trash(trash_dir: str) -> str:
    """Guess volume root from trash dir path.

    e.g. /mnt/c/.Trash-1000 → /mnt/c
         ~/.local/share/Trash → volume_of(~)
    """
    td = os.path.realpath(trash_dir)
    base = os.path.basename(td)
    if base.startswith(".Trash"):
        return os.path.dirname(td)
    parent = os.path.dirname(td)
    base_parent = os.path.basename(parent)
    if base_parent == ".Trash":
        return os.path.dirname(parent)
    return _volume_of_dir(td)


# ---------- trashinfo parsing ----------

class TrashedFile:
    __slots__ = ("original_path", "deletion_date", "trash_dir",
                 "info_path", "files_path", "name")

    def __init__(self, original_path: str, deletion_date: str,
                 trash_dir: str, info_path: str, files_path: str,
                 name: str) -> None:
        self.original_path = original_path
        self.deletion_date = deletion_date
        self.trash_dir = trash_dir
        self.info_path = info_path
        self.files_path = files_path
        self.name = name


def parse_trashinfo(info_path: str, volume_root: str) -> Optional[TrashedFile]:
    """Parse a .trashinfo file and return a TrashedFile, or None on error."""
    try:
        with open(info_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError:
        return None

    path_val = None
    date_val = ""
    for line in content.splitlines():
        if line.startswith("Path="):
            path_val = unquote(line[5:])
        elif line.startswith("DeletionDate="):
            date_val = line[13:]

    if path_val is None:
        return None

    # Absolute or relative path?
    if os.path.isabs(path_val):
        original = path_val
    else:
        original = os.path.join(volume_root, path_val)

    # Derive files path from info path
    info_dir = os.path.dirname(info_path)
    trash_dir = os.path.dirname(info_dir)
    name = os.path.basename(info_path)
    if name.endswith(".trashinfo"):
        name = name[:-10]
    files_path = os.path.join(trash_dir, "files", name)

    return TrashedFile(
        original_path=original,
        deletion_date=date_val,
        trash_dir=trash_dir,
        info_path=info_path,
        files_path=files_path,
        name=name,
    )


def scan_trash(specific_dir: Optional[str] = None) -> List[TrashedFile]:
    """Scan all discoverable trash dirs and return TrashedFiles."""
    results: List[TrashedFile] = []
    for trash_dir, volume_root in discover_trash_dirs(specific_dir):
        info_dir = os.path.join(trash_dir, "info")
        if not os.path.isdir(info_dir):
            continue
        try:
            entries = os.listdir(info_dir)
        except OSError:
            continue
        for entry in entries:
            if not entry.endswith(".trashinfo"):
                continue
            info_path = os.path.join(info_dir, entry)
            tf = parse_trashinfo(info_path, volume_root)
            if tf:
                results.append(tf)
    results.sort(key=lambda t: (t.deletion_date, t.info_path))
    return results


# ---------- commands ----------

def cmd_list(args: List[str], trash_dir_opt: Optional[str]) -> int:
    filter_path: Optional[str] = None
    if args:
        filter_path = os.path.abspath(args[0])

    items = scan_trash(trash_dir_opt)
    if filter_path:
        items = [t for t in items
                 if t.original_path == filter_path
                 or t.original_path.startswith(filter_path.rstrip("/") + "/")]

    if not items:
        print("No trashed files.", file=sys.stderr)
        return 0

    for t in items:
        print(f"{t.deletion_date}  {t.original_path}")
    return 0


def cmd_restore(args: List[str], trash_dir_opt: Optional[str]) -> int:
    restore_all = False
    overwrite = False
    remaining: List[str] = []

    for arg in args:
        if arg == "--all":
            restore_all = True
        elif arg == "--overwrite":
            overwrite = True
        elif arg == "--help":
            sys.stdout.write(HELP_TEXT)
            return 0
        else:
            remaining.append(arg)

    explicit_path = bool(remaining)
    if explicit_path:
        filter_path = os.path.abspath(remaining[0])
    else:
        filter_path = os.path.abspath(".")

    items = scan_trash(trash_dir_opt)

    # Auto-pick latest exact match only when an explicit path was given;
    # otherwise (no arg => cwd) fall through to the interactive picker so
    # we never silently restore the cwd itself.
    exact = [t for t in items if t.original_path == filter_path]
    if explicit_path and exact and not restore_all:
        to_restore = [exact[-1]]
    elif restore_all:
        items = [t for t in items
                 if t.original_path == filter_path
                 or t.original_path.startswith(filter_path.rstrip("/") + "/")]
        if not items:
            print(f"No files trashed from '{filter_path}'", file=sys.stderr)
            return 1
        # Deduplicate: for each original_path, only restore the latest version
        # to avoid overwriting during batch restore.
        seen: dict[str, TrashedFile] = {}
        for t in items:
            seen[t.original_path] = t  # last one wins (list is sorted by date)
        to_restore = list(seen.values())
    else:
        items = [t for t in items
                 if t.original_path == filter_path
                 or t.original_path.startswith(filter_path.rstrip("/") + "/")]
        if not items:
            print(f"No files trashed from '{filter_path}'", file=sys.stderr)
            return 1
        # Interactive picker writes to stderr so stdout stays parseable.
        for idx, t in enumerate(items):
            sys.stderr.write(
                f"  {idx:3d}  {t.deletion_date}  {t.original_path}\n"
            )
        sys.stderr.write(f"What to restore [0..{len(items) - 1}, all, quit]: ")
        sys.stderr.flush()
        try:
            line = sys.stdin.readline().strip()
        except KeyboardInterrupt:
            return 1
        if not line or line == "quit" or line == "q":
            return 0
        if line == "all":
            to_restore = items
        else:
            try:
                indices = [int(x.strip()) for x in line.replace(",", " ").split()]
            except ValueError:
                print(f"{PROG}: invalid input", file=sys.stderr)
                return 1
            to_restore = []
            for idx in indices:
                if 0 <= idx < len(items):
                    to_restore.append(items[idx])
                else:
                    print(f"{PROG}: index {idx} out of range", file=sys.stderr)
                    return 1

    ok = True
    for t in to_restore:
        if not _do_restore(t, overwrite):
            ok = False
    return 0 if ok else 1


def _do_restore(t: TrashedFile, overwrite: bool) -> bool:
    dest = t.original_path

    # Verify backup exists BEFORE touching the destination — otherwise an
    # --overwrite on a trashinfo with a missing files/ entry would destroy
    # the user's current file with nothing to restore from.
    if not os.path.exists(t.files_path) and not os.path.islink(t.files_path):
        print(f"{PROG}: backup file missing: '{t.files_path}'", file=sys.stderr)
        return False

    if os.path.exists(dest) or os.path.islink(dest):
        if not overwrite:
            print(f"{PROG}: '{dest}' already exists (use --overwrite)",
                  file=sys.stderr)
            return False
        if os.path.isdir(dest) and not os.path.islink(dest):
            shutil.rmtree(dest)
        else:
            os.unlink(dest)

    parent = os.path.dirname(dest)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent, exist_ok=True)

    try:
        os.rename(t.files_path, dest)
    except OSError as e:
        print(f"{PROG}: cannot restore '{dest}': {e.strerror}", file=sys.stderr)
        return False

    try:
        os.unlink(t.info_path)
    except OSError:
        pass

    print(f"Restored: {dest}")
    return True


def cmd_empty(args: List[str], trash_dir_opt: Optional[str]) -> int:
    days: Optional[int] = None
    force = False

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--help":
            sys.stdout.write(HELP_TEXT)
            return 0
        if arg == "--days":
            if i + 1 >= len(args):
                print(f"{PROG}: --days requires an argument", file=sys.stderr)
                return 1
            try:
                days = int(args[i + 1])
            except ValueError:
                print(f"{PROG}: invalid --days value", file=sys.stderr)
                return 1
            i += 2
        elif arg.startswith("--days="):
            try:
                days = int(arg[len("--days="):])
            except ValueError:
                print(f"{PROG}: invalid --days value", file=sys.stderr)
                return 1
            i += 1
        elif arg in ("-f", "--force"):
            force = True
            i += 1
        else:
            print(f"{PROG}: unknown argument '{arg}'", file=sys.stderr)
            return 1

    items = scan_trash(trash_dir_opt)

    if days is not None:
        cutoff = datetime.now()
        filtered = []
        for t in items:
            try:
                dt = datetime.strptime(t.deletion_date, "%Y-%m-%dT%H:%M:%S")
            except ValueError:
                # Unparseable date: keep it (conservative — don't delete
                # something we can't age-check).
                continue
            if (cutoff - dt).days >= days:
                filtered.append(t)
        items = filtered

    if not items:
        print("Trash is already empty.")
        return 0

    if not force:
        msg = f"Permanently delete {len(items)} item{'s' if len(items) != 1 else ''}?"
        if days is not None:
            msg += f" (older than {days} days)"
        sys.stderr.write(f"{msg} [y/N] ")
        sys.stderr.flush()
        try:
            line = sys.stdin.readline().strip()
        except KeyboardInterrupt:
            return 1
        if not line.lower().startswith("y"):
            print("Cancelled.")
            return 0

    deleted = 0
    for t in items:
        try:
            if os.path.isdir(t.files_path) and not os.path.islink(t.files_path):
                shutil.rmtree(t.files_path)
            elif os.path.exists(t.files_path) or os.path.islink(t.files_path):
                os.unlink(t.files_path)
        except OSError as e:
            print(f"{PROG}: cannot delete '{t.files_path}': {e.strerror}",
                  file=sys.stderr)
            continue
        try:
            os.unlink(t.info_path)
        except OSError:
            pass
        deleted += 1

    print(f"Deleted {deleted} item{'s' if deleted != 1 else ''}.")
    return 0


def cmd_size(args: List[str], trash_dir_opt: Optional[str]) -> int:
    items = scan_trash(trash_dir_opt)
    if not items:
        print("All trash directories are empty.")
        return 0

    sized = []
    total_size = 0
    for t in items:
        try:
            st = os.lstat(t.files_path)
        except OSError:
            continue
        if os.path.isdir(t.files_path) and not os.path.islink(t.files_path):
            size = _dir_size(t.files_path)
        else:
            size = st.st_size
        sized.append((size, t))
        total_size += size

    sized.sort(key=lambda x: x[0], reverse=True)

    for size, t in sized:
        print(f"{_human_size(size):>10}  {t.deletion_date}  {t.original_path}")

    print(f"{_human_size(total_size):>10}  Total ({len(sized)} item{'s' if len(sized) != 1 else ''})")
    return 0


def _dir_size(path: str) -> int:
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                if entry.is_dir(follow_symlinks=False):
                    total += _dir_size(entry.path)
                else:
                    try:
                        total += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        pass
    except OSError:
        pass
    return total


def _human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(size) < 1024:
            if unit == "B":
                return f"{n} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"


def cmd_rm(args: List[str]) -> int:
    """Delegate to q-rm's main()."""
    return _qrm.main(args)


# ---------- main ----------

def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    if not argv or argv[0] in ("--help", "-h"):
        sys.stdout.write(HELP_TEXT)
        return 0
    if argv[0] == "--version":
        print(f"{PROG} {VERSION}")
        return 0

    # Extract global --trash-dir option
    trash_dir_opt: Optional[str] = None
    filtered_argv: List[str] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--trash-dir" and i + 1 < len(argv):
            trash_dir_opt = argv[i + 1]
            i += 2
        else:
            filtered_argv.append(argv[i])
            i += 1

    if not filtered_argv:
        sys.stdout.write(HELP_TEXT)
        return 0

    cmd = filtered_argv[0]
    cmd_args = filtered_argv[1:]

    if cmd == "list" or cmd == "ls":
        return cmd_list(cmd_args, trash_dir_opt)
    elif cmd == "restore":
        return cmd_restore(cmd_args, trash_dir_opt)
    elif cmd == "empty":
        return cmd_empty(cmd_args, trash_dir_opt)
    elif cmd == "size":
        return cmd_size(cmd_args, trash_dir_opt)
    elif cmd == "rm":
        return cmd_rm(cmd_args)
    else:
        print(f"{PROG}: unknown command '{cmd}'\n"
              f"Try '{PROG} --help' for more information.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
