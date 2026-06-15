"""Freedesktop.org Trash Spec 1.0 backend.

Covers Linux, WSL linux-side paths, and any platform with
~/.local/share/Trash or $top/.Trash-$UID directories.
"""
from __future__ import annotations

import errno
import functools
import importlib.util
import os
import stat
import sys
from datetime import datetime
from typing import List, Optional, Tuple
from urllib.parse import quote, unquote


def _load_model():
    parent = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    path = os.path.join(parent, "trash_backend.py")
    spec = importlib.util.spec_from_file_location("trash_backend", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TrashedFile = _load_model().TrashedFile


# ---------- mount / volume ----------

def _read_mount_points() -> dict[str, str]:
    if sys.platform == "darwin":
        return _read_mount_points_macos()
    return _read_mount_fstype_map()


def _read_mount_points_macos() -> dict[str, str]:
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


@functools.cache
def _read_mount_fstype_map() -> dict[str, str]:
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
                    out[_decode_octal(parts[1])] = parts[2]
    except OSError:
        pass
    return out


def volume_of(path: str) -> str:
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


def _volume_of_dir(path: str) -> str:
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
    td = os.path.realpath(trash_dir)
    base = os.path.basename(td)
    if base.startswith(".Trash"):
        return os.path.dirname(td)
    parent = os.path.dirname(td)
    if os.path.basename(parent) == ".Trash":
        return os.path.dirname(parent)
    return _volume_of_dir(td)


# ---------- trash dir helpers ----------

def home_trash_dir() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(base, "Trash")


def is_safe_top_trash(top_trash: str) -> bool:
    if os.path.islink(top_trash):
        return False
    try:
        st = os.stat(top_trash)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and bool(st.st_mode & stat.S_ISVTX)


def _pick_trash_dir(file_path: str) -> Tuple[str, str, str]:
    file_vol = volume_of(file_path)
    home = os.path.expanduser("~")
    home_vol = volume_of(home) if os.path.exists(home) else None

    if home_vol is not None and file_vol == home_vol:
        return home_trash_dir(), home_vol, "absolute"

    uid = os.getuid()
    top_trash = os.path.join(file_vol, ".Trash")
    if is_safe_top_trash(top_trash):
        d = os.path.join(top_trash, str(uid))
        return d, file_vol, "relative"

    return os.path.join(file_vol, f".Trash-{uid}"), file_vol, "relative"


def _ensure_trash_dirs(trash_dir: str) -> None:
    for d in (trash_dir,
              os.path.join(trash_dir, "files"),
              os.path.join(trash_dir, "info")):
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
        except OSError as e:
            raise RuntimeError(f"cannot create '{d}': {e.strerror}") from e


# ---------- trashinfo ----------

def _encode_path(p: str) -> str:
    return quote(p, safe="/")


def _now_local_iso() -> str:
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _reserve_info_file(info_dir: str, base_name: str) -> Tuple[str, str]:
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
                raise RuntimeError(f"too many name collisions in {info_dir}")


def _write_info(info_path: str, original_path: str, path_style: str,
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
            rel = abs_path
    body = (
        "[Trash Info]\n"
        f"Path={_encode_path(rel)}\n"
        f"DeletionDate={_now_local_iso()}\n"
    )
    with open(info_path, "w", encoding="utf-8") as f:
        f.write(body)


def _parse_trashinfo(info_path: str, volume_root: str) -> Optional[TrashedFile]:
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

    if os.path.isabs(path_val):
        original = path_val
    else:
        original = os.path.join(volume_root, path_val)

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


# ---------- discovery ----------

def _discover_trash_dirs(specific_dir: Optional[str] = None) -> List[Tuple[str, str]]:
    if specific_dir:
        return [(specific_dir, _guess_volume_of_trash(specific_dir))]

    uid = os.getuid()
    results: List[Tuple[str, str]] = []

    ht = home_trash_dir()
    if os.path.isdir(os.path.join(ht, "info")):
        home = os.path.expanduser("~")
        results.append((ht, _volume_of_dir(home)))

    mounts = _read_mount_points()
    for mp in mounts:
        top_trash = os.path.join(mp, ".Trash")
        if is_safe_top_trash(top_trash):
            d = os.path.join(top_trash, str(uid))
            if os.path.isdir(os.path.join(d, "info")):
                results.append((d, mp))
        d = os.path.join(mp, f".Trash-{uid}")
        if (not os.path.islink(d)
                and os.path.isdir(os.path.join(d, "info"))
                and not any(x[0] == d for x in results)):
            results.append((d, mp))

    return results


# ---------- public: scan ----------

def scan(specific_dir: Optional[str] = None) -> List[TrashedFile]:
    results: List[TrashedFile] = []
    for trash_dir, volume_root in _discover_trash_dirs(specific_dir):
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
            tf = _parse_trashinfo(os.path.join(info_dir, entry), volume_root)
            if tf:
                results.append(tf)
    return results


# ---------- public: trash ----------

def trash(paths: List[str]) -> List[str]:
    """Move paths to freedesktop trash. Returns list of errors."""
    errors: List[str] = []
    for path in paths:
        try:
            _trash_one(path)
        except (RuntimeError, OSError) as e:
            errors.append(f"cannot remove '{path}': {e}")
    return errors


def _trash_one(path: str) -> None:
    abs_path = os.path.abspath(path)
    trash_dir, volume_root, path_style = _pick_trash_dir(abs_path)

    try:
        _ensure_trash_dirs(trash_dir)
    except RuntimeError as e:
        raise RuntimeError(
            f"cannot use trash dir for '{path}': {e}. "
            f"Use --purge to delete permanently."
        ) from e

    files_dir = os.path.join(trash_dir, "files")
    info_dir = os.path.join(trash_dir, "info")
    base_name = os.path.basename(abs_path.rstrip("/")) or "_"

    name, info_path = _reserve_info_file(info_dir, base_name)
    dest = os.path.join(files_dir, name)
    try:
        _write_info(info_path, abs_path, path_style, volume_root)
        try:
            os.rename(abs_path, dest)
        except OSError as e:
            if e.errno == errno.EXDEV:
                os.unlink(info_path)
                raise RuntimeError(
                    f"'{path}' lives on a different volume from its trash dir "
                    f"('{trash_dir}'). Use --purge to delete permanently."
                ) from e
            os.unlink(info_path)
            raise RuntimeError(f"cannot move '{path}': {e.strerror}") from e
    except Exception:
        try:
            os.unlink(info_path)
        except OSError:
            pass
        raise
