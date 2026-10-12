"""Windows Recycle Bin backend (WSL only).

Sends files on Windows-native drives (drvfs/9p/virtiofs) to the
Windows Recycle Bin via PowerShell, and reads the bin by parsing
$I metadata files directly under each volume's $Recycle.Bin/<SID>/.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import struct
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from typing import List, Optional


def _load_model():
    parent = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    path = os.path.join(parent, "trash_backend.py")
    spec = importlib.util.spec_from_file_location("trash_backend", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TrashedFile = _load_model().TrashedFile

_WIN_FSTYPES = {"drvfs", "9p", "virtiofs"}


# ---------- WSL helpers ----------

_IS_WSL: Optional[bool] = None


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


def _volume_of(path: str) -> str:
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


def _fstype_of(mount_point: str) -> str:
    parent = os.path.dirname(os.path.realpath(__file__))
    fd_path = os.path.join(parent, "freedesktop.py")
    spec = importlib.util.spec_from_file_location("backends.freedesktop", fd_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod._read_mount_fstype_map().get(mount_point, "")


def is_windows_native_path(abs_path: str) -> bool:
    if not is_wsl():
        return False
    return _fstype_of(_volume_of(abs_path)) in _WIN_FSTYPES


def _to_windows_path(abs_path: str) -> Optional[str]:
    try:
        r = subprocess.run(
            ["wslpath", "-w", abs_path],
            capture_output=True, text=True, check=True,
        )
        return r.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def _find_powershell() -> Optional[str]:
    p = shutil.which("powershell.exe")
    if p:
        return p
    fallback = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    if os.path.exists(fallback):
        return fallback
    return None


# ---------- scan helpers ----------

_FILETIME_EPOCH = datetime(1601, 1, 1, tzinfo=timezone.utc)


def _windows_mounts() -> List[str]:
    out: List[str] = []
    try:
        with open("/proc/self/mounts", "r", encoding="utf-8",
                  errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[2] in _WIN_FSTYPES:
                    mp = parts[1].replace(r"\040", " ")
                    if mp.startswith("/mnt/"):
                        out.append(mp)
    except OSError:
        pass
    return out


def _filetime_to_local_iso(ft: int) -> str:
    if ft <= 0:
        return ""
    try:
        dt = (_FILETIME_EPOCH + timedelta(microseconds=ft // 10)).astimezone()
    except (OverflowError, OSError, ValueError):
        return ""
    return dt.strftime("%Y-%m-%dT%H:%M:%S")


def _windows_to_wsl(p: str) -> str:
    if len(p) >= 2 and p[1] == ":":
        return f"/mnt/{p[0].lower()}{p[2:].replace(chr(92), '/')}"
    return p


def _parse_i_file(path: str) -> Optional[tuple]:
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 24:
        return None
    version, _size = struct.unpack("<qq", data[:16])
    ts, = struct.unpack("<q", data[16:24])
    if version == 2:
        if len(data) < 28:
            return None
        nchars, = struct.unpack("<I", data[24:28])
        raw = data[28:28 + nchars * 2]
    else:
        raw = data[24:24 + 520]
    name = raw.decode("utf-16-le", errors="replace").rstrip("\x00")
    if not name:
        return None
    return _filetime_to_local_iso(ts), _windows_to_wsl(name)


# ---------- public: scan ----------

def scan() -> List[TrashedFile]:
    if not is_wsl():
        return []

    out: List[TrashedFile] = []
    for mp in _windows_mounts():
        rb = os.path.join(mp, "$Recycle.Bin")
        try:
            sids = os.listdir(rb)
        except OSError:
            continue
        for sid in sids:
            sid_dir = os.path.join(rb, sid)
            try:
                entries = os.listdir(sid_dir)
            except OSError:
                continue
            for e in entries:
                if not e.startswith("$I") or len(e) < 3:
                    continue
                i_path = os.path.join(sid_dir, e)
                parsed = _parse_i_file(i_path)
                if parsed is None:
                    continue
                r_path = os.path.join(sid_dir, "$R" + e[2:])
                if not os.path.lexists(r_path):
                    continue
                date, original = parsed
                out.append(TrashedFile(
                    original_path=original,
                    deletion_date=date,
                    trash_dir=sid_dir,
                    info_path=i_path,
                    files_path=r_path,
                    name=e[2:],
                ))
    return out


# ---------- public: trash ----------

def trash(paths: List[str]) -> List[str]:
    """Send paths to Windows Recycle Bin via PowerShell. Returns errors."""
    ps = _find_powershell()
    if not ps:
        return ["powershell.exe not found; cannot use Windows Recycle Bin"]

    win_paths: List[str] = []
    for p in paths:
        wp = _to_windows_path(os.path.abspath(p))
        if wp is None:
            return [f"wslpath failed for '{p}'"]
        win_paths.append(wp)

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
    r = subprocess.run(
        [ps, "-NoProfile", "-NonInteractive",
         "-ExecutionPolicy", "Bypass", "-Command", "\n".join(ps_lines)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip().splitlines()
        last = msg[-1] if msg else f"exit {r.returncode}"
        return [f"Windows Recycle Bin failed: {last}"]
    return []
