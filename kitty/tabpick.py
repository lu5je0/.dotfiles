#!/usr/bin/env python3
"""kitty tab picker UI kitten (tmux choose-tree style).

Reads the items JSON prepared in-process by tabpick_collect.py (zero
subprocesses), renders the shared tabpick_core picker, and returns the chosen
tab's active window id. handle_result() focuses that window inside the kitty
process.
"""

import json
import os
import sys
import tempfile

DATA_PATH = os.path.join(tempfile.gettempdir(), "tabpick_items.json")


def _find_here():
    d = os.environ.get("KITTY_CONFIG_DIRECTORY")
    if d and os.path.isdir(d):
        return d
    f = globals().get("__file__")
    if f:
        return os.path.dirname(os.path.abspath(f))
    return os.path.expanduser("~/.config/kitty")


_HERE = _find_here()
_LOG = os.path.join(_HERE, "tabpick.log")


def _log(msg):
    try:
        with open(_LOG, "a") as f:
            f.write(str(msg) + "\n")
    except Exception:
        pass


_SHARED = os.path.join(os.path.dirname(os.path.realpath(_HERE)), "submodule", "tui-pick")
sys.path.insert(0, _SHARED)
import tabpick_core  # noqa: E402

import base64  # noqa: E402


def ime(method):
    req = json.dumps({"id": 1, "module": "ime", "method": method, "params": {}})
    b64 = base64.b64encode(req.encode()).decode()
    sys.stdout.write(f"\x1b]1337;SetUserVar=tui_bridge={b64}\x07")
    sys.stdout.flush()


def main(args):
    try:
        with open(DATA_PATH) as f:
            payload = json.load(f)
    except Exception:
        import traceback
        _log("read items FAILED:\n" + traceback.format_exc())
        return "cancel"

    items = payload.get("items") if isinstance(payload, dict) else payload
    if not items:
        return "cancel"

    try:
        target = tabpick_core.pick(
            items,
            on_enter=lambda: ime("normal"),
            on_exit=lambda: ime("insert"),
        )
    except Exception:
        import traceback
        _log("pick FAILED:\n" + traceback.format_exc())
        return "cancel"

    if target:
        return str(target["active_pane_id"])
    origin = next((it for it in items if it.get("active")), None)
    return str(origin["active_pane_id"]) if origin else "cancel"


def handle_result(args, answer, target_window_id, boss):
    # restore the original layout if the collector zoomed the tab to stack
    try:
        with open(DATA_PATH) as f:
            payload = json.load(f)
        restore = payload.get("restore") if isinstance(payload, dict) else None
        if restore:
            for tab in boss.all_tabs:
                if getattr(tab, "id", None) == restore["tab_id"]:
                    tab.goto_layout(restore["layout"])
                    break
    except Exception:
        import traceback
        _log("restore layout FAILED:\n" + traceback.format_exc())

    answer = (answer or "").strip()
    if not answer or answer == "cancel":
        return
    try:
        wid = int(answer)
    except Exception:
        return
    try:
        w = boss.window_id_map.get(wid)
        boss.set_active_window(w if w is not None else wid, switch_os_window_if_needed=True)
    except Exception:
        import traceback
        _log("set_active_window FAILED:\n" + traceback.format_exc())
