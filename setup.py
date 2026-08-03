#!/usr/bin/env python3
"""Dotfiles installer: pick modules in a TUI, then link/run them."""

import json
import os
import platform
import select
import shutil
import signal
import subprocess
import sys
import termios
import textwrap
import tty
from pathlib import Path

DOTFILES_DIR = Path(os.environ.get("DOTFILES_DIR") or Path(__file__).resolve().parent)
HOME = Path.home()


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


# Only run from ~/.dotfiles (or a Windows-side clone on WSL) to avoid linking a stray clone
if DOTFILES_DIR != HOME / ".dotfiles" and DOTFILES_DIR.parts[:3] != ("/", "mnt", "c"):
    die(f"setup.py must be run from ~/.dotfiles (current: {DOTFILES_DIR})")
if DOTFILES_DIR.name != ".dotfiles":
    die(f"setup.py must be run from a .dotfiles checkout (current: {DOTFILES_DIR})")


def detect_tags():
    """Platform tags, most specific first, matched against a module's `os` list."""
    if (
        os.environ.get("TERMUX_VERSION")
        or "com.termux" in os.environ.get("PREFIX", "")
        or Path("/data/data/com.termux").is_dir()
    ):
        return ["termux"]
    if platform.system() == "Darwin":
        return ["mac"]
    uname = platform.uname()
    if "wsl" in f"{uname.release} {uname.version}".lower():
        return ["wsl", "linux"]
    return ["linux"]


TAGS = detect_tags()
IS_WIN_MODE = "wsl" in TAGS and DOTFILES_DIR.parts[:3] == ("/", "mnt", "c")
if IS_WIN_MODE:
    TAGS = ["win"]  # win-side modules only; unix modules need a real unix checkout
MODULE_DIR = DOTFILES_DIR / "scripts/setup.d/modules"


def windows_home():
    """Windows %USERPROFILE% as a WSL path (unix-mode modules touching the Windows side)."""
    out = subprocess.run(
        ["/mnt/c/Windows/System32/cmd.exe", "/c", "echo %USERPROFILE%"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not out:
        return ""
    return subprocess.run(["wslpath", out], capture_output=True, text=True).stdout.strip()


os.environ["DOTFILES_DIR"] = str(DOTFILES_DIR)
if IS_WIN_MODE:
    os.environ["WIN_HOME"] = str(DOTFILES_DIR.parent)

if platform.system() == "Darwin":
    (HOME / ".mac").touch(exist_ok=True)

if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
    RESET, BOLD, DIM = "\033[0m", "\033[1m", "\033[2m"
    CYAN, GREEN, YELLOW, RED = "\033[36m", "\033[32m", "\033[33m", "\033[31m"
    CURSOR_BG = "\033[48;5;237m"
    KEEP_BG = "\033[22;39m"  # clears bold/dim + fg but keeps the cursorline background
else:
    RESET = BOLD = DIM = CYAN = GREEN = YELLOW = RED = CURSOR_BG = KEEP_BG = ""


def expand(path):
    path = str(path)
    if "$WIN_HOME" in path and not os.environ.get("WIN_HOME"):
        os.environ["WIN_HOME"] = windows_home()
    return Path(os.path.expandvars(path)).expanduser()


def shorten(path):
    text = str(path)
    home = str(HOME)
    return "~" + text[len(home) :] if text.startswith(home + os.sep) else text


def pick_by_tag(value):
    """A check may be a plain path, or a {tag: path} map resolved against this platform."""
    if not isinstance(value, dict):
        return value
    for tag in TAGS:
        if tag in value:
            return value[tag]
    return value.get("default")


class Module:
    def __init__(self, spec):
        self.name = spec.get("name") or die(f"module without a name: {spec}")
        self.script = spec.get("script")
        self.source = spec.get("source")
        self.target = spec.get("target")
        self.os_spec = spec.get("os") or []
        if IS_WIN_MODE:
            self.supported = "win" in self.os_spec
        else:
            self.supported = not self.os_spec or any(t in TAGS for t in self.os_spec)
        self.selected = False
        self.status = ""

        if self.script:
            self.desc = spec.get("desc") or self.script
            self.action = spec.get("action") or "run"
        elif self.source and self.target:
            self.desc = spec.get("desc") or f"./{self.source} → {self.target}"
            self.action = spec.get("action") or "link"
        else:
            die(f"module {self.name!r} needs either `script` or `source`+`target`")

        self.target_path = expand(self.target) if self.target else None
        self.checks = []  # [(kind, Path)] where kind is "link" or "exists"
        if not self.supported:
            return
        if not self.script:
            self.checks = [("link", self.target_path)]
            return
        self.vars = {k: pick_by_tag(v) for k, v in (spec.get("vars") or {}).items()}
        for item in spec.get("checks") or []:
            item_os = item.get("os")
            if item_os and not any(t in TAGS for t in item_os):
                continue
            kind = "link" if "link" in item else "exists" if "exists" in item else None
            if not kind:
                die(f"module {self.name!r}: check item needs `link` or `exists`: {item}")
            self.checks.append((kind, self.resolve(item[kind])))

    def resolve(self, path):
        for name, value in self.vars.items():
            if value is None:
                die(f"module {self.name!r}: var {name!r} has no value for {'/'.join(TAGS)}")
            path = path.replace(f"${name}", value)
        return expand(path)

    @property
    def os_label(self):
        return "/".join(self.os_spec)

    def refresh_status(self):
        if not self.supported or not self.checks:
            self.status = ""
            return
        states = set()
        for kind, path in self.checks:
            if not path.exists() and not path.is_symlink():
                states.add("missing")
            elif kind == "exists":
                states.add("ok")
            elif path.is_symlink() and str(path.resolve()).startswith(str(DOTFILES_DIR.resolve())):
                states.add("ok")
            else:
                states.add("conflict")
        if "conflict" in states:
            self.status = "conflict"
        elif states == {"ok"}:
            self.status = "installed"
        else:
            self.status = ""

    def run(self):
        script = MODULE_DIR / self.script
        return subprocess.run(["bash", str(script)], cwd=DOTFILES_DIR).returncode

    def run_link(self):
        """Returns ("linked"|"created"|"occupied", detail)."""
        target = self.target_path
        if target.is_symlink() and str(target.resolve()).startswith(str(DOTFILES_DIR.resolve())):
            return "linked", ""
        if target.exists() or target.is_symlink():
            return "occupied", shorten(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(DOTFILES_DIR / self.source, target)
        return "created", shorten(target)


def load_modules():
    conf = MODULE_DIR / "modules.json"
    if not conf.is_file():
        die(f"No modules.json found in {MODULE_DIR}")
    try:
        specs = json.loads(conf.read_text())
    except json.JSONDecodeError as exc:
        die(f"{conf}: invalid JSON: {exc}")
    modules = [Module(spec) for spec in specs]
    for module in modules:
        module.refresh_status()
    return modules


MARK_ON = "◉"
MARK_OFF = "○"
MARK_BLOCKED = "×"
SEQUENCES = ("gg", ",vw")  # multi-key bindings; "," is the nvim leader used in this repo
PREFIXES = {seq[:i] for seq in SEQUENCES for i in range(1, len(seq))}
SEQUENCE_TIMEOUT = 1.0


def frame_size():
    size = shutil.get_terminal_size((100, 30))
    return size, max(24, min(size.columns - 1, 110))


def fit(text, width):
    if width <= 0:
        return ""
    return text if len(text) <= width else text[: width - 1] + "…"


class Picker:
    """Full-screen module picker. Unsupported modules sink to the bottom and can't be toggled."""

    def __init__(self, modules):
        self.modules = modules
        self.cursor = 0
        self.offset = 0
        self.query = ""
        self.searching = False
        self.name_width = max(len(m.name) for m in modules)
        self.action_width = max(len(m.action) for m in modules)
        self.status_width = len("● installed")
        self.last_size = None
        self.wrap = False
        self.visible = []
        self.update_filter()

    def update_filter(self):
        query = self.query.lower()
        matched = [m for m in self.modules if query in f"{m.name} {m.desc}".lower()]
        self.visible = [m for m in matched if m.supported] + [m for m in matched if not m.supported]

    def current(self):
        return self.visible[self.cursor] if self.visible else None

    def toggle(self):
        module = self.current()
        if module and module.supported:
            module.selected = not module.selected

    def move(self, delta):
        if self.visible:
            self.cursor = (self.cursor + delta) % len(self.visible)

    def jump(self, delta):
        if self.visible:
            self.cursor = max(0, min(len(self.visible) - 1, self.cursor + delta))

    def desc_chunks(self, module, desc_w):
        if not self.wrap:
            return [fit(module.desc, desc_w)]
        return textwrap.wrap(module.desc, desc_w) or [""]

    def rows(self, desc_w):
        """One tuple per screen line: ("divider", …) or ("module", index, chunk, is_continuation)."""
        out = []
        divided = False
        for idx, module in enumerate(self.visible):
            if not module.supported and not divided:
                out.append(("divider", -1, "", False))
                divided = True
            for n, chunk in enumerate(self.desc_chunks(module, desc_w)):
                out.append(("module", idx, chunk, n > 0))
        return out

    def columns(self, width):
        """Budget `4 gutter + name + 2 + action + 2 + desc + 2 + status` inside width."""
        ladder = (
            (self.status_width, self.action_width, 16),
            (1, self.action_width, 10),
            (1, 0, 8),
            (0, 0, 0),
        )
        for status_w, action_w, min_desc in ladder:
            fixed = 8 + status_w + (action_w + 2 if action_w else 0)
            name_w = min(self.name_width, max(6, (width - fixed) // 2))
            desc_w = width - fixed - name_w
            if desc_w >= min_desc:
                return name_w, action_w, desc_w, status_w

    def status_cell(self, module, status_w, dim, reset):
        if not module.supported:
            label = fit(module.os_label, status_w) if status_w > 1 else ""
            return label, f"{dim}{label}{reset}"
        if module.status == "installed":
            if status_w > 1:
                return "● installed", f"{GREEN}●{reset} {dim}installed{reset}"
            return "●", f"{GREEN}●{reset}"
        if module.status == "conflict":
            if status_w > 1:
                return "▲ conflict", f"{YELLOW}▲ conflict{reset}"
            return "▲", f"{YELLOW}▲{reset}"
        return "", ""

    def module_line(self, idx, chunk, continuation, layout):
        name_w, action_w, desc_w, status_w = layout
        module = self.visible[idx]
        focused = idx == self.cursor
        bg = CURSOR_BG if focused else ""
        reset = KEEP_BG if focused else RESET
        dim = "" if focused else DIM
        pointer = f"{BOLD}{CYAN}▌{reset}" if focused else " "
        indent = name_w + 4 + (action_w + 2 if action_w else 0)

        if continuation:
            pad = " " * (desc_w - len(chunk) + 2 + status_w)
            return f"{bg}{pointer} {' ' * indent}{dim}{chunk}{reset}{pad}{RESET}"

        plain_status, status = self.status_cell(module, status_w, dim, reset)
        if not module.supported:
            mark = f"{dim}{MARK_BLOCKED}{reset}"
        elif module.selected:
            mark = f"{GREEN}{MARK_ON}{reset}"
        else:
            mark = f"{dim}{MARK_OFF}{reset}"

        name = fit(module.name, name_w).ljust(name_w)
        if focused:
            name = f"{BOLD}{CYAN}{name}{reset}"
        elif not module.supported:
            name = f"{DIM}{name}{RESET}"

        action = ""
        if action_w:
            action = f"{dim}{fit(module.action, action_w).ljust(action_w)}{reset}  "

        pad = " " * (desc_w - len(chunk) + 2 + status_w - len(plain_status))
        return f"{bg}{pointer} {mark} {name}  {action}{dim}{chunk}{reset}{pad}{status}{RESET}"

    def divider_line(self, width):
        label = fit(f"unavailable on {'/'.join(TAGS)}", max(0, width - 6))
        dashes = max(0, width - 6 - len(label))
        return f"    {DIM}{label} {'─' * dashes}{RESET}"

    def body(self, height, width):
        if not self.visible:
            return [f"    {DIM}no module matches{RESET}"] + [""] * (height - 1)

        layout = self.columns(width)
        rows = self.rows(layout[2])
        focused = [i for i, row in enumerate(rows) if row[0] == "module" and row[1] == self.cursor]
        first, last = focused[0], focused[-1]
        reserved = 2 if len(rows) > height else 0
        for _ in range(2):
            inner = max(1, height - reserved)
            self.offset = min(first, max(last - inner + 1, self.offset))
            self.offset = max(0, min(self.offset, max(0, len(rows) - inner)))
            above = self.offset
            below = len(rows) - self.offset - inner
            reserved = (1 if above else 0) + (1 if below > 0 else 0)

        lines = [f"    {DIM}↑ {above} more{RESET}"] if above else []
        for kind, idx, chunk, continuation in rows[self.offset : self.offset + inner]:
            if kind == "divider":
                lines.append(self.divider_line(width))
            else:
                lines.append(self.module_line(idx, chunk, continuation, layout))
        if below > 0:
            lines.append(f"    {DIM}↓ {below} more{RESET}")
        return lines + [""] * (height - len(lines))

    def detail_text(self):
        module = self.current()
        if not module:
            return ""
        return module.desc if module.supported else f"{module.desc}  ·  needs {module.os_label}"

    def detail_line(self, width):
        """Single-line readout of the focused row, independent of the list's wrap mode."""
        return f"  {DIM}{fit(self.detail_text(), width - 2)}{RESET}"

    def header(self, width):
        title = fit("Dotfiles Setup", max(0, width - 2))
        selected = sum(1 for m in self.modules if m.selected)
        available = sum(1 for m in self.modules if m.supported)
        tags = "/".join(TAGS)
        for right in (
            f"{selected} of {available} selected · {tags}",
            f"{selected}/{available} · {tags}",
            f"{selected}/{available}",
            "",
        ):
            if len(title) + len(right) + 3 <= width:
                break
        gap = " " * max(1, width - 2 - len(title) - len(right))
        return [
            f"  {BOLD}{CYAN}{title}{RESET}{gap}{DIM}{right}{RESET}",
            f"  {DIM}{'─' * (width - 2)}{RESET}",
            self.detail_line(width),
            "",
        ]

    def footer(self, width):
        rule = f"  {DIM}{'─' * (width - 2)}{RESET}"
        if self.searching:
            tail = f"  {len(self.visible)} matching"
            query = fit(self.query, max(4, width - len(tail) - 5))
            if len(query) + len(tail) + 5 > width:
                tail = ""
            return ["", rule, f"  {CYAN}/{RESET} {query}{CYAN}▏{RESET}{DIM}{tail}{RESET}"]
        if self.query:
            note = "  esc to clear"
            query = fit(self.query, max(4, width - len(note) - 10))
            if len(query) + len(note) + 10 > width:
                note = ""
            return ["", rule, f"  {DIM}filter{RESET} {query}{DIM}{note}{RESET}"]
        return ["", rule, "  " + self.hints(width - 2)]

    def hints(self, width):
        full = [("j/k", "move"), ("space", "select"), ("/", "filter"), ("enter", "run"), ("q", "quit")]
        wide = full[:3] + [(",vw", "wrap")] + full[3:]
        for keys in (wide, full, full[:2] + full[-1:], [(k, "") for k, _ in full]):
            if len(" · ".join(f"{k} {v}".strip() for k, v in keys)) <= width:
                return f" {DIM}·{RESET} ".join(
                    f"{BOLD}{k}{RESET}" + (f"{DIM} {v}{RESET}" if v else "") for k, v in keys
                )
        return f"{DIM}{fit('q quit', width)}{RESET}"

    def render(self):
        size, width = frame_size()
        lines = self.header(width)
        lines += self.body(max(3, size.lines - len(lines) - 4), width)
        lines += self.footer(width)
        resized = self.last_size != size
        self.last_size = size
        frame = "".join(f"{line}\033[K\n" for line in lines[: max(1, size.lines - 1)])
        sys.stdout.write(("\033[2J" if resized else "") + "\033[H" + frame + "\033[J")
        sys.stdout.flush()

    def handle_search(self, key):
        if key == "ENTER":
            self.searching = False
        elif key == "ESC":
            self.searching = False
            self.query = ""
            self.update_filter()
            self.cursor = 0
        elif key == "BACKSPACE":
            self.query = self.query[:-1]
            self.update_filter()
            self.cursor = min(self.cursor, max(0, len(self.visible) - 1))
        elif key == "SPACE":
            self.toggle()
        elif key in ("UP", "DOWN"):
            self.move(1 if key == "DOWN" else -1)
        elif len(key) == 1 and key.isprintable():
            self.query += key
            self.update_filter()
            self.cursor = 0

    def handle(self, key):
        """Return "run" or "quit" to leave the loop."""
        if self.searching:
            self.handle_search(key)
            return None
        if key == "q":
            return "quit"
        if key == "ENTER":
            return "run"
        if key == "ESC" and self.query:
            self.query = ""
            self.update_filter()
            self.cursor = 0
        elif key == "SPACE":
            self.toggle()
        elif key == "/":
            self.searching = True
            self.query = ""
            self.cursor = 0
        elif key in ("j", "DOWN"):
            self.move(1)
        elif key in ("k", "UP"):
            self.move(-1)
        elif key == "\x04":
            self.jump(max(1, len(self.visible) // 2))
        elif key == "\x15":
            self.jump(-max(1, len(self.visible) // 2))
        elif key == "gg":
            self.cursor = 0
        elif key == ",vw":
            self.wrap = not self.wrap
        elif key == "G":
            self.cursor = max(0, len(self.visible) - 1)
        return None


def read_key(fd, sequences=True):
    def pending(timeout):
        return bool(select.select([fd], [], [], timeout)[0])

    char = os.read(fd, 1).decode("utf-8", "replace")
    if char == "\x1b":
        if not pending(0.02):
            return "ESC"
        if os.read(fd, 1) != b"[" or not pending(0.02):
            return "ESC"
        return {"A": "UP", "B": "DOWN", "C": "RIGHT", "D": "LEFT"}.get(
            os.read(fd, 1).decode("utf-8", "replace"), ""
        )
    if sequences:
        while char in PREFIXES and pending(SEQUENCE_TIMEOUT):
            char += os.read(fd, 1).decode("utf-8", "replace")
            if char in SEQUENCES:
                return char
    if char in ("\r", "\n"):
        return "ENTER"
    if char in ("\x7f", "\x08"):
        return "BACKSPACE"
    if char == " ":
        return "SPACE"
    return char


def pick(modules):
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    picker = Picker(modules)
    # SIGWINCH only interrupts select() through a wakeup pipe; a bare handler would be retried
    wake_r, wake_w = os.pipe()
    os.set_blocking(wake_w, False)
    previous = signal.signal(signal.SIGWINCH, lambda *_: None)
    signal.set_wakeup_fd(wake_w)
    sys.stdout.write("\033[?1049h\033[?25l")
    try:
        tty.setcbreak(fd)
        picker.render()
        while True:
            ready = select.select([fd, wake_r], [], [])[0]
            if wake_r in ready:
                os.read(wake_r, 4096)
            if fd in ready:
                action = picker.handle(read_key(fd, sequences=not picker.searching))
                if action:
                    return action == "run"
            picker.render()
    finally:
        signal.set_wakeup_fd(-1)
        signal.signal(signal.SIGWINCH, previous)
        os.close(wake_r)
        os.close(wake_w)
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()


def section(label, width=None):
    width = width or frame_size()[1]
    label = fit(label, max(0, width - 4))
    dashes = max(0, width - len(label) - 4)
    print(f"\n{DIM}──{RESET} {BOLD}{CYAN}{label}{RESET} {DIM}{'─' * dashes}{RESET}")


def main():
    if not sys.stdin.isatty():
        die("setup.py needs an interactive terminal")
    modules = load_modules()
    if not modules:
        die("No modules found. Exit.")
    if not pick(modules):
        sys.exit(0)

    chosen = [m for m in modules if m.selected]
    if not chosen:
        print(f"{DIM}nothing selected{RESET}")
        sys.exit(1)

    failed = []
    script_ran = False
    width = max(len(m.name) for m in chosen)
    for module in chosen:
        if module.script:
            script_ran = True
            section(module.name)
            code = module.run()
            if code == 0:
                print(f"{GREEN}✓{RESET} {module.name}")
            else:
                failed.append(module)
                print(f"{RED}✗{RESET} {module.name} {DIM}exit {code}{RESET}")
            continue
        name = module.name.ljust(width)
        try:
            state, detail = module.run_link()
        except OSError as exc:
            failed.append(module)
            print(f"{RED}✗{RESET} {name}  {exc.strerror}: {exc.filename}")
            continue
        if state == "linked":
            print(f"{GREEN}✓{RESET} {name}  {DIM}已链接（跳过）{RESET}")
        elif state == "created":
            print(f"{GREEN}✓{RESET} {name}  新建 → {detail}")
        else:
            failed.append(module)
            print(f"{YELLOW}▲{RESET} {name}  目标被占用: {detail} 不是 dotfiles 链接")

    if script_ran or failed:
        section("summary")
        for module in chosen:
            module.refresh_status()
            badge = {
                "installed": f"{GREEN}●{RESET} {DIM}installed{RESET}",
                "conflict": f"{YELLOW}▲ conflict{RESET}",
            }.get(module.status, f"{RED}○ not installed{RESET}")
            print(f"  {module.name.ljust(width)}  {badge}")
        tally = f"{len(chosen) - len(failed)}/{len(chosen)} ran successfully"
        print(f"  {DIM}{'─' * (width + 18)}{RESET}\n  {DIM}{tally}{RESET}")
    else:
        print(f"{DIM}{len(chosen)}/{len(chosen)} ok{RESET}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
