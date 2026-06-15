"""Trash backend dispatcher — model + multi-backend scan/trash.

Each backend (backends/freedesktop, backends/macos, backends/windows)
exposes scan() and trash(). This module picks the applicable backends
for the current platform and dispatches.
"""
from __future__ import annotations

import importlib.util
import os
import sys
from typing import List, Optional


# ---------- model ----------

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


# ---------- backend loading ----------

def _load_backend(name: str):
    self_real = os.path.realpath(__file__)
    path = os.path.join(os.path.dirname(self_real), "backends", f"{name}.py")
    spec = importlib.util.spec_from_file_location(f"backends.{name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _is_wsl() -> bool:
    if sys.platform != "linux":
        return False
    try:
        with open("/proc/version", "r", encoding="utf-8", errors="replace") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def _get_backends():
    names = ["freedesktop"]
    if sys.platform == "darwin":
        names.append("macos")
    if _is_wsl():
        names.append("windows")
    return [_load_backend(n) for n in names]


# ---------- public API ----------

def scan_trash(specific_dir: Optional[str] = None) -> List[TrashedFile]:
    """Scan all applicable backends and return merged TrashedFiles."""
    if specific_dir:
        return _load_backend("freedesktop").scan(specific_dir)

    results: List[TrashedFile] = []
    seen: set[str] = set()

    for backend in _get_backends():
        for tf in backend.scan():
            if tf.files_path not in seen:
                seen.add(tf.files_path)
                results.append(tf)

    results.sort(key=lambda t: (t.deletion_date, t.files_path))
    return results


def trash_files(paths: List[str]) -> List[str]:
    """Route paths to appropriate backend trash(). Returns list of errors."""
    if not paths:
        return []

    if sys.platform == "darwin":
        return _load_backend("macos").trash(paths)

    if _is_wsl():
        win_backend = _load_backend("windows")
        fd_backend = _load_backend("freedesktop")
        win_paths = [p for p in paths if win_backend.is_windows_native_path(os.path.abspath(p))]
        fd_paths = [p for p in paths if p not in win_paths]
        errors: List[str] = []
        if win_paths:
            errors.extend(win_backend.trash(win_paths))
        if fd_paths:
            errors.extend(fd_backend.trash(fd_paths))
        return errors

    return _load_backend("freedesktop").trash(paths)
