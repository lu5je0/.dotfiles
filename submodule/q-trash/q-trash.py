#!/usr/bin/env python3
"""q-trash — manage trash (list / restore / empty / size).

Platform-aware companion to q-rm. Trash discovery and scanning logic
lives in trash_backend.py; this file is the CLI front-end.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import sys
from datetime import datetime
from typing import List, Optional

VERSION = "0.1.0"
PROG = "q-trash"

EXAMPLES = f"""\
examples:
  {PROG} list                   # list all trashed files
  {PROG} list .                 # list files trashed from current directory
  {PROG} restore                # interactive restore (all files)
  {PROG} restore /path/to/file  # restore specific file (latest match)
  {PROG} restore --all .        # restore all files from current dir
  {PROG} restore --dest /tmp /path/to/file
                                # restore to /tmp instead of original
  {PROG} empty                  # empty all trash (with confirmation)
  {PROG} empty --days 30        # empty items older than 30 days
  {PROG} size                   # show trash usage per volume
"""


# ---------- imports ----------

def _load_module(filename: str, mod_name: str):
    self_real = os.path.realpath(__file__)
    path = os.path.join(os.path.dirname(self_real), filename)
    spec = importlib.util.spec_from_file_location(mod_name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_backend = _load_module("trash_backend.py", "trash_backend")
TrashedFile = _backend.TrashedFile
scan_trash = _backend.scan_trash


# ---------- commands ----------

def cmd_list(ns: argparse.Namespace) -> int:
    filter_path: Optional[str] = None
    if ns.path:
        filter_path = os.path.abspath(ns.path)

    items = scan_trash(ns.trash_dir)
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


def cmd_restore(ns: argparse.Namespace) -> int:
    restore_all = ns.all
    overwrite = ns.overwrite
    dest_opt = ns.dest

    explicit_path = bool(ns.path)
    filter_path = os.path.abspath(ns.path) if explicit_path else None

    items = scan_trash(ns.trash_dir)

    exact = [t for t in items if t.original_path == filter_path] if filter_path else []
    if explicit_path and exact and not restore_all:
        to_restore = [exact[-1]]
    elif restore_all:
        if filter_path:
            items = [t for t in items
                     if t.original_path == filter_path
                     or t.original_path.startswith(filter_path.rstrip("/") + "/")]
        if not items:
            msg = f"No files trashed from '{filter_path}'" if filter_path else "No trashed files."
            print(msg, file=sys.stderr)
            return 1
        seen: dict[str, TrashedFile] = {}
        for t in items:
            seen[t.original_path] = t
        to_restore = list(seen.values())
    else:
        if filter_path:
            items = [t for t in items
                     if t.original_path == filter_path
                     or t.original_path.startswith(filter_path.rstrip("/") + "/")]
        if not items:
            msg = f"No files trashed from '{filter_path}'" if filter_path else "No trashed files."
            print(msg, file=sys.stderr)
            return 1
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

    if dest_opt is not None:
        dest_abs = os.path.abspath(dest_opt)
        is_existing_dir = os.path.isdir(dest_abs) and not os.path.islink(dest_abs)
        if not is_existing_dir and len(to_restore) > 1:
            try:
                os.makedirs(dest_abs, exist_ok=True)
            except OSError as e:
                print(f"{PROG}: cannot create dest '{dest_abs}': {e.strerror}",
                      file=sys.stderr)
                return 1
            is_existing_dir = True

        plan: List[tuple] = []
        for t in to_restore:
            if is_existing_dir:
                final_dest = os.path.join(dest_abs, os.path.basename(t.original_path))
            else:
                final_dest = dest_abs
            plan.append((t, final_dest))
    else:
        plan = [(t, t.original_path) for t in to_restore]

    ok = True
    for t, final_dest in plan:
        if not _do_restore(t, final_dest, overwrite):
            ok = False
    return 0 if ok else 1


def _do_restore(t: TrashedFile, dest: str, overwrite: bool) -> bool:
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

    if t.info_path:
        try:
            os.unlink(t.info_path)
        except OSError:
            pass

    print(f"Restored: {dest}")
    return True


def cmd_empty(ns: argparse.Namespace) -> int:
    days = ns.days
    force = ns.force

    items = scan_trash(ns.trash_dir)

    if days is not None:
        cutoff = datetime.now()
        filtered = []
        for t in items:
            try:
                dt = datetime.strptime(t.deletion_date, "%Y-%m-%dT%H:%M:%S")
            except ValueError:
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
        if t.info_path:
            try:
                os.unlink(t.info_path)
            except OSError:
                pass
        deleted += 1

    print(f"Deleted {deleted} item{'s' if deleted != 1 else ''}.")
    return 0


def cmd_size(ns: argparse.Namespace) -> int:
    items = scan_trash(ns.trash_dir)
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


def cmd_rm(ns: argparse.Namespace) -> int:
    return _load_module("rm_action.py", "rm_action").main(ns.args)


# ---------- main ----------

class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        if "invalid choice" in message:
            tok = message.split("'")[1] if "'" in message else "?"
            self.exit(1, f"{PROG}: unknown command '{tok}'\n"
                     f"Try '{PROG} --help' for more information.\n")
        if "expected one argument" in message:
            flag = message.split(":")[0].replace("argument ", "")
            self.exit(1, f"{PROG}: {flag} requires an argument\n")
        super().error(message)


def _build_parser() -> _Parser:
    parser = _Parser(
        prog=PROG,
        description="Manage trash (list / restore / empty / size).",
        epilog=EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version=f"{PROG} {VERSION}")
    parser.add_argument("--trash-dir", dest="trash_dir", default=None,
                        help="operate on a specific trash directory only")

    sub = parser.add_subparsers(dest="command", parser_class=_Parser)

    # list
    p_list = sub.add_parser("list", aliases=["ls"], help="list trashed files")
    p_list.add_argument("path", nargs="?", default=None,
                        help="filter by original path")
    p_list.set_defaults(func=cmd_list)

    # restore
    p_restore = sub.add_parser("restore", help="interactively restore trashed files")
    p_restore.add_argument("--all", action="store_true",
                           help="restore all matches without interactive prompt")
    p_restore.add_argument("--overwrite", action="store_true",
                           help="overwrite existing files at restore destination")
    p_restore.add_argument("--dest", default=None,
                           help="restore to DIR instead of original location")
    p_restore.add_argument("path", nargs="?", default=None,
                           help="filter by original path")
    p_restore.set_defaults(func=cmd_restore)

    # empty
    p_empty = sub.add_parser("empty", help="permanently delete trashed files")
    p_empty.add_argument("--days", type=int, default=None,
                         help="only delete items older than N days")
    p_empty.add_argument("-f", "--force", action="store_true",
                         help="skip confirmation prompt")
    p_empty.set_defaults(func=cmd_empty)

    # size
    p_size = sub.add_parser("size", help="show trash disk usage")
    p_size.set_defaults(func=cmd_size)

    # rm
    p_rm = sub.add_parser("rm", help="move files to trash (same as q-rm)")
    p_rm.add_argument("args", nargs=argparse.REMAINDER,
                      help="arguments passed to q-rm")
    p_rm.set_defaults(func=cmd_rm)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    # 'rm' subcommand passes arbitrary flags to rm_action; locate it before argparse.
    rm_idx = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "rm":
            rm_idx = i
            break
        if a == "--trash-dir":
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    if rm_idx is not None:
        pre = argv[:rm_idx]
        rm_args = argv[rm_idx + 1:]
        parser = _build_parser()
        ns = parser.parse_args(pre + ["rm"])
        ns.args = rm_args
        return ns.func(ns)

    parser = _build_parser()
    ns = parser.parse_args(argv)

    if not ns.command:
        parser.print_help()
        return 0

    return ns.func(ns)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
