# =============================================================================
# init-tools.ps1 —— 下载固定版本的 CMake 与 Ninja, 加入 PATH
#
# 为什么固定版本: runner 镜像自带的 CMake 版本随镜像更新而变化,
# 固定版本可保证构建结果可复现。Ninja 用于 Ninja Multi-Config 双配置构建。
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

# 将工具加入 PATH (当前进程 + GITHUB_PATH 供后续步骤使用)
$env:PATH = "$cmakeDir\bin;$ninjaDir;$env:PATH"
$githubPath = $env:GITHUB_PATH
if ($githubPath) {
    "$cmakeDir\bin" | Out-File -FilePath $githubPath -Append -Encoding utf8
    $ninjaDir | Out-File -FilePath $githubPath -Append -Encoding utf8
}

Write-Host '==> 工具链就绪:'
cmake --version | Select-Object -First 1
ninja --version
