# 检查是否具有管理员权限
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    # 以管理员权限重新启动PowerShell脚本
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 确保目标目录存在
$targetDir = "$Home\Documents\WindowsPowerShell"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir
}

# 创建软链接
New-Item -ItemType SymbolicLink -Path "$targetDir\profile.ps1" -Target "$Home\.dotfiles\win\powershell\profile.ps1"
