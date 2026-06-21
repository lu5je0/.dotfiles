@echo off
setlocal enabledelayedexpansion

set "DOTFILES_RIME=%~dp0"
set "RIME_ICE=%DOTFILES_RIME%rime-ice"
set "RIME_DIR=%APPDATA%\Rime"

if not exist "%RIME_ICE%\default.yaml" (
    echo error: submodule rime-ice not found. Run: git submodule update --init rime/rime-ice >&2
    exit /b 1
)

if not exist "%RIME_DIR%" mkdir "%RIME_DIR%"

:: Link upstream directories (junction)
for %%d in (cn_dicts en_dicts lua opencc) do (
    if not exist "%RIME_DIR%\%%d" (
        if exist "%RIME_ICE%\%%d" (
            mklink /J "%RIME_DIR%\%%d" "%RIME_ICE%\%%d"
        )
    )
)

:: Link upstream yaml/txt files
for %%f in ("%RIME_ICE%\*.yaml" "%RIME_ICE%\*.txt") do (
    if not exist "%RIME_DIR%\%%~nxf" (
        mklink "%RIME_DIR%\%%~nxf" "%%f"
    )
)

:: Link personal customizations (override upstream)
for %%f in ("%DOTFILES_RIME%*.custom.yaml" "%DOTFILES_RIME%custom_phrase.txt") do (
    if exist "%%f" (
        if exist "%RIME_DIR%\%%~nxf" del "%RIME_DIR%\%%~nxf"
        mklink "%RIME_DIR%\%%~nxf" "%%f"
    )
)

echo rime: linked to %RIME_DIR%
echo Please click 'Redeploy' in Weasel tray icon to apply.
