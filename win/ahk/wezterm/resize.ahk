; resize.ahk
#Requires AutoHotkey v2.0
#Include ..\layout.ahk

skipFlag := A_Temp "\wezterm_skip_resize.flag"
if (FileExist(skipFlag)) {
    FileDelete skipFlag
    ExitApp
}

GetParentPid(pid) {
    snap := DllCall("CreateToolhelp32Snapshot", "uint", 0x2, "uint", 0, "ptr")
    if (snap = -1)
        return 0
    ; PROCESSENTRY32W (64-bit): dwSize(4) cntUsage(4) th32ProcessID(4) pad(4)
    ;   th32DefaultHeapID(8) th32ModuleID(4) cntThreads(4)
    ;   th32ParentProcessID(4) pcPriClassBase(4) dwFlags(4) szExeFile[260](520) = 564
    size := 568
    entry := Buffer(size, 0)
    NumPut("uint", size, entry, 0)
    parent := 0
    if (DllCall("Process32FirstW", "ptr", snap, "ptr", entry)) {
        loop {
            if (NumGet(entry, 8, "uint") = pid) {
                parent := NumGet(entry, 32, "uint")
                break
            }
        } until !DllCall("Process32NextW", "ptr", snap, "ptr", entry)
    }
    DllCall("CloseHandle", "ptr", snap)
    return parent
}

parentPid := GetParentPid(ProcessExist())
if (!parentPid)
    ExitApp

hwnd := WinWait("ahk_pid " parentPid, , 5)
if (!hwnd)
    ExitApp

screenWidth := SysGet(78)
screenHeight := SysGet(79)
layout := GetCenterLayout("wezterm-gui.exe", "center_j", screenWidth, screenHeight)
if (!layout)
    ExitApp

WinGetPos &x, &y, , , "ahk_id " hwnd
WinMove x, y, layout.width, layout.height, "ahk_id " hwnd
