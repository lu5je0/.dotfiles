"""macOS ~/.Trash backend.

Scans ~/.Trash and reads original paths from the .DS_Store put-back
records (ptbL / ptbN) without external dependencies.

Trashing is done through the native Foundation API
(-[NSFileManager trashItemAtURL:resultingItemURL:error:]) via ctypes,
so it needs neither the third-party `trash` binary nor PyObjC. The
system API records the put-back metadata itself, keeping Finder's
"Put Back" and this backend's scan/restore working.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import importlib.util
import os
import struct
from datetime import datetime
from typing import Dict, List, Optional, Tuple


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
        if entry in (".DS_Store", ".Trashes"):
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


# ---------- Objective-C runtime binding (ctypes, no PyObjC) ----------

_objc_cache: Dict[str, object] = {}


def _objc_runtime():
    """Lazily build the Objective-C bindings needed for trashing.

    Returns a dict of ready-to-call ctypes function pointers and cached
    class/selector pointers, or raises OSError if the runtime can't load.
    """
    if _objc_cache:
        return _objc_cache

    objc_path = ctypes.util.find_library("objc")
    if not objc_path:
        raise OSError("libobjc not found")
    objc = ctypes.CDLL(objc_path)
    # Loading Foundation registers NSFileManager / NSURL / NSString.
    foundation_path = ctypes.util.find_library("Foundation")
    if not foundation_path:
        raise OSError("Foundation framework not found")
    ctypes.CDLL(foundation_path)

    void_p = ctypes.c_void_p
    objc.objc_getClass.restype = void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]

    def make_send(restype, argtypes):
        proto = ctypes.CFUNCTYPE(restype, *argtypes)
        return proto(("objc_msgSend", objc))

    cls = lambda name: objc.objc_getClass(name.encode())
    sel = lambda name: objc.sel_registerName(name.encode())

    _objc_cache.update({
        "NSFileManager": cls("NSFileManager"),
        "NSString": cls("NSString"),
        "NSURL": cls("NSURL"),
        "sel_defaultManager": sel("defaultManager"),
        "sel_stringWithUTF8String": sel("stringWithUTF8String:"),
        "sel_fileURLWithPath": sel("fileURLWithPath:"),
        "sel_trashItem": sel("trashItemAtURL:resultingItemURL:error:"),
        "sel_localizedDescription": sel("localizedDescription"),
        "sel_UTF8String": sel("UTF8String"),
        # id method(id, SEL)
        "send_id0": make_send(void_p, [void_p, void_p]),
        # id method(id, SEL, char*)
        "send_id_cstr": make_send(void_p, [void_p, void_p, ctypes.c_char_p]),
        # id method(id, SEL, id)
        "send_id_id": make_send(void_p, [void_p, void_p, void_p]),
        # BOOL method(id, SEL, id, id*, id*)
        "send_trash": make_send(
            ctypes.c_bool,
            [void_p, void_p, void_p, void_p, void_p],
        ),
        # char* method(id, SEL)
        "send_cstr": make_send(ctypes.c_char_p, [void_p, void_p]),
    })
    return _objc_cache


def _nsstring(rt, s: str) -> ctypes.c_void_p:
    return rt["send_id_cstr"](
        rt["NSString"], rt["sel_stringWithUTF8String"],
        s.encode("utf-8"),
    )


def _error_message(rt, err_ptr: ctypes.c_void_p) -> Optional[str]:
    if not err_ptr:
        return None
    desc = rt["send_id0"](err_ptr, rt["sel_localizedDescription"])
    if not desc:
        return None
    cstr = rt["send_cstr"](desc, rt["sel_UTF8String"])
    return cstr.decode("utf-8", errors="replace") if cstr else None


def trash(paths: List[str]) -> List[str]:
    """Move paths to macOS trash via Foundation API. Returns errors."""
    try:
        rt = _objc_runtime()
    except OSError as e:
        return [f"macOS trash unavailable: {e}"]

    void_p = ctypes.c_void_p
    errors: List[str] = []
    for p in paths:
        abs_path = os.path.abspath(p)
        url = rt["send_id_id"](
            rt["NSURL"], rt["sel_fileURLWithPath"], _nsstring(rt, abs_path),
        )
        if not url:
            errors.append(f"macOS trash failed: bad path {abs_path}")
            continue
        manager = rt["send_id0"](
            rt["NSFileManager"], rt["sel_defaultManager"],
        )
        err = void_p(0)
        ok = rt["send_trash"](
            manager, rt["sel_trashItem"], url, None, ctypes.byref(err),
        )
        if not ok:
            msg = _error_message(rt, err) or "unknown error"
            errors.append(f"macOS trash failed for {abs_path}: {msg}")
    return errors
