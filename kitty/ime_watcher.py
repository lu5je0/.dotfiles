from typing import Any

from kitty.boss import Boss  # type: ignore
from kitty.window import Window  # type: ignore
import subprocess

proc = subprocess.Popen(
    ["/Users/lu5je0/.dotfiles/vim/lib/macos/bin/tui_bridge", "-i"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)


def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    if data["key"] == "tui_bridge":
        value = data["value"] + '\n'
        proc.stdin.write(value)
        proc.stdin.flush()
        # while proc.stdout.readable():
        #     print(proc.stdout.read())
