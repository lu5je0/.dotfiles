#!/bin/bash

CMD=/mnt/c/Windows/System32/cmd.exe
$CMD /c sudo "$(wslpath -w "$DOTFILES_DIR/rime/rime-install.bat")"
