<#
metax 一键安装脚本（Windows）
使用说明：以管理员身份运行 PowerShell，执行以下命令：
irm https://raw.githubusercontent.com/你的用户名/你的仓库/main/install-metax.ps1 | iex
#>

# 配置项（替换为你的实际信息）
$toolName = "metax"
$repoOwner = "你的GitHub用户名"
$repoName = "你的仓库名"
$installDir = "$env:ProgramFiles\$toolName" # 安装到系统程序目录，默认全局可访问
$latestReleaseApi = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"

try {
    Write-Host "===== 开始安装 $toolName =====" -ForegroundColor Green

    # 1. 检查是否以管理员运行（必须，否则无法修改系统环境变量）
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "请以【管理员身份】运行 PowerShell 后再执行此脚本！"
        exit 1
    }

    # 2. 创建安装目录
    if (-not (Test-Path $installDir)) {
        Write-Host "创建安装目录: $installDir"
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    # 3. 获取最新版本信息
    Write-Host "获取最新版本信息..."
    $releaseInfo = Invoke-RestMethod -Uri $latestReleaseApi -Method Get
    $version = $releaseInfo.tag_name
    $exeAsset = $releaseInfo.assets | Where-Object { $_.name -eq "metax-windows-x64.exe" }

    if (-not $exeAsset) {
        Write-Error "未找到 Windows 版本的可执行文件！"
        exit 1
    }

    # 4. 下载 exe 文件
    $exePath = "$installDir\$toolName.exe"
    Write-Host "下载 $toolName $version 版本..."
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $exePath -UseBasicParsing

    # 5. 检查文件是否下载成功
    if (-not (Test-Path $exePath)) {
        Write-Error "文件下载失败！"
        exit 1
    }

    # 6. 添加到系统环境变量（永久生效）
    $systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not $systemPath.Contains($installDir)) {
        Write-Host "添加安装目录到系统环境变量..."
        [Environment]::SetEnvironmentVariable("Path", "$systemPath;$installDir", "Machine")
        # 临时更新当前终端的环境变量（无需重启）
        $env:Path += ";$installDir"
    }

    # 7. 验证安装
    Write-Host "验证安装..."
    if (Get-Command $toolName -ErrorAction SilentlyContinue) {
        Write-Host "===== $toolName $version 安装成功！=====" -ForegroundColor Green
        Write-Host "现在可以在任意终端执行 '$toolName --help' 开始使用" -ForegroundColor Cyan
    } else {
        Write-Warning "安装完成，但临时环境变量未生效，请重启终端后使用"
    }
}
catch {
    Write-Error "安装失败：$_"
    exit 1
}