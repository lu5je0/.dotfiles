; resize.ahk
WinGet, hwnd, ID, A  ; 获取当前窗口句柄
WinGetPos, x, y, width, height, ahk_id %hwnd%  ; 获取当前窗口的位置和大小
newWidth := 1928  ; 设置新的宽度
newHeight := 1680  ; 设置新的高度
WinMove, ahk_id %hwnd%, , x, y, newWidth, newHeight  ; 调整窗口大小，保持位置不变
