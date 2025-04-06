@echo off
wsl /home/linuxbrew/.linuxbrew/bin/nvim "$(wslpath '%1')"
