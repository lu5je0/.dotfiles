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

#Requires AutoHotkey v2.0
SetWinDelay -1
#Include ..\layout.ahk

; alt
<!k::Send("{Up}")
<!j::Send("{Down}")
<!h::Send("{Left}")
<!l::Send("{Right}")

; reload
#^r::Reload

; minimize windows
!m::
{
    WinMinimize "A"
}

; Maximize windows
#^k::
{
    WinMaximize "A"
}

; let window display on top
#^t::WinSetAlwaysOnTop -1, "A"

; Esc::Capslock
; Capslock::Esc

GetProcessName(processID) {
    try return ProcessGetName(processID)
    catch
        return ""
}

ResizeWindow(position) {
    ; 获取活动窗口的句柄
    activeWindow := WinGetID("A")

    ; 获取活动窗口的进程 ID
    processID := WinGetPID("ahk_id " activeWindow)
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)

    ; 获取屏幕宽度和高度
    screenWidth := SysGet(78)
    screenHeight := SysGet(79)

    ; 判断位置参数
    if (position = "left" or position = "right") {
        r := GetSideRect(position)
        newWidth := r.width
        newHeight := r.height
        newX := r.x
        newY := r.y
    } else if (position = "center_i" or position = "center_j") {
        layout := GetCenterLayout(processName, position, screenWidth, screenHeight)
        if (!layout)
            return
        newWidth := layout.width
        newHeight := layout.height
        newX := layout.x
        newY := layout.y
    } else {
        return ; 无效的位置参数
    }

    ; 若是居中位置且目标已被其它窗口占据，错开一点避免重合
    if (position = "center_i" or position = "center_j") {
        offsetStep := 20
        maxShifts := 6
        shifts := 0
        while (shifts < maxShifts && FindOtherWindowAtRect(newX, newY, newWidth, newHeight, activeWindow)) {
            newX += offsetStep
            newY += offsetStep
            shifts++
        }
    }

    ; 调整窗口大小和位置
    WinRestore "A"
    WinMove newX, newY, newWidth, newHeight, "ahk_id " activeWindow
}

IsWindowSnappedTo(hwnd, side) {
    if (!hwnd)
        return false

    r := GetSideRect(side)
    try {
        WinGetPos &x, , &w, , "ahk_id " hwnd
    } catch {
        return false
    }
    tolerance := 16
    return Abs(x - r.x) <= tolerance && Abs(w - r.width) <= tolerance
}

FindOtherWindowOnSide(side, excludeHwnd) {
    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd)
            continue
        if (IsWindowSnappedTo(hwnd, side))
            return hwnd
    }
    return 0
}

FindOtherWindowAtRect(rx, ry, rw, rh, excludeHwnd) {
    if (rw <= 0 || rh <= 0)
        return 0
    targetCx := rx + rw / 2
    targetCy := ry + rh / 2
    centerTolerance := 30
    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        try {
            WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        } catch {
            continue
        }
        if (w <= 0 || h <= 0)
            continue
        cx := x + w / 2
        cy := y + h / 2
        if (Abs(cx - targetCx) <= centerTolerance && Abs(cy - targetCy) <= centerTolerance)
            return hwnd
    }
    return 0
}

GetSideRect(side) {
    MonitorGetWorkArea MonitorGetPrimary(), &waLeft, &waTop, &waRight, &waBottom
    waWidth := waRight - waLeft
    waHeight := waBottom - waTop

    vPadding := 9
    hPadding := 9
    w := waWidth / 2 - hPadding
    h := waHeight - vPadding * 2
    x := (side = "left") ? waLeft + hPadding : waLeft + waWidth / 2
    y := waTop + vPadding
    return { x: x, y: y, width: w, height: h }
}

MoveWindowToSide(hwnd, side) {
    r := GetSideRect(side)
    try {
        WinRestore "ahk_id " hwnd
        WinMove r.x, r.y, r.width, r.height, "ahk_id " hwnd
    }
}

FindFullscreenWindow(excludeHwnd) {
    MonitorGetWorkArea MonitorGetPrimary(), &waLeft, &waTop, &waRight, &waBottom
    waArea := (waRight - waLeft) * (waBottom - waTop)
    if (waArea <= 0)
        return 0
    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        if (!WinGetTitle("ahk_id " hwnd))
            continue
        try {
            WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        } catch {
            continue
        }
        if (w <= 0 || h <= 0)
            continue
        ; 与工作区重叠面积 > 80% 视为全屏/最大化
        ox := Max(0, Min(waRight, x + w) - Max(waLeft, x))
        oy := Max(0, Min(waBottom, y + h) - Max(waTop, y))
        if ((ox * oy) / waArea > 0.8)
            return hwnd
    }
    return 0
}

SnapWithSwap(side) {
    activeWindow := WinGetID("A")
    if (!activeWindow)
        return

    otherSide := (side = "left") ? "right" : "left"
    occupier := FindOtherWindowOnSide(side, activeWindow)
    if (!occupier)
        occupier := FindFullscreenWindow(activeWindow)
    if (occupier)
        MoveWindowToSide(occupier, otherSide)

    ResizeWindow(side)
}

^#h:: ; Ctrl + Win + H
{
    SnapWithSwap("left")
}

^#l:: ; Ctrl + Win + L
{
    SnapWithSwap("right")
}

^#i:: ; Ctrl + Win + I
{
    ResizeWindow("center_i")
}

^#j:: ; Ctrl + Win + J
{
    ResizeWindow("center_j")
}

^#w:: ; Ctrl + Win + w
{
    ; 获取活动窗口的句柄
    activeWindow := WinGetID("A")

    ; 获取窗口的位置和大小
    WinGetPos &X, &Y, &Width, &Height, "ahk_id " activeWindow

    ; 获取活动窗口的进程 ID
    processID := WinGetPID("ahk_id " activeWindow)
    ; 获取活动窗口的进程名称
    processName := GetProcessName(processID)

    ; 打印窗口的位置和大小
    MsgBox "The window position and size are:`nX: " X "`nY: " Y "`nWidth: " Width "`nHeight: " Height "`nProcessName: " processName
}

^#f:: ; Ctrl + Win + F - 启动当前活动窗口对应程序的新实例
{
    static forkWhitelist := Map(
        "chrome.exe", true,
        "wezterm-gui.exe", true,
        "explorer.exe", true,
    )

    activeWindow := WinGetID("A")
    if (!activeWindow)
        return
    pid := WinGetPID("ahk_id " activeWindow)
    processName := GetProcessName(pid)
    if (!forkWhitelist.Has(processName))
        return
    try {
        exePath := ProcessGetPath(pid)
    } catch {
        return
    }
    if (exePath) {
        Run exePath, , , &newPid
        if (newPid) {
            newHwnd := WinWait("ahk_pid " newPid, , 5)
            if (newHwnd)
                WinActivate "ahk_id " newHwnd
        }
    }
}

^#+5:: ; Ctrl + Win + % - fork 一个进程，原窗口贴左，新窗口贴右
{
    static forkWhitelist := Map(
        "chrome.exe", true,
        "wezterm-gui.exe", true,
        "explorer.exe", true,
    )

    oldHwnd := WinGetID("A")
    if (!oldHwnd)
        return
    pid := WinGetPID("ahk_id " oldHwnd)
    processName := GetProcessName(pid)
    if (!forkWhitelist.Has(processName))
        return
    try {
        exePath := ProcessGetPath(pid)
    } catch {
        return
    }
    if (!exePath)
        return

    if (processName = "wezterm-gui.exe")
        FileAppend "", A_Temp "\wezterm_skip_resize.flag"

    ; 启动前快照：所有当前同 exe 的可见窗口
    existing := Map()
    for hwnd in WinGetList() {
        try {
            p := WinGetPID("ahk_id " hwnd)
            if (ProcessGetPath(p) = exePath)
                existing[hwnd] := true
        }
    }

    Run exePath

    ; 轮询查找新窗口（最多 5 秒）
    newHwnd := 0
    startTime := A_TickCount
    while (A_TickCount - startTime < 5000) {
        for hwnd in WinGetList() {
            if (existing.Has(hwnd))
                continue
            try {
                p := WinGetPID("ahk_id " hwnd)
                if (ProcessGetPath(p) != exePath)
                    continue
            } catch {
                continue
            }
            if (!WinGetTitle("ahk_id " hwnd))
                continue
            newHwnd := hwnd
            break
        }
        if (newHwnd)
            break
        Sleep 50
    }
    if (!newHwnd)
        return

    oldSide := IsWindowSnappedTo(oldHwnd, "right") ? "right" : "left"
    newSide := (oldSide = "right") ? "left" : "right"

    MoveWindowToSide(oldHwnd, oldSide)
    MoveWindowToSide(newHwnd, newSide)
    WinActivate "ahk_id " newHwnd
}
