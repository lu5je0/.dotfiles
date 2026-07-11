#!/usr/bin/env python3
"""Shared TUI core for the wezterm/kitty tab picker (tmux choose-tree style).

Terminal-agnostic: renders a top list of tabs and a bottom split-layout preview
of the selected tab's panes/windows, using raw ANSI so native truecolor is
preserved. Both the wezterm script and the kitty kitten import this module and
feed it a common `items` structure:

  item = {
    tab_id, active (bool), name, cwd, active_pane_id,
    tw, th,                       # tab total width/height in cells
    panes: [ {pane_id,left,top,width,height,is_active,preview}, ... ],
  }

pick(items, on_enter, on_exit) enters the alt screen, runs the loop, and
returns the selected item (or None on cancel).
"""

import os
import re
import select
import sys
import termios
import tty
import unicodedata

# ---- ANSI helpers -------------------------------------------------------
ESC = "\x1b"
CSI = ESC + "["
ALT_SCREEN_ON = CSI + "?1049h"
ALT_SCREEN_OFF = CSI + "?1049l"
HIDE_CUR = CSI + "?25l"
SHOW_CUR = CSI + "?25h"
CLEAR = CSI + "2J"
RESET = CSI + "0m"

# strip sequences that would move the cursor / clear screen inside preview,
# but keep SGR (color/style) sequences intact so truecolor passes through.
_NON_SGR_CSI = re.compile(r"\x1b\[[0-9;:?]*[A-LN-Za-ln-z]")  # CSI except 'm'/'M'
_OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
_CHARSET = re.compile(r"\x1b[()*+][A-Za-z0-9]")
_SINGLE = re.compile(r"\x1b[=>Mc78]")
_SGR_RE = re.compile(r"\x1b\[[0-9;:]*m")


def sanitize_preview(line):
    """Drop cursor/erase/charset escapes, keep SGR color sequences."""
    line = _OSC.sub("", line)
    line = _CHARSET.sub("", line)
    line = _NON_SGR_CSI.sub("", line)
    line = _SINGLE.sub("", line)
    return line


def cell_width(s):
    w = 0
    for ch in s:
        if ch == "\x1b":
            continue
        ea = unicodedata.east_asian_width(ch)
        w += 2 if ea in ("W", "F") else 1
    return w


def clip_visible(s, max_cols):
    """Clip a string containing SGR escapes to max_cols visible columns."""
    out = []
    col = 0
    i = 0
    n = len(s)
    while i < n:
        m = _SGR_RE.match(s, i)
        if m:
            out.append(m.group(0))
            i = m.end()
            continue
        ch = s[i]
        cw = 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        if col + cw > max_cols:
            break
        out.append(ch)
        col += cw
        i += 1
    return "".join(out), col


def active_bg_sgr(s):
    """Return the SGR sequence reproducing the bg color in effect at end of s."""
    bg = None  # None = default; else a params list for the SGR
    for m in _SGR_RE.finditer(s):
        codes = m.group(0)[2:-1].replace(":", ";")
        parts = [int(x) for x in codes.split(";") if x != ""] or [0]
        i = 0
        while i < len(parts):
            c = parts[i]
            if c == 0 or c == 49:
                bg = None
            elif 40 <= c <= 47 or 100 <= c <= 107:
                bg = [c]
            elif c == 48 and i + 1 < len(parts):
                if parts[i + 1] == 5 and i + 2 < len(parts):
                    bg = [48, 5, parts[i + 2]]
                    i += 2
                elif parts[i + 1] == 2 and i + 4 < len(parts):
                    bg = [48, 2, parts[i + 2], parts[i + 3], parts[i + 4]]
                    i += 4
            i += 1
    if bg is None:
        return ""
    return CSI + ";".join(str(x) for x in bg) + "m"


# ---- data ---------------------------------------------------------------
def label_left(it):
    mark = "*" if it["active"] else " "
    return f"{mark} {it['tab_id']}  {it['name']}"


def label_right(it):
    return it["cwd"]


def label(it):
    return f"{label_left(it)}  {label_right(it)}"


_STATE = {"items": None, "raw": {}}


def _has_visible(line):
    stripped = _SGR_RE.sub("", line)
    stripped = _NON_SGR_CSI.sub("", stripped)
    stripped = _OSC.sub("", stripped)
    stripped = _CHARSET.sub("", stripped)
    stripped = _SINGLE.sub("", stripped)
    return bool(stripped.strip())


def _trim_trailing_blank(lines):
    end = len(lines)
    while end > 0 and not _has_visible(lines[end - 1]):
        end -= 1
    return lines[:end]


def set_items(items):
    items = sorted(items, key=lambda x: x["tab_id"])
    _STATE["items"] = items
    for it in items:
        for p in it.get("panes", []):
            lines = (p.get("preview") or "").splitlines()
            _STATE["raw"][p["pane_id"]] = _trim_trailing_blank(lines)


def get_items():
    return _STATE["items"]


def get_raw(pid):
    return _STATE["raw"].get(pid)


# ---- input --------------------------------------------------------------
def read_key(timeout):
    r, _, _ = select.select([sys.stdin], [], [], timeout)
    if not r:
        return None
    # Read straight from the raw fd: sys.stdin.read() buffers, which would
    # swallow the "[A" tail of an arrow sequence and leave a bare ESC behind
    # (making arrow keys look like a quit). os.read returns whatever the
    # terminal delivered in one go, e.g. b"\x1b[A" or b"\x1bOA".
    try:
        data = os.read(sys.stdin.fileno(), 32)
    except OSError:
        return None
    if not data:
        return None
    return data.decode("utf-8", "ignore")


# ---- fuzzy --------------------------------------------------------------
def fuzzy(items, query):
    if not query:
        return items
    q = query.lower()
    res = []
    for it in items:
        hay = label(it).lower()
        i = 0
        for ch in q:
            i = hay.find(ch, i)
            if i < 0:
                break
            i += 1
        else:
            res.append(it)
    return res


# ---- render -------------------------------------------------------------
# tmux choose-tree aligned colors
BORDER = CSI + "38;5;244m"            # dim gray border
TITLE = CSI + "1;38;5;255m"           # bold white title
INDEX = CSI + "38;5;179m"             # yellow (n) prefix
SEL_BAR = CSI + "48;2;108;101;133;38;2;235;235;235m"  # muted purple bg, light fg
CONFIRM = CSI + "48;5;179;38;5;16m"   # yellow bg, dark fg (tmux confirm bar)


def run(out, on_close=None):
    query = ""
    filtering = False
    confirming = None
    parse_cache = {}

    all_items = get_items()
    idx = next((i for i, it in enumerate(all_items) if it.get("active")), 0)

    while True:
        items = fuzzy(all_items, query)
        if idx >= len(items):
            idx = max(0, len(items) - 1)

        cols, rows = os.get_terminal_size(out.fileno())
        box_h = max(6, rows // 2)
        list_h = rows - box_h

        buf = [HIDE_CUR, CLEAR, CSI + "1;1H"]

        # ---- list ----
        top = 0
        if idx >= list_h:
            top = idx - list_h + 1
        for row in range(list_h):
            real = top + row
            buf.append(CSI + f"{row + 1};1H" + RESET)
            if real >= len(items):
                continue
            it = items[real]
            left = f"({real}) {label_left(it)}"
            right = label_right(it)
            lw = cell_width(left)
            rw = cell_width(right)
            gap = cols - lw - rw
            if gap < 1:
                left_c, lcw = clip_visible(left, cols)
                right = ""
                gap = max(0, cols - lcw)
                left = left_c
            if real == idx:
                line = left + " " * gap + right
                _, w = clip_visible(line, cols)
                buf.append(SEL_BAR + line + " " * max(0, cols - w) + RESET)
            else:
                buf.append(
                    INDEX + f"({real})" + RESET
                    + left[len(f"({real})"):] + " " * gap + right
                )

        # ---- preview box top border with title ----
        tl, tr, bl, br, hz, vt = "┌", "┐", "└", "┘", "─", "│"
        title_color = TITLE
        title = f"{idx} (sort: index)"
        if filtering:
            title = f"{idx} (sort: index)  /{query}"
        title = title[: max(0, cols - 6)]
        lead = tl + hz
        title_seg = " " + title_color + title + RESET + BORDER + " "
        used = 2 + 1 + len(title) + 1
        fill = max(0, cols - 1 - used)
        buf.append(
            CSI + f"{list_h + 1};1H" + BORDER + lead + title_seg + hz * fill + tr + RESET
        )

        # ---- preview: split layout by pane geometry ----
        inner_w = cols - 2
        inner_h = box_h - 2
        base_row = list_h + 2
        base_col = 2

        panes = items[idx].get("panes", []) if items else []
        tw = (items[idx].get("tw") or 1) if items else 1
        th = (items[idx].get("th") or 1) if items else 1

        def scale_x(x):
            return round(x * inner_w / tw)

        def scale_y(y):
            return round(y * inner_h / th)

        rects = []
        for p in panes:
            x0 = scale_x(p["left"])
            x1 = scale_x(p["left"] + p["width"])
            y0 = scale_y(p["top"])
            y1 = scale_y(p["top"] + p["height"])
            rects.append((p, x0, y0, max(1, x1 - x0), max(1, y1 - y0)))

        for i in range(inner_h):
            y = base_row + i
            buf.append(CSI + f"{y};1H" + BORDER + vt + RESET)
            buf.append(CSI + f"{y};{cols}H" + BORDER + vt + RESET)

        for p, rx, ry, rw, rh in rects:
            r = get_raw(p["pane_id"]) or []
            ck = (p["pane_id"], rw, rh)
            if ck not in parse_cache:
                parse_cache[ck] = [sanitize_preview(x) for x in r[:rh]]
            plines = parse_cache[ck]
            for li in range(rh):
                y = base_row + ry + li
                if y >= base_row + inner_h:
                    break
                content = plines[li] if li < len(plines) else ""
                vis, wid = clip_visible(content, rw)
                bg = active_bg_sgr(vis)
                pad = ""
                if bg:
                    pad = bg + " " * max(0, rw - wid) + RESET
                buf.append(CSI + f"{y};{base_col + rx}H" + vis + pad + RESET)

        seen_x = set()
        for p, rx, ry, rw, rh in rects:
            if rx > 0 and rx not in seen_x:
                seen_x.add(rx)
                for li in range(rh):
                    y = base_row + ry + li
                    if y >= base_row + inner_h:
                        break
                    buf.append(
                        CSI + f"{y};{base_col + rx - 1}H" + BORDER + vt + RESET
                    )

        buf.append(
            CSI + f"{list_h + box_h};1H" + BORDER + bl + hz * (cols - 2) + br + RESET
        )

        # ---- bottom status bar: tmux-style kill confirmation prompt ----
        if confirming is not None:
            prompt = f"kill window {confirming['tab_id']} ({confirming['name']})? (y/n)"
            prompt, pw = clip_visible(prompt, cols)
            bar = prompt + " " * max(0, cols - pw)
            buf.append(CSI + f"{rows};1H" + CONFIRM + bar + RESET)

        out.write("".join(buf))
        out.flush()

        key = read_key(0.15)
        if key is None:
            continue

        if confirming is not None:
            if key in ("y", "Y"):
                victim = confirming
                confirming = None
                if on_close:
                    try:
                        on_close(victim)
                    except Exception:
                        pass
                if victim in all_items:
                    all_items.remove(victim)
                if not all_items:
                    return None
                if idx >= len(all_items):
                    idx = max(0, len(all_items) - 1)
            else:
                confirming = None
            continue

        if filtering:
            if key == "\x1b":
                filtering = False
                query = ""
            elif key in ("\r", "\n"):
                filtering = False
            elif key in ("\x7f", "\b"):
                query = query[:-1]
            elif key in (CSI + "B", "\x1b[B", "\x1bOB"):
                idx = min(len(items) - 1, idx + 1)
            elif key in (CSI + "A", "\x1b[A", "\x1bOA"):
                idx = max(0, idx - 1)
            elif len(key) == 1 and key.isprintable():
                query += key
                idx = 0
            continue

        if key.isdigit():
            n = int(key)
            if n < len(items):
                return items[n]
        elif key in ("q", "\x1b"):
            return None
        elif key in ("j", CSI + "B", "\x1b[B", "\x1bOB"):
            idx = min(len(items) - 1, idx + 1)
        elif key in ("k", CSI + "A", "\x1b[A", "\x1bOA"):
            idx = max(0, idx - 1)
        elif key == "g":
            idx = 0
        elif key == "G":
            idx = len(items) - 1
        elif key == "x":
            if items:
                confirming = items[idx]
        elif key == "/":
            filtering = True
            query = ""
        elif key in ("\r", "\n"):
            if items:
                return items[idx]
            return None


def pick(items, on_enter=None, on_exit=None, stream=None, on_close=None):
    """Full picker entry: set raw mode + alt screen, run loop, restore.

    on_enter/on_exit are optional callbacks (e.g. IME switching).
    on_close(item) is an optional callback invoked when the user confirms
    killing a tab (x then y); the item is then dropped from the list.
    stream is the tty stream to draw on (defaults to sys.stdout).
    Returns the selected item dict, or None if cancelled.
    """
    if not items:
        return None
    set_items(items)
    out = stream or sys.stdout
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    selected = None
    try:
        tty.setraw(fd)
        out.write(ALT_SCREEN_ON)
        out.flush()
        if on_enter:
            on_enter()
        selected = run(out, on_close=on_close)
    finally:
        if on_exit:
            on_exit()
        out.write(SHOW_CUR + RESET + ALT_SCREEN_OFF)
        out.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return selected
