<#
metax 一键卸载脚本（Windows）
使用说明：以管理员身份运行 PowerShell，执行以下命令：
irm https://raw.githubusercontent.com/WinnerApp/metax/refs/heads/stable | iex
#>

$toolName = "metax"
$installDir = "$env:ProgramFiles\$toolName"

# 管理员检查
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "请以管理员身份运行！"
    exit 1
}

# 删除安装目录
if (Test-Path $installDir) {
    Write-Host "删除安装目录: $installDir"
    Remove-Item -Path $installDir -Recurse -Force
}

# 从环境变量移除
$systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($systemPath.Contains($installDir)) {
    Write-Host "从环境变量移除安装目录..."
    $newPath = $systemPath.Replace(";$installDir", "")
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
}

Write-Host "$toolName 卸载成功！" -ForegroundColor Green