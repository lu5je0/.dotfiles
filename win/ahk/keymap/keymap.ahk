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
^#!r::Reload

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

; crtl win j
; #^j::ResizeWin(0, 0, 2319, 1678)
#^j::	
WinRestore,A
return

; Maximize windows
#^k::	
WinMaximize,A
return

; let window display on top
#^t:: Winset, Alwaysontop, , A
