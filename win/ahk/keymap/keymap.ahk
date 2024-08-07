; 基本语法 Start
; <^ 代表左Ctrl
; ^ -> Ctrl
; ! -> Alt
; + -> Shift
; ; -> 单行注释 (single-line comment) 
; ` -> 转义字符 (escape character)
; :: -> 按键映射 (key mapping)
; $ -> 抑制原来的按键
; ~ -> 保留系统原有按键功能
; 原键位::映射到的键位

; alt
<!k::Send, {Up}
<!j::Send, {Down}
<!h::Send, {Left}
<!l::Send, {Right}

; reload
#^r::Reload

; minimize windows
!m::	
WinMinimize,A
return

; Esc::Capslock
; Capslock::Esc

ResizeWin(Left = 0, Top = 0, Width = 0, Height = 0)
{
    WinGetPos,X,Y,W,H,A

    If %Left% = 0
        Left := X
    If %Top% = 0
        Top := Y

    If %Width% = 0
        Width := W

    If %Height% = 0
        Height := H

    WinMove,A,,%Left%,%Top%,%Width%,%Height%
}

GetProcessName(processID) {
    hProcess := DllCall("OpenProcess", "UInt", 0x0410, "Int", 0, "UInt", processID, "Ptr")
    if !hProcess
        return ""
    
    VarSetCapacity(buf, 260, 0)
    if DllCall("Psapi.dll\GetModuleBaseName", "Ptr", hProcess, "Ptr", 0, "Str", buf, "UInt", 260)
        processName := buf
    else
        processName := ""
    
    DllCall("CloseHandle", "Ptr", hProcess)
    return processName
}

^#w:: ; Ctrl + Win + w
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A

    ; 获取窗口的位置和大小
    WinGetPos, X, Y, Width, Height, ahk_id %activeWindow%

    ; 打印窗口的位置和大小
    MsgBox, The window position and size are:`nX: %X%`nY: %Y%`nWidth: %Width%`nHeight: %Height%
return

; crtl+win+i
^#i:: ; Ctrl + Win + i
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A
    
    ; 获取活动窗口的进程 ID
    WinGet, processID, PID, ahk_id %activeWindow%
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)
    
    ; 获取屏幕宽度和高度
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79
    ; 判断是否是 Alacritty
    if (processName = "alacritty.exe") {
        newWidth := 2457
        newHeight := 2038
        newX := (screenWidth - newWidth) / 2
        newY := 23
        WinRestore,A
        WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
    } else {
        ; 计算窗口的新宽度和高度 (2/3 屏幕大小)
        newWidth := screenWidth * (4 / 5)
        newHeight := screenHeight

        ; 计算窗口的新位置 (居中)
        newX := (screenWidth - newWidth) / 2
        newY := 0

        ; 调整窗口大小和位置
        WinRestore,A
        WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
    }
return

; crtl+win+j
^#j:: ; Ctrl + Win + J
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A
    
    ; 获取活动窗口的进程 ID
    WinGet, processID, PID, ahk_id %activeWindow%
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)
    
    ; 获取屏幕宽度和高度
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79
    ; 判断是否是 Alacritty
    if (processName = "alacritty.exe") {
        newWidth := 1931
        newHeight := 1596
        newX := (screenWidth - newWidth) / 2
        newY := (screenHeight - newHeight) / 2
        WinRestore,A
        WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
    } else {
        ; 计算窗口的新宽度和高度 (2/3 屏幕大小)
        newWidth := screenWidth * (3 / 5)
        newHeight := screenHeight * (4 / 5)

        ; 计算窗口的新位置 (居中)
        newX := (screenWidth - newWidth) / 2
        newY := (screenHeight - newHeight) / 2

        ; 调整窗口大小和位置
        WinRestore,A
        WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
    }
return

; Maximize windows
#^k::	
    WinMaximize,A
return

; let window display on top
#^t:: Winset, Alwaysontop, , A

ResizeWindow(position) {
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A

    ; 获取屏幕宽度和高度
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79

    ; 计算窗口的新宽度和高度
    newWidth := screenWidth / 2
    newHeight := screenHeight

    ; 计算窗口的新位置
    if (position = "left") {
        newX := 0
    } else if (position = "right") {
        newX := screenWidth / 2
    } else {
        return ; 无效的位置参数
    }
    newY := 0

    ; 调整窗口大小和位置
    WinRestore,A
    WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
}

^#h:: ; Ctrl + Win + H
    ResizeWindow("left")
return

^#l:: ; Ctrl + Win + L
    ResizeWindow("right")
return
