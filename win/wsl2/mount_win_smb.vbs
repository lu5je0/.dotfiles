rem Msgbox "wsl2 startup"
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -d Debian -u root mount -t drvfs 'X:' /mnt/x --verbose", vbhide
ws.run "wsl -d Debian -u root mount -t drvfs 'Z:' /mnt/z --verbose", vbhide
