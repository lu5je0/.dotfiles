#!/usr/bin/env python3
"""wezterm tab picker: thin wrapper around tabpick_core.

Spawned in a new tab by the wezterm keybinding, which passes the tab/pane
tree (with inline previews) as a JSON argv. Selection is reported back to
wezterm via the 'tabpick_select' user var; wezterm activates the target pane
and closes this picker tab natively.
"""

import base64
import json
import os
import sys

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shared", "tui-pick"),
)
import tabpick_core  # noqa: E402

ESC = "\x1b"


def set_user_var(name, value):
    b64 = base64.b64encode(str(value).encode()).decode()
    sys.stdout.write(f"{ESC}]1337;SetUserVar={name}={b64}\x07")
    sys.stdout.flush()


def ime(method):
    req = json.dumps({"id": 1, "module": "ime", "method": method, "params": {}})
    set_user_var("tui_bridge", req)


def main():
    if len(sys.argv) <= 1:
        return
    try:
        items = json.loads(sys.argv[1])
    except Exception:
        return
    if not items:
        return

    target = tabpick_core.pick(
        items,
        on_enter=lambda: ime("normal"),
        on_exit=lambda: ime("insert"),
    )

    if target:
        set_user_var("tabpick_select", target["active_pane_id"])
    else:
        origin = next((it for it in items if it.get("active")), None)
        set_user_var(
            "tabpick_select", origin["active_pane_id"] if origin else "cancel"
        )


if __name__ == "__main__":
    main()
