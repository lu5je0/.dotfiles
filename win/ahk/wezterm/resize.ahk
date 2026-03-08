; resize.ahk
#Requires AutoHotkey v2.0

hwnd := WinGetID("A")  ; 获取当前窗口句柄
WinGetPos &x, &y, &width, &height, "ahk_id " hwnd  ; 获取当前窗口的位置和大小
newWidth := 1928  ; 设置新的宽度
newHeight := 1644  ; 设置新的高度
WinMove x, y, newWidth, newHeight, "ahk_id " hwnd  ; 调整窗口大小，保持位置不变
