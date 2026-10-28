#!/usr/bin/env python3
"""Render the real dashboard with deterministic demo samples (dev-only Pillow)."""

import argparse
import curses
import math
from pathlib import Path
import random
import subprocess
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from q_openwrt.app import parse_args
from q_openwrt.model import Counter, Sample
from q_openwrt.source import Source
from q_openwrt.ui import Dashboard, PALETTE


class PreviewScreen:
    def __init__(self, height, width):
        self.height, self.width = height, width
        self.erase()

    def erase(self):
        self.cells = [[(" ", 0) for _ in range(self.width)] for _ in range(self.height)]

    def getmaxyx(self):
        return self.height, self.width

    def addnstr(self, y, x, text, limit, style):
        for index, char in enumerate(text[:limit]):
            self.cells[y][x + index] = (char, style)

    def timeout(self, value):
        pass

    def refresh(self):
        pass


def xterm_color(index):
    if index == -1:
        return "#11151f"
    if index >= 232:
        value = 8 + 10 * (index - 232)
        return (value,) * 3
    if index >= 16:
        index -= 16
        levels = (0, 95, 135, 175, 215, 255)
        return levels[index // 36], levels[index // 6 % 6], levels[index % 6]
    return "#dddddd"


def make_preview(height, width):
    screen = PreviewScreen(height, width)
    with patch.object(curses, "has_colors", return_value=False), patch.object(curses, "curs_set"):
        dashboard = Dashboard(screen, Source(None, 1, True), parse_args(["--demo"]))
    dashboard.unicode = True
    dashboard.styles = [index << 8 for index in range(32)]
    rng = random.Random(7)
    counters = {name: Counter(0, 0) for name in ("pppoe-wan", "eth0", "eth1", "br-lan", "lo", "sit0")}
    for tick in range(240):
        wave = math.sin(tick / 13)
        pulse = max(0, math.sin(tick / 6)) ** 3
        rx = (7.2 + 4 * wave + 4.8 * pulse + rng.random() * 0.9) * 1024**2
        tx = (0.75 + 0.4 * math.sin(tick / 11) + 0.8 * pulse + rng.random() * 0.25) * 1024**2
        for name, previous in counters.items():
            receive, transmit = (tx, rx) if name in ("br-lan", "eth0") else (rx, tx)
            factor = 0 if name in ("lo", "sit0") else 1.03 if name == "eth1" else 1
            counters[name] = Counter(previous.rx + int(receive * factor), previous.tx + int(transmit * factor))
        dashboard.source.events.put(("sample", Sample(1000 + tick, dict(counters), ("pppoe-wan",))))
    dashboard.drain()
    with patch("q_openwrt.ui.time.strftime", return_value="23:08:26"):
        dashboard.draw()
    return screen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=110)
    parser.add_argument("--height", type=int, default=34)
    parser.add_argument("--output", type=Path, default=Path("assets/preview.png"))
    args = parser.parse_args()
    from PIL import Image, ImageDraw, ImageFont

    font_path = subprocess.check_output(
        ["fc-match", "-f", "%{file}", "JetBrainsMono Nerd Font:style=Regular"], text=True
    )
    font = ImageFont.truetype(font_path, 20)
    bold_path = subprocess.check_output(
        ["fc-match", "-f", "%{file}", "JetBrainsMono Nerd Font:style=Bold"], text=True
    )
    bold = ImageFont.truetype(bold_path, 20)
    cell_width, cell_height, padding = round(font.getlength("M")), 26, 20
    image = Image.new("RGB", (args.width * cell_width + padding * 2, args.height * cell_height + padding * 2), "#11151f")
    draw = ImageDraw.Draw(image)
    screen = make_preview(args.height, args.width)
    for row, line in enumerate(screen.cells):
        for column, (char, style) in enumerate(line):
            index = (style >> 8) & 255
            foreground, background = PALETTE.get(index, (253, -1))
            x, y = padding + column * cell_width, padding + row * cell_height
            if background != -1:
                draw.rectangle((x, y, x + cell_width - 1, y + cell_height - 1), fill=xterm_color(background))
            # Like a terminal's fallback font, cover braille when the selected
            # programming font has no U+2800 glyphs. Keep its actual dot mask.
            if 0x2800 <= ord(char) <= 0x28ff:
                mask = ord(char) - 0x2800
                for side, dots in enumerate(((1, 2, 4, 64), (8, 16, 32, 128))):
                    for pixel, bit in enumerate(dots):
                        if mask & bit:
                            cx = x + (0.25 if side == 0 else 0.75) * cell_width
                            cy = y + (pixel + 0.5) * cell_height / 4
                            draw.ellipse((cx - 1, cy - 1, cx + 1, cy + 1), fill=xterm_color(foreground))
                continue
            selected_font = bold if style & curses.A_BOLD else font
            draw.text((x, y + 21), char, font=selected_font, fill=xterm_color(foreground), anchor="ls")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
