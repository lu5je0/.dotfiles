if has("mac")
    set guifont=JetBrainsMono\ Nerd\ Font\ Mono:h15
    " set guifont=JetBrainsMono:h15
elseif has("win32")
    set guifont=Consolas\ NF:h12
    set guifontwide=Microsoft_Yahei_Mono:h12
endif

set guioptions-=m " 隐藏菜单栏
set guioptions-=e " 隐藏tab
set guioptions-=T " 隐藏工具栏
set guioptions-=L " 隐藏左侧滚动条
set guioptions-=r " 隐藏右侧滚动条
set guioptions-=b " 隐藏底部滚动条
if has("mac")
    set lines=35
    set columns=107
else
    set lines=48
    set columns=140
endif
if has("win32")
    winpos 900 330
endif
source $VIMRUNTIME/delmenu.vim
source $VIMRUNTIME/menu.vim
if has("win32")
    command Wsl :ter C:\Windows\Sysnative\wsl.exe
endif
