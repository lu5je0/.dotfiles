"""Windows Recycle Bin backend (WSL only).

Sends files on Windows-native drives (drvfs/9p/virtiofs) to the
Windows Recycle Bin via PowerShell.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
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


# ---------- public: scan ----------

def scan() -> List[TrashedFile]:
    # TODO: implement via PowerShell COM Shell.Application
    return []


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
