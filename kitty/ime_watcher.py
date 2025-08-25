from typing import Any

from kitty.boss import Boss # type: ignore
from kitty.window import Window # type: ignore
import subprocess

proc = subprocess.Popen(
    ["/Users/lu5je0/.dotfiles/vim/lib/imeswitch", "-i"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)

def on_set_user_var(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    if data['key'] == 'ime':
        print(data['value'])
        if data['value'] == 'normal':
            proc.stdin.write('normal\n')
            proc.stdin.flush()
        elif data['value'] == 'insert':
            proc.stdin.write('insert\n')
            proc.stdin.flush()
