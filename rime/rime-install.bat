@echo off
setlocal

set "DOTFILES_RIME=%~dp0"
set "RIME_ICE=%DOTFILES_RIME%rime-ice"
set "RIME_DIR=%APPDATA%\Rime"

if not exist "%RIME_DIR%" mkdir "%RIME_DIR%"

:: Copy upstream rime-ice files
for %%f in ("%RIME_ICE%\*.yaml" "%RIME_ICE%\*.txt") do (
    if exist "%%f" copy /y "%%f" "%RIME_DIR%\" >nul
)

:: Copy upstream directories
for %%d in (cn_dicts en_dicts lua opencc) do (
    if exist "%RIME_ICE%\%%d" (
        xcopy /e /i /y /q "%RIME_ICE%\%%d" "%RIME_DIR%\%%d" >nul
    )
)

:: Copy personal customizations (override upstream)
for %%f in ("%DOTFILES_RIME%*.custom.yaml" "%DOTFILES_RIME%custom_phrase.txt") do (
    if exist "%%f" copy /y "%%f" "%RIME_DIR%\" >nul
)

echo rime: copied to %RIME_DIR%
echo right-click tray icon and redeploy to apply
