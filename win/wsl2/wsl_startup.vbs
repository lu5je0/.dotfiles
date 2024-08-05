rem Msgbox "wsl2 startup"
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -d Debian", vbhide
