# =============================================================================
# build-qt5.ps1 —— 编译并安装 Qt5 (仅开源组件, shared 动态链接, Release + Debug)
#
# 与 Qt6 不同, Qt5 使用 qmake 构建体系:
#   - qtbase: configure.bat (-debug-and-release) 生成 jom 工程, jom 一次构建
#     Debug + Release 双配置, jom install 安装;
#   - 其余组件 (qttools/qttranslations/qtsvg): 用安装好的 qmake 生成工程,
#     继承 Qt 的 debug_and_release 配置, 同样 jom + jom install。
#
# 依赖:
#   - 已配置好的 MSVC x64 环境 (本工程由 VsDevCmd 步骤提供)
#   - download-sources.ps1 已下载好的源码 (官方源或 archive 源)
#   - init-tools.ps1 安装的 jom (及 Qt5 configure 所需 perl, 一般 Git 自带)
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$QtVersion,

    [Parameter(Mandatory = $true)]
    [string]$Toolchain,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$ToolsDir
)

$ErrorActionPreference = 'Stop'

# ---------- 0. 环境准备 ----------
$jomDir = Join-Path $ToolsDir 'jom'
$env:PATH = "$jomDir;$env:PATH"

if (-not (Get-Command jom -ErrorAction SilentlyContinue)) {
    throw '未找到 jom, 请先运行 init-tools.ps1'
}
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    throw '未找到 cl.exe, 请确保已加载 MSVC x64 环境'
}
# Qt5 configure 的 syncqt 步骤需要 perl (Git for Windows 自带)
if (-not (Get-Command perl -ErrorAction SilentlyContinue)) {
    $gitPerl = 'C:\Program Files\Git\usr\bin'
    if (Test-Path (Join-Path $gitPerl 'perl.exe')) {
        $env:PATH = "$gitPerl;$env:PATH"
        Write-Host "perl: $gitPerl (Git 自带)"
    }
    else {
        Write-Warning '未找到 perl, Qt5 configure 可能需要 (syncqt.pl)'
    }
}

# ---------- 1. 路径定义 ----------
$srcRoot = Join-Path $WorkDir "$QtVersion\src"
$installDir = Join-Path $WorkDir "$QtVersion-install\$Toolchain"
$buildRoot = Join-Path $WorkDir "$QtVersion\build-$Toolchain"

# Qt5 各组件源码标记: qtbase 有 configure.bat, 其余模块是 <模块名>.pro 工程
$srcMarkers = @{
    'qtbase'         = 'configure.bat'
    'qttools'        = 'qttools.pro'
    'qttranslations' = 'qttranslations.pro'
    'qtsvg'          = 'qtsvg.pro'
}
foreach ($c in @('qtbase', 'qttools', 'qttranslations', 'qtsvg')) {
    $marker = Join-Path $srcRoot "$c\$($srcMarkers[$c])"
    if (-not (Test-Path $marker)) {
        throw "缺少组件源码: $c ($marker 不存在, 请先运行 download-sources.ps1)"
    }
}
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

# ---------- 2. 编译 qtbase ----------
Write-Host ''
Write-Host '=========================================================='
Write-Host '==> [1/4] 编译 qtbase (qmake + jom, Debug + Release, shared)'
Write-Host '=========================================================='

$qtbaseBuild = Join-Path $buildRoot 'qtbase'
if (Test-Path $qtbaseBuild) { Remove-Item $qtbaseBuild -Recurse -Force }
New-Item -ItemType Directory -Force -Path $qtbaseBuild | Out-Null
Push-Location $qtbaseBuild
try {
    $configure = Join-Path $srcRoot 'qtbase\configure.bat'

    $qt5Args = @(
        '-debug-and-release',
        '-opensource',
        '-confirm-license',
        '-shared',
        "-prefix `"$installDir`"",
        '-nomake', 'examples',
        '-nomake', 'tests',
        '-platform', 'win32-msvc',
        # 捆绑第三方依赖, 保证可复现
        '-qt-zlib', '-qt-libpng', '-qt-libjpeg', '-qt-freetype', '-qt-pcre',
        # 桌面 OpenGL, 避免依赖 ANGLE
        '-opengl', 'desktop'
    )

    Write-Host "==> configure.bat $($qt5Args -join ' ')"
    & cmd.exe /c "call `"$configure`" $($qt5Args -join ' ')"
    if ($LASTEXITCODE -ne 0) { throw 'qtbase configure 失败' }

    # Qt5 布局: DLL 在 bin\, Debug 工具在 bin\debug\; 加入 PATH 供工具找到 Qt5Cored.dll
    $env:PATH = "$qtbaseBuild\bin;$qtbaseBuild\bin\debug;$qtbaseBuild\bin\release;$env:PATH"

    Write-Host '==> jom 构建 (Debug + Release) ...'
    jom
    if ($LASTEXITCODE -ne 0) { throw 'qtbase 构建失败' }

    Write-Host '==> jom install ...'
    jom install
    if ($LASTEXITCODE -ne 0) { throw 'qtbase 安装失败' }
}
finally {
    Pop-Location
}

# ---------- 3. 编译其余开源组件 ----------
$qmake = Join-Path $installDir 'bin\qmake.exe'
if (-not (Test-Path $qmake)) { throw "qmake 不存在: $qmake" }

$i = 2
foreach ($c in @('qttools', 'qttranslations', 'qtsvg')) {
    Write-Host ''
    Write-Host '=========================================================='
    Write-Host "==> [$i/4] 编译 $c (qmake + jom)"
    Write-Host '=========================================================='

    $src = Join-Path $srcRoot $c
    $pro = Join-Path $src "$c.pro"
    if (-not (Test-Path $pro)) { throw "缺少工程文件: $pro" }

    $build = Join-Path $buildRoot $c
    if (Test-Path $build) { Remove-Item $build -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $build | Out-Null
    Push-Location $build
    try {
        Write-Host "==> qmake $pro"
        & $qmake $pro
        if ($LASTEXITCODE -ne 0) { throw "$c qmake 失败" }

        Write-Host "==> jom 构建 $c ..."
        jom
        if ($LASTEXITCODE -ne 0) { throw "$c 构建失败" }

        Write-Host "==> jom install $c ..."
        jom install
        if ($LASTEXITCODE -ne 0) { throw "$c 安装失败" }
    }
    finally {
        Pop-Location
    }
    $i++
}

# ---------- 4. 收尾 ----------
# 复制 qt.conf (相对 Prefix), 使安装目录可整体搬移
$qtConf = Join-Path $PSScriptRoot '..\config\qt.conf'
if (Test-Path $qtConf) {
    Copy-Item $qtConf (Join-Path $installDir 'bin\qt.conf') -Force
}

Write-Host ''
Write-Host '=========================================================='
Write-Host '==> 构建完成'
Write-Host "==> 安装目录: $installDir"
Write-Host '=========================================================='

# 快速自检: Qt5 shared 构建的 DLL 位于 bin/, 确认 Release 与 Debug 均已安装
$relCore = Join-Path $installDir 'bin\Qt5Core.dll'
$dbgCore = Join-Path $installDir 'bin\Qt5Cored.dll'
if (-not (Test-Path $relCore)) { throw '自检失败: 未找到 Release 版 Qt5Core.dll' }
if (-not (Test-Path $dbgCore)) { throw '自检失败: 未找到 Debug 版 Qt5Cored.dll' }
Write-Host "自检通过: $relCore"
Write-Host "自检通过: $dbgCore"
