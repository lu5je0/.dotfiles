rem Msgbox "wsl2 startup"
Set ws = CreateObject("Wscript.Shell")
ws.run "wsl -u root /etc/init_wsl.sh"
