@echo off
setlocal enabledelayedexpansion

set "IME_DIR=%~dp0"
set "RIME_SRC=%IME_DIR%rime\"
set "RIME_DIR=%APPDATA%\Rime"
set "RIME_ICE=%RIME_DIR%\rime-ice"
set "RIME_ICE_URL=https://github.com/iDvel/rime-ice.git"

if not exist "%RIME_DIR%" mkdir "%RIME_DIR%"

:: 上游 rime-ice 不再是 dotfiles 的 submodule，而是安装时浅克隆到 Rime 用户目录。
:: 它属于运行时数据，不是配置；完整 clone 的 .git 有 230M+，浅克隆只 17M。
if exist "%RIME_ICE%\default.yaml" (
    echo rime-ice: already present
) else (
    if exist "%RIME_ICE%" (
        echo error: "%RIME_ICE%" exists but incomplete ^(no default.yaml^). Remove it and retry >&2
        exit /b 1
    )
    echo rime-ice: shallow clone to "%RIME_ICE%"
    git clone --depth 1 "%RIME_ICE_URL%" "%RIME_ICE%"
    if errorlevel 1 (
        echo error: git clone failed >&2
        exit /b 1
    )
)

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
:: *.lua 必须一起 link：rime_ice.custom.yaml 里 patch 了 lua_processor@ctrl_b_passthrough，
:: 缺了对应的 lua 文件 Rime 会加载方案失败。
for %%f in ("%RIME_SRC%*.custom.yaml" "%RIME_SRC%custom_phrase.txt" "%RIME_SRC%*.lua") do (
    if exist "%%f" (
        if exist "%RIME_DIR%\%%~nxf" del "%RIME_DIR%\%%~nxf"
        mklink "%RIME_DIR%\%%~nxf" "%%f"
    )
)

echo rime: linked to %RIME_DIR%
echo Please click 'Redeploy' in Weasel tray icon to apply.
