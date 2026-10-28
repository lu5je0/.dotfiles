"""A btop-inspired curses dashboard with dense, two-sample braille graphs."""

import curses
import locale
import math
import queue
import time

from .model import Tracker, format_bytes, format_rate


HIDDEN_INTERFACES = frozenset(("sit0", "lo"))

# Xterm-256: subdued blue frames, mint download, lilac upload.
PALETTE = {
    1: (60, -1), 2: (86, -1), 3: (147, -1), 4: (222, -1),
    5: (203, -1), 6: (253, -1), 7: (103, -1), 8: (150, -1),
    9: (230, 24), 10: (238, -1),
    **{16 + i: (color, -1) for i, color in enumerate((23, 29, 30, 36, 43, 50))},
    **{24 + i: (color, -1) for i, color in enumerate((60, 61, 62, 98, 140, 183))},
}


def graph_scale(values):
    """Rounded scale steps avoid rescaling on every tiny fluctuation."""
    peak = max(max(values, default=0), 1)
    unit = 1024 ** max(0, int(math.log(peak, 1024)))
    for step in (1, 2, 5, 10, 20, 50, 100, 200, 500, 1024):
        if step * unit >= peak * 1.05:
            return max(1024, step * unit)
    return max(1024, 2048 * unit)


def braille_graph(values, width, height, maximum, inverted=False):
    """Two samples per cell, four vertical pixels, filled towards the center."""
    if width <= 0 or height <= 0:
        return []
    values = list(values)[-width * 2:]
    values = [0] * (width * 2 - len(values)) + values
    levels = [max(0, min(height * 4, round(value / max(maximum, 1) * height * 4))) for value in values]
    dots = ((1, 2, 4, 64), (8, 16, 32, 128))
    lines = []
    for row in range(height):
        line = []
        for column in range(width):
            mask = 0
            for side in (0, 1):
                level = levels[column * 2 + side]
                for pixel in range(4):
                    position = row * 4 + pixel
                    filled = position < level if inverted else position >= height * 4 - level
                    if filled:
                        mask |= dots[side][pixel]
            line.append(chr(0x2800 + mask) if mask else " ")
        lines.append("".join(line))
    return lines


DIGITS = {
    "0": ("█▀█", "█ █", "█▄█"), "1": (" ▀█", "  █", "  █"),
    "2": ("▀▀█", "█▀▀", "█▄▄"), "3": ("▀▀█", " ▀█", "▄▄█"),
    "4": ("█ █", "▀▀█", "  █"), "5": ("█▀▀", "▀▀█", "▄▄█"),
    "6": ("█▀▀", "█▀█", "█▄█"), "7": ("▀▀█", "  █", "  █"),
    "8": ("█▀█", "█▀█", "█▄█"), "9": ("█▀█", "▀▀█", "▄▄█"),
    ".": (" ", " ", "▄"), "-": ("   ", "▀▀▀", "   "),
}


class Dashboard:
    def __init__(self, screen, source, args):
        self.screen, self.source, self.args = screen, source, args
        self.tracker = Tracker()
        self.selected = args.interface if args.interface not in HIDDEN_INTERFACES else None
        self.automatic = self.selected is None
        self.bits = args.bits
        self.paused = False
        self.help = False
        self.status = "Waiting for first sample..."
        self.error = ""
        self.last_sample = None
        self.connected = False
        self.unicode = "utf" in (locale.getpreferredencoding(False) or "").lower()
        self.styles = [0] * 32
        if curses.has_colors():
            curses.start_color()
            try:
                curses.use_default_colors()
                background = -1
            except curses.error:
                background = curses.COLOR_BLACK
            fallback = {1: 4, 2: 6, 3: 5, 4: 3, 5: 1, 6: 7, 7: 4, 8: 2, 9: 7, 10: 4}
            for index, (foreground, fill) in PALETTE.items():
                if curses.COLORS < 256:
                    foreground = fallback.get(index, 6 if index < 24 else 5)
                    fill = 4 if index == 9 else background
                else:
                    fill = background if fill == -1 else fill
                curses.init_pair(index, foreground, fill)
                self.styles[index] = curses.color_pair(index)
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        screen.timeout(100)

    def put(self, y, x, text, style=0, width=None):
        height, columns = self.screen.getmaxyx()
        if y < 0 or y >= height or x < 0 or x >= columns:
            return
        text = "".join(c if c.isprintable() else " " for c in str(text))
        limit = columns - x - (1 if y == height - 1 else 0)
        if width is not None:
            limit = min(limit, width)
        try:
            self.screen.addnstr(y, x, text, max(0, limit), style)
        except curses.error:
            pass

    def box(self, y, x, height, width, title, color=1, right=""):
        tl, tr, bl, br, horizontal, vertical = "╭╮╰╯─│" if self.unicode else "++++-|"
        style = self.styles[color]
        self.put(y, x, tl + horizontal * (width - 2) + tr, style)
        self.put(y + height - 1, x, bl + horizontal * (width - 2) + br, style)
        for row in range(y + 1, y + height - 1):
            self.put(row, x, vertical, style)
            self.put(row, x + width - 1, vertical, style)
        self.put(y, x + 2, f" {title} ", self.styles[8] | curses.A_BOLD, width - 4)
        if right and width > len(title) + len(right) + 9:
            self.put(y, x + width - len(right) - 4, f" {right} ", self.styles[7])

    def choose(self):
        names = self.names()
        if self.automatic:
            self.selected = next((name for name in self.tracker.wan if name in names), None)
            if not self.selected:
                self.selected = next((name for name in ("pppoe-wan", "wan", "eth1") if name in names), None)
            if not self.selected and names:
                self.selected = names[0]

    def names(self):
        return sorted((name for name in self.tracker.interfaces if name not in HIDDEN_INTERFACES),
                      key=lambda name: (name not in self.tracker.wan, name))

    def drain(self):
        for _ in range(512):
            try:
                kind, value = self.source.events.get_nowait()
            except queue.Empty:
                break
            if kind == "sample":
                self.tracker.update(value)
                self.last_sample = time.monotonic()
                self.connected = True
                self.error = ""
                self.status = "DEMO / simulated traffic" if self.args.demo else "LIVE / connected"
                self.choose()
            elif kind == "error":
                self.error = value
                self.connected = False
                self.tracker.disconnect()
            elif kind == "status":
                self.status = value

    def plot(self, y, x, height, width, values, color, inverted=False):
        maximum = graph_scale(values)
        for row in range(height):
            line = "".join("·" if self.unicode and column % 5 == 0 else " " for column in range(width))
            self.put(y + row, x, line, self.styles[10], width)
        if self.unicode:
            lines = braille_graph(values, width, height, maximum, inverted)
        else:
            data = list(values)[-width:]
            data = [0] * (width - len(data)) + data
            lines = []
            for row in range(height):
                threshold = (row if inverted else height - row - 1) / height
                lines.append("".join("#" if value / maximum > threshold else " " for value in data))
        for row, line in enumerate(lines):
            fraction = row / max(height - 1, 1) if inverted else 1 - row / max(height - 1, 1)
            style = self.styles[(16 if color == 2 else 24) + round(fraction * 5)]
            start = None
            for column in range(width + 1):
                filled = column < width and line[column] != " "
                if filled and start is None:
                    start = column
                elif not filled and start is not None:
                    self.put(y + row, x + start, line[start:column], style)
                    start = None
        return maximum

    def metric(self, y, x, height, width, item, direction, ready):
        color = 2 if direction == "rx" else 3
        is_wan = self.selected in self.tracker.wan
        label = ("download" if is_wan else "receive") if direction == "rx" else ("upload" if is_wan else "transmit")
        arrow = ("↓" if direction == "rx" else "↑") if self.unicode else ("v" if direction == "rx" else "^")
        self.put(y, x, f"{arrow} {label}", self.styles[color] | curses.A_BOLD, width)
        rate = format_rate(getattr(item, direction), self.bits) if ready and item else "--"
        peak = format_rate(getattr(item, "peak_" + direction), self.bits) if item else "--"
        total = format_bytes(getattr(item, "total_" + direction)) if item else "--"
        if height >= 7 and self.unicode:
            number, _, unit = rate.partition(" ")
            if number != "--":
                value = float(number.replace(",", ""))
                number = f"{value:.1f}" if value >= 100 else f"{value:.2f}"
            lines = [" ".join(DIGITS[char][row] for char in number) for row in range(3)]
            for row, line in enumerate(lines):
                self.put(y + 1 + row, x + max(0, width - len(line)), line,
                         self.styles[color] | curses.A_BOLD, width)
            self.put(y + 4, x + max(0, width - len(unit)), unit, self.styles[6])
            stats_y = y + 5
        else:
            self.put(y + 1, x, rate.rjust(width), self.styles[color] | curses.A_BOLD, width)
            stats_y = y + 2
        self.put(stats_y, x, "peak", self.styles[7])
        self.put(stats_y, x + max(5, width - len(peak)), peak, self.styles[6], width - 5)
        self.put(stats_y + 1, x, "total", self.styles[7])
        self.put(stats_y + 1, x + max(6, width - len(total)), total, self.styles[6], width - 6)

    def network(self, y, height, width, ready):
        interface = self.selected or "detecting..."
        mode = "auto" if self.automatic else "manual"
        self.box(y, 0, height, width, f"1 net ─ {interface}" if self.unicode else f"1 net - {interface}",
                 right=f"{mode} / {'bit' if self.bits else 'byte'}")
        sidebar = 30 if width >= 86 else 26
        divider = width - sidebar - 2
        self.put(y, divider, "┬" if self.unicode else "+", self.styles[1])
        self.put(y + height - 1, divider, "┴" if self.unicode else "+", self.styles[1])
        for row in range(y + 1, y + height - 1):
            self.put(row, divider, "│" if self.unicode else "|", self.styles[1])
        inner = height - 2
        down_height = inner // 2
        item = self.tracker.interfaces.get(self.selected)
        for offset, region_height, direction, color, inverted in (
            (0, down_height, "rx", 2, False),
            (down_height, inner - down_height, "tx", 3, True),
        ):
            row = y + 1 + offset
            values = getattr(item, "history_" + direction) if item else []
            plot_width = divider - 4
            maximum = graph_scale(values)
            arrow = ("↓" if direction == "rx" else "↑") if self.unicode else ("v" if direction == "rx" else "^")
            self.put(row, 2, f"{arrow} {direction}", self.styles[color] | curses.A_BOLD)
            axis = format_rate(maximum, self.bits)
            self.put(row, divider - len(axis) - 2, axis, self.styles[7])
            self.plot(row + 1, 2, region_height - 1, plot_width, values, color, inverted)
            self.metric(row, divider + 2, region_height, sidebar - 2, item, direction, ready)
        interval = self.tracker.interval or self.args.interval
        samples = len(item.history_rx) if item else 0
        visible = min(samples, (divider - 4) * (2 if self.unicode else 1))
        tag = f" ~{visible * interval:.0f}s history / {interval:.2g}s "
        self.put(y + height - 1, 3, tag, self.styles[7], divider - 5)

    def interfaces(self, y, height, width, ready):
        names = self.names()
        self.box(y, 0, height, width, "2 interfaces", right=f"{len(names)} devices")
        name_width = max(12, min(22, width - 46))
        rx_x = 4 + name_width
        tx_x = rx_x + 16
        self.put(y + 1, 3, "interface", self.styles[7])
        self.put(y + 1, rx_x, "↓ receive" if self.unicode else "receive", self.styles[2])
        self.put(y + 1, tx_x, "↑ transmit" if self.unicode else "transmit", self.styles[3])
        chart_x = tx_x + 17
        chart_width = width - chart_x - 3
        if chart_width >= 6:
            self.put(y + 1, chart_x, "trend", self.styles[7], chart_width)
        visible = max(0, height - 4)
        selected = names.index(self.selected) if self.selected in names else 0
        start = max(0, min(selected - visible // 2, len(names) - visible))
        for index, name in enumerate(names[start:start + visible]):
            row = y + 2 + index
            active = name == self.selected
            style = self.styles[9] | curses.A_BOLD if active else self.styles[6]
            if active:
                self.put(row, 1, " " * (width - 2), style, width - 2)
            self.put(row, 2, "›" if active and self.unicode else ">" if active else " ", style)
            suffix = " *" if name in self.tracker.wan else ""
            label = name[:name_width - len(suffix)] + suffix
            self.put(row, 4, label, style, name_width)
            value = self.tracker.interfaces[name]
            for column, direction, color in ((rx_x, "rx", 2), (tx_x, "tx", 3)):
                rate = format_rate(getattr(value, direction), self.bits) if ready else "--"
                self.put(row, column, rate.rjust(14), style if active else self.styles[color], 14)
            if chart_width >= 6:
                values = [rx + tx for rx, tx in zip(value.history_rx, value.history_tx)]
                spark = braille_graph(values, chart_width, 1, graph_scale(values))[0] if self.unicode else "." * min(len(values), chart_width)
                self.put(row, chart_x, spark, style if active else self.styles[7], chart_width)
        self.put(y + height - 1, 3, " tab / ↑↓ select " if self.unicode else " tab / arrows select ", self.styles[7], width - 6)
        if not names:
            self.put(y + 3, 3, "Waiting for interfaces...", self.styles[7], width - 6)

    def link(self, y, x, height, width):
        self.box(y, x, height, width, "3 link")
        dot = "●" if self.unicode else "*"
        state = "demo" if self.args.demo else "connected" if self.connected else "connecting"
        self.put(y + 2, x + 3, f"{dot} {state}", self.styles[2 if self.connected else 4] | curses.A_BOLD, width - 6)
        age = f"{time.monotonic() - self.last_sample:.1f}s ago" if self.last_sample else "waiting"
        seconds = int(self.tracker.elapsed)
        elapsed = f"{seconds // 3600:02}:{seconds // 60 % 60:02}:{seconds % 60:02}"
        rows = [("sample", age), ("session", elapsed),
                ("WAN", "confirmed" if self.selected in self.tracker.wan else "unconfirmed"),
                ("mode", "auto" if self.automatic else "manual"),
                ("transport", "local" if self.args.local else "demo" if self.args.demo else "SSH")]
        for offset, (label, value) in enumerate(rows):
            if offset + 4 >= height - 1:
                break
            self.put(y + 4 + offset, x + 3, label, self.styles[7])
            self.put(y + 4 + offset, x + width - len(value) - 3, value, self.styles[6], width - 12)

    def draw(self):
        self.screen.erase()
        height, width = self.screen.getmaxyx()
        if width < 68 or height < 23:
            self.put(0, 0, "q-openwrt - enlarge terminal to at least 68 x 23", self.styles[4])
            self.put(2, 0, f"Current size: {width} x {height} | q: quit")
            self.screen.refresh()
            return
        self.put(0, 2, "q-", self.styles[7] | curses.A_BOLD)
        self.put(0, 4, "openwrt", self.styles[2] | curses.A_BOLD)
        host = "demo / simulated traffic" if self.args.demo else "local" if self.args.local else self.args.host
        self.put(0, 14, host, self.styles[7], width - 42)
        if self.paused:
            badge, color = "PAUSED", 4
        elif self.args.demo:
            badge, color = "DEMO", 4
        else:
            badge, color = ("LIVE", 2) if self.connected else ("WAIT", 4)
        self.put(0, width - 24, badge, self.styles[color] | curses.A_BOLD)
        self.put(0, width - 10, time.strftime("%H:%M:%S"), self.styles[6])
        stale = self.last_sample is None or time.monotonic() - self.last_sample > max(3, self.args.interval * 3)
        ready = self.connected and not stale and self.tracker.interval is not None
        network_height = max(12, min(height - 9, round((height - 4) * 0.60)))
        self.network(2, network_height, width, ready)
        bottom_y = 2 + network_height
        bottom_height = height - bottom_y - 2
        if width >= 100:
            table_width = max(66, round(width * 0.68))
            self.interfaces(bottom_y, bottom_height, table_width, ready)
            self.link(bottom_y, table_width, bottom_height, width - table_width)
        else:
            self.interfaces(bottom_y, bottom_height, width, ready)
        status, color = "", 7
        if self.error:
            status, color = self.error, 5
        elif self.selected and self.selected not in self.tracker.interfaces:
            status, color = f"Interface {self.selected!r} unavailable; Tab: switch / a: auto", 4
        elif self.paused:
            status, color = "DISPLAY PAUSED / collection continues", 4
        elif self.selected and self.selected not in self.tracker.wan:
            status = "WAN unconfirmed / RX and TX are relative to this interface"
        elif not self.connected:
            status, color = self.status, 4
        self.put(height - 2, 2, status, self.styles[color], width - 4)
        keys = [("q", "quit"), ("tab", "interface"), ("b", "units"), ("p", "pause"), ("r", "reset"), ("a", "auto"), ("?", "help")]
        column = 2
        for key, label in keys:
            self.put(height - 1, column, key, self.styles[8] | curses.A_BOLD)
            self.put(height - 1, column + len(key) + 1, label, self.styles[7])
            column += len(key) + len(label) + 3
        if self.help:
            self.draw_help(height, width)
        self.screen.refresh()

    def draw_help(self, height, width):
        lines = [
            "Tab / Down / j       Next interface",
            "Shift-Tab / Up / k   Previous interface",
            "a                    Auto-select WAN",
            "b                    B/s (1024) / bit/s (1000)",
            "p / Space            Pause display; keep sampling",
            "r                    Reset totals, peaks and history",
            "q / Esc              Quit     ? / h   Close help",
            "",
            "WAN RX = download; WAN TX = upload.",
            "LAN bridge directions are reversed.",
            "Parent and child interfaces are never summed.",
            "Totals cover successfully sampled session traffic.",
            "Password expired / connection lost? Restart to log in.",
        ]
        pane_width, pane_height = min(62, width - 4), len(lines) + 4
        y, x = (height - pane_height) // 2, (width - pane_width) // 2
        for row in range(pane_height):
            self.put(y + row, x, " " * pane_width)
        self.box(y, x, pane_height, pane_width, "HELP / key bindings")
        for row, line in enumerate(lines):
            self.put(y + 2 + row, x + 3, line, self.styles[6], pane_width - 6)

    def run(self):
        while True:
            self.drain()
            if not self.paused or self.help:
                self.draw()
            try:
                key = self.screen.get_wch()
            except curses.error:
                continue
            if key in ("q", "Q", "\x1b"):
                return
            if key in ("?", "h"):
                self.help = not self.help
                self.draw()
            elif key in ("p", " "):
                self.paused = not self.paused
                self.draw()
            elif key == "b":
                self.bits = not self.bits
                self.draw()
            elif key == "r":
                self.tracker.reset()
                self.draw()
            elif key == "a":
                self.automatic = True
                self.choose()
                self.draw()
            elif key in ("\t", curses.KEY_DOWN, "j", curses.KEY_UP, curses.KEY_BTAB, "k"):
                names = self.names()
                if names:
                    index = names.index(self.selected) if self.selected in names else -1
                    step = -1 if key in (curses.KEY_UP, curses.KEY_BTAB, "k") else 1
                    self.selected = names[(index + step) % len(names)]
                    self.automatic = False
                    self.draw()
            elif key == curses.KEY_RESIZE:
                self.draw()


def run(source, args):
    try:
        locale.setlocale(locale.LC_ALL, "")
        curses.wrapper(lambda screen: Dashboard(screen, source, args).run())
    except (curses.error, locale.Error) as error:
        raise RuntimeError(f"终端初始化失败，请检查 TERM、locale 和终端颜色支持：{error}") from error
