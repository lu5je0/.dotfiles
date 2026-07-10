#!/usr/bin/env python3
"""kitty in-process data collector for the tab picker.

Runs ONLY handle_result (no_ui), i.e. inside the kitty process with access to
boss. It walks every tab/window of the focused OS window, reading each window's
pixel geometry and colored text directly (no `kitten @` subprocesses), builds
the shared `items` structure, and writes it to a temp JSON file that the UI
kitten (tabpick.py) then reads. This mirrors wezterm's zero-subprocess design.
"""

import json
import os
import tempfile

from kittens.tui.handler import result_handler  # type: ignore

DATA_PATH = os.path.join(tempfile.gettempdir(), "tabpick_items.json")


def main(args):
    return None


def _windows_of(tab):
    # Tab is iterable over its windows
    try:
        return list(tab)
    except Exception:
        return list(getattr(tab, "windows", []) or [])


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    osw_id = None
    try:
        from kitty.fast_data_types import current_focused_os_window_id
        osw_id = current_focused_os_window_id()
    except Exception:
        osw_id = None

    tm = boss.os_window_map.get(osw_id) if osw_id else None
    if tm is None:
        tm = next(iter(boss.os_window_map.values()), None)
    if tm is None:
        _write({"items": [], "restore": None})
        return

    active_tab = tm.active_tab
    items = []
    for ti, tab in enumerate(tm):
        wins = _windows_of(tab)
        if not wins:
            continue
        # pixel geometry per window
        geoms = {}
        minx = miny = 10 ** 9
        maxx = maxy = 0
        for w in wins:
            g = w.geometry
            geoms[w.id] = (g.left, g.top, g.right, g.bottom)
            minx = min(minx, g.left)
            miny = min(miny, g.top)
            maxx = max(maxx, g.right)
            maxy = max(maxy, g.bottom)
        tw = max(1, maxx - minx)
        th = max(1, maxy - miny)

        panes = []
        active_pane_id = None
        active_cwd = ""
        active_win = tab.active_window
        active_name = tab.title or ""
        for w in wins:
            gl, gt, gr, gb = geoms[w.id]
            try:
                txt = w.as_text(as_ansi=True)
            except Exception:
                txt = ""
            focused = active_win is not None and w.id == active_win.id
            panes.append({
                "pane_id": w.id,
                "left": gl - minx,
                "top": gt - miny,
                "width": max(1, gr - gl),
                "height": max(1, gb - gt),
                "is_active": focused,
                "preview": txt,
            })
            if focused:
                active_pane_id = w.id
                active_cwd = w.cwd_of_child or ""
        if active_pane_id is None:
            active_pane_id = wins[0].id
            active_cwd = wins[0].cwd_of_child or ""
        items.append({
            "tab_id": ti,
            "active": tab is active_tab,
            "name": active_name,
            "cwd": active_cwd,
            "active_pane_id": active_pane_id,
            "tw": tw,
            "th": th,
            "panes": panes,
        })

    # If the active tab is split, zoom it to a stack layout so the overlay
    # picker covers the whole tab (not just one split). Record the original
    # layout so the UI's handle_result can restore it afterwards.
    restore = None
    try:
        if active_tab is not None and len(_windows_of(active_tab)) > 1:
            orig = getattr(active_tab, "_current_layout_name", None)
            if orig and orig != "stack":
                active_tab.goto_layout("stack")
                restore = {"tab_id": active_tab.id, "layout": orig}
    except Exception:
        restore = None

    _write({"items": items, "restore": restore})


def _write(payload):
    try:
        with open(DATA_PATH, "w") as f:
            json.dump(payload, f)
    except Exception:
        pass
