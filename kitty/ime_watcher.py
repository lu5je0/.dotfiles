from typing import Any

from kitty.boss import Boss # type: ignore
from kitty.window import Window # type: ignore
import subprocess

proc = subprocess.Popen(
    ["/opt/homebrew/bin/python3", "/Users/lu5je0/.dotfiles/kitty/xkb.py"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)

def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    if data['key'] == 'ime' and data['value'] == 'en':
        proc.stdin.write('switch_ime com.apple.keylayout.ABC\n')
        proc.stdin.flush()
