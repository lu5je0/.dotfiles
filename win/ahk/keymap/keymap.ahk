; 基本语法 Start
; <^ 代表左Ctrl
; ^ -> Ctrl
; # -> Win
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

; Maximize windows
#^k::	
    WinMaximize,A
return

; let window display on top
#^t:: Winset, Alwaysontop, , A

; Esc::Capslock
; Capslock::Esc

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

ResizeWindow(position) {
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A
    
    ; 获取活动窗口的进程 ID
    WinGet, processID, PID, ahk_id %activeWindow%
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)
    
    ; 获取屏幕宽度和高度
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79

    ; 定义特定应用的窗口大小和位置映射
    specialAppMap := {}
    specialAppMap["alacritty.exe"] := { "center_i": { "width": 2457, "height": 2038, "x_offset": (screenWidth - 2457) / 2, "y_offset": 23 }, "center_j": { "width": 1931, "height": 1596, "x_offset": (screenWidth - 1931) / 2, "y_offset": (screenHeight - 1596) / 2 } }
    specialAppMap["WindowsTerminal.exe"] := { "center_i": { "width": 2457, "height": 2038, "x_offset": (screenWidth - 2457) / 2, "y_offset": 23 }, "center_j": { "width": 1931, "height": 1596, "x_offset": (screenWidth - 1931) / 2, "y_offset": (screenHeight - 1596) / 2 } }
    ; font size 11
    ; specialAppMap["wezterm-gui.exe"] := { "center_i": { "width": 2457, "height": 2038, "x_offset": (screenWidth - 2457) / 2, "y_offset": 23 }, "center_j": { "width": 1931, "height": 1596, "x_offset": (screenWidth - 1931) / 2, "y_offset": (screenHeight - 1596) / 2 } }
    ; font size 11.5
    specialAppMap["wezterm-gui.exe"] := { "center_i": { "width": 2457, "height": 2008, "x_offset": (screenWidth - 2457) / 2, "y_offset": 23 }, "center_j": { "width": 1928, "height": 1612, "x_offset": (screenWidth - 1931) / 2, "y_offset": (screenHeight - 1596) / 2 } }
    ; fancy tab bar
    ; specialAppMap["wezterm-gui.exe"] := { "center_i": { "width": 2456, "height": 2034, "x_offset": (screenWidth - 2457) / 2, "y_offset": 23 }, "center_j": { "width": 1928, "height": 1592, "x_offset": (screenWidth - 1931) / 2, "y_offset": (screenHeight - 1596) / 2 } }
    
    ; 判断是否在特殊应用映射中
    if (specialAppMap[processName].HasKey(position)) {
        newWidth := specialAppMap[processName][position].width
        newHeight := specialAppMap[processName][position].height
        newX := specialAppMap[processName][position].x_offset
        newY := specialAppMap[processName][position].y_offset
    } else {
        ; 判断位置参数
        if (position = "left" or position = "right") {
            ; 计算窗口的新宽度和高度
            newWidth := screenWidth / 2
            newHeight := screenHeight
            
            ; 计算窗口的新位置
            newX := (position = "left") ? 0 : screenWidth / 2
            newY := 0
        } else if (position = "center_i" or position = "center_j") {
            if (position = "center_i") {
                ; 计算窗口的新宽度和高度 (4/5 屏幕大小)
                newWidth := screenWidth * (11 / 16)
                newHeight := screenHeight - 120

                ; 计算窗口的新位置 (居中)
                newX := (screenWidth - newWidth) / 2
                newY := 23
            } else if (position = "center_j") {
                ; 计算窗口的新宽度和高度 (3/5 屏幕大小)
                newWidth := screenWidth * 3 / 5
                newHeight := screenHeight * (17 / 20)

                ; 计算窗口的新位置 (居中)
                newX := (screenWidth - newWidth) / 2
                newY := (screenHeight - newHeight) / 2
            }
        } else {
            return ; 无效的位置参数
        }
    }

    ; 调整窗口大小和位置
    WinRestore, A
    WinMove, ahk_id %activeWindow%, , newX, newY, newWidth, newHeight
}

^#h:: ; Ctrl + Win + H
    ResizeWindow("left")
return

^#l:: ; Ctrl + Win + L
    ResizeWindow("right")
return

^#i:: ; Ctrl + Win + I
    ResizeWindow("center_i")
return

^#j:: ; Ctrl + Win + J
    ResizeWindow("center_j")
return

^#w:: ; Ctrl + Win + w
    ; 获取活动窗口的句柄
    WinGet, activeWindow, ID, A

    ; 获取窗口的位置和大小
    WinGetPos, X, Y, Width, Height, ahk_id %activeWindow%
    
    ; 获取活动窗口的进程 ID
    WinGet, processID, PID, ahk_id %activeWindow%
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)

    ; 打印窗口的位置和大小
    MsgBox, The window position and size are:`nX: %X%`nY: %Y%`nWidth: %Width%`nHeight: %Height%`nProcessName: %processName%
return
