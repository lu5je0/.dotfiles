"""macOS ~/.Trash backend.

Scans ~/.Trash and reads original paths from the .DS_Store put-back
records (ptbL / ptbN) without external dependencies.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import struct
import subprocess
from datetime import datetime
from typing import Dict, List, Tuple


def _load_trash_backend():
    parent = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    path = os.path.join(parent, "trash_backend.py")
    spec = importlib.util.spec_from_file_location("trash_backend", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TrashedFile = _load_trash_backend().TrashedFile


# ---------- .DS_Store parser ----------

def _parse_dsstore_putback(ds_path: str) -> Dict[str, Tuple[str, str]]:
    """Parse .DS_Store ptbL/ptbN records -> {trash_name: (dir, filename)}.

    Full original path = "/" + dir + filename.
    """
    try:
        with open(ds_path, "rb") as f:
            data = f.read()
    except OSError:
        return {}

    records: Dict[str, Dict[str, str]] = {}
    for marker in (b"ptbL", b"ptbN"):
        start = 0
        while True:
            idx = data.find(marker, start)
            if idx == -1:
                break
            start = idx + 4
            if idx + 12 > len(data):
                continue
            if data[idx + 4:idx + 8] != b"ustr":
                continue
            str_len = struct.unpack(">I", data[idx + 8:idx + 12])[0]
            end = idx + 12 + str_len * 2
            if end > len(data):
                continue
            value = data[idx + 12:end].decode("utf-16-be", errors="replace")

            fname = None
            for try_len in range(1, 300):
                name_start = idx - try_len * 2
                len_start = name_start - 4
                if len_start < 0:
                    break
                candidate = struct.unpack(">I", data[len_start:name_start])[0]
                if candidate == try_len:
                    fname = data[name_start:idx].decode(
                        "utf-16-be", errors="replace"
                    )
                    break
            if fname is None:
                continue
            records.setdefault(fname, {})[marker.decode()] = value

    return {
        name: (info["ptbL"], info["ptbN"])
        for name, info in records.items()
        if "ptbL" in info and "ptbN" in info
    }


# ---------- public ----------

def scan() -> List[TrashedFile]:
    trash_dir = os.path.expanduser("~/.Trash")
    if not os.path.isdir(trash_dir):
        return []

    try:
        entries = os.listdir(trash_dir)
    except OSError:
        return []

    putback = _parse_dsstore_putback(os.path.join(trash_dir, ".DS_Store"))

    results: List[TrashedFile] = []
    for entry in entries:
        if entry.startswith("."):
            continue
        files_path = os.path.join(trash_dir, entry)
        try:
            st = os.lstat(files_path)
        except OSError:
            continue

        dt = datetime.fromtimestamp(st.st_mtime)
        deletion_date = dt.strftime("%Y-%m-%dT%H:%M:%S")

        pb = putback.get(entry)
        if pb:
            original_path = "/" + pb[0] + pb[1]
        else:
            original_path = entry

        results.append(TrashedFile(
            original_path=original_path,
            deletion_date=deletion_date,
            trash_dir=trash_dir,
            info_path="",
            files_path=files_path,
            name=entry,
        ))

    return results


def trash(paths: List[str]) -> List[str]:
    """Move paths to macOS trash via system `trash` command. Returns errors."""
    if not shutil.which("trash"):
        return [
            "'trash' command not found; install one (e.g. `brew install trash`) "
            "or use --purge"
        ]
    abs_paths = [os.path.abspath(p) for p in paths]
    r = subprocess.run(
        ["trash", *abs_paths],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip().splitlines()
        last = msg[-1] if msg else f"exit {r.returncode}"
        return [f"macOS trash failed: {last}"]
    return []
