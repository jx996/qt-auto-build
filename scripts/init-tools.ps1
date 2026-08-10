# =============================================================================
# init-tools.ps1 —— 下载固定版本的 CMake / Ninja / jom, 加入 PATH
#
# 为什么固定版本: runner 镜像自带的 CMake 版本随镜像更新而变化,
# 固定版本可保证构建结果可复现。
#   - Ninja: Qt6 的 Ninja Multi-Config 双配置构建
#   - jom  : Qt5 (5.15) 的 qmake 构建 (jom 并行 nmake)
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$ToolsDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$cmakeVersion = '3.31.6'
$ninjaVersion = '1.13.2'

Write-Host "==> 初始化工具链到 $ToolsDir"
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# ---------- CMake ----------
$cmakeDir = Join-Path $ToolsDir "cmake-$cmakeVersion"
if (-not (Test-Path (Join-Path $cmakeDir 'bin\cmake.exe'))) {
    $cmakeZip = Join-Path $ToolsDir "cmake-$cmakeVersion.zip"
    $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
    Write-Host "==> 下载 CMake $cmakeVersion ..."
    Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip
    Write-Host "==> 解压 CMake ..."
    Expand-Archive -Path $cmakeZip -DestinationPath $ToolsDir -Force
    Remove-Item $cmakeZip -Force
}

# ---------- Ninja ----------
$ninjaDir = Join-Path $ToolsDir "ninja-$ninjaVersion"
if (-not (Test-Path (Join-Path $ninjaDir 'ninja.exe'))) {
    $ninjaZip = Join-Path $ToolsDir "ninja-$ninjaVersion.zip"
    $ninjaUrl = "https://github.com/ninja-build/ninja/releases/download/v$ninjaVersion/ninja-win.zip"
    Write-Host "==> 下载 Ninja $ninjaVersion ..."
    Invoke-WebRequest -Uri $ninjaUrl -OutFile $ninjaZip
    Write-Host "==> 解压 Ninja ..."
    New-Item -ItemType Directory -Force -Path $ninjaDir | Out-Null
    Expand-Archive -Path $ninjaZip -DestinationPath $ninjaDir -Force
    Remove-Item $ninjaZip -Force
}

# ---------- jom (Qt5 qmake 构建用) ----------
$jomDir = Join-Path $ToolsDir 'jom'
if (-not (Test-Path (Join-Path $jomDir 'jom.exe'))) {
    $jomZip = Join-Path $ToolsDir 'jom.zip'
    $jomUrl = 'https://download.qt.io/official_releases/jom/jom.zip'
    Write-Host '==> 下载 jom ...'
    Invoke-WebRequest -Uri $jomUrl -OutFile $jomZip
    Write-Host '==> 解压 jom ...'
    New-Item -ItemType Directory -Force -Path $jomDir | Out-Null
    Expand-Archive -Path $jomZip -DestinationPath $jomDir -Force
    Remove-Item $jomZip -Force
}

# 将工具加入 PATH (当前进程 + GITHUB_PATH 供后续步骤使用)
$env:PATH = "$cmakeDir\bin;$ninjaDir;$jomDir;$env:PATH"
$githubPath = $env:GITHUB_PATH
if ($githubPath) {
    "$cmakeDir\bin" | Out-File -FilePath $githubPath -Append -Encoding utf8
    $ninjaDir | Out-File -FilePath $githubPath -Append -Encoding utf8
    $jomDir | Out-File -FilePath $githubPath -Append -Encoding utf8
}

Write-Host '==> 工具链就绪:'
cmake --version | Select-Object -First 1
ninja --version
jom -version 2>&1 | Select-Object -First 1
