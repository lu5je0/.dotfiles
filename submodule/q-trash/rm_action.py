"""rm-compatible action that moves files to trash.

Handles GNU rm argument parsing, validation, interactive prompts,
and --purge. Delegates actual trashing to trash_backend.trash_files().
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import stat
import sys
from typing import List, Optional, Tuple

PROG = "q-trash"


def _load_trash_backend():
    self_real = os.path.realpath(__file__)
    path = os.path.join(os.path.dirname(self_real), "trash_backend.py")
    spec = importlib.util.spec_from_file_location("trash_backend", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


HELP_TEXT = f"""\
Usage: {PROG} rm [OPTION]... [FILE]...
Move FILEs to trash (rm-compatible).

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
      --purge           bypass trash, delete permanently
      --help            display this help and exit

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
        self.interactive = "never"
        self.recursive = False
        self.dir_only = False
        self.verbose = False
        self.preserve_root = True
        self.one_file_system = False
        self.purge = False
        self.files: List[str] = []


def _die(msg: str, code: int = 1) -> None:
    print(f"{PROG}: {msg}", file=sys.stderr)
    sys.exit(code)


def _parse_argv(argv: List[str]) -> Args:
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
                    _die(f"invalid argument '{val}' for '--interactive'")
            else:
                _die(f"unrecognized option '--{name}'")
            continue
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
                _die(f"invalid option -- '{ch}'")
    return a


# ---------- rm semantics ----------

def _is_dot_or_dotdot(path: str) -> bool:
    p = path
    while len(p) > 1 and p.endswith("/"):
        p = p[:-1]
    return p.rsplit("/", 1)[-1] in (".", "..")


def _is_root_path(path: str) -> bool:
    p = os.path.normpath(os.path.abspath(path))
    return p == "/" or p == "//"


def _prompt(msg: str) -> bool:
    sys.stderr.write(f"{PROG}: {msg}")
    sys.stderr.flush()
    try:
        line = sys.stdin.readline()
    except KeyboardInterrupt:
        return False
    if not line:
        return False
    return line.strip().lower().startswith("y")


def _purge_one(path: str, verbose: bool, one_fs: bool) -> None:
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


def _validate_one(path: str, args: Args) -> Tuple[bool, bool]:
    if path == "":
        if args.force:
            return True, False
        print(f"{PROG}: cannot remove '': No such file or directory",
              file=sys.stderr)
        return False, False

    if _is_dot_or_dotdot(path):
        print(
            f"{PROG}: refusing to remove '.' or '..' directory: skipping '{path}'",
            file=sys.stderr,
        )
        return False, False

    if args.preserve_root and _is_root_path(path):
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

    is_dir = stat.S_ISDIR(st.st_mode)
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
        if not _prompt(f"remove {kind} '{path}'? "):
            return True, False

    return True, True


def _maybe_prompt_once(args: Args) -> bool:
    if args.interactive != "once":
        return True
    n_files = len(args.files)
    if args.recursive:
        return _prompt(
            f"remove {n_files} argument{'s' if n_files != 1 else ''} recursively? "
        )
    if n_files > 3:
        return _prompt(f"remove {n_files} arguments? ")
    return True


# ---------- main ----------

def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    args = _parse_argv(argv)

    if not args.files:
        if args.force:
            return 0
        print(f"{PROG}: rm: missing operand\n"
              f"Try '{PROG} rm --help' for more information.", file=sys.stderr)
        return 1

    if not _maybe_prompt_once(args):
        return 0

    ok = True
    purge_paths: List[str] = []
    trash_paths: List[str] = []

    for f in args.files:
        cont, do_del = _validate_one(f, args)
        if not cont:
            ok = False
            continue
        if not do_del:
            continue
        if args.purge:
            purge_paths.append(f)
        else:
            trash_paths.append(f)

    for p in purge_paths:
        try:
            _purge_one(p, args.verbose, args.one_file_system)
        except OSError as e:
            print(f"{PROG}: cannot remove '{p}': {e.strerror}",
                  file=sys.stderr)
            ok = False

    if trash_paths:
        backend = _load_trash_backend()
        errors = backend.trash_files(trash_paths)
        if errors:
            for err in errors:
                print(f"{PROG}: {err}", file=sys.stderr)
            ok = False
        elif args.verbose:
            for p in trash_paths:
                print(f"removed '{p}'")

    return 0 if ok else 1
