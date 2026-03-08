#Requires AutoHotkey v2.0
#Include "wsa/baichizhan.ahk"

;;百词斩宽度 1035 2075
#HotIf WinActive("ahk_exe WsaClient.exe")

Esc::
{
    MouseGetPos &CoordXRec, &CoordYRec
    MouseClick "left", 36, 26, 1, 0
    MouseMove CoordXRec, CoordYRec
}

#HotIf
