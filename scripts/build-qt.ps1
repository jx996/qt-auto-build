# =============================================================================
# build-qt.ps1 —— 编译并安装 Qt (仅开源组件, shared 动态链接, Release + Debug)
#
# 构建原理:
#   - qtbase 使用 Qt 官方 configure.bat, 指定 -shared -debug-and-release;
#     Qt configure 在 PATH 中发现 ninja 且为 debug-and-release 时,
#     会自动选用 "Ninja Multi-Config" 生成器, 从而在一个构建目录中同时
#     产出 Release 与 Debug 两个配置 (参见 qtbase configure 源码:
#     cmake/QtProcessConfigureArgs.cmake 的 generator 自动检测逻辑)。
#   - 其余组件 (qttools/qttranslations/qtsvg) 直接用 CMake 以
#     "Ninja Multi-Config" + CMAKE_CONFIGURATION_TYPES=Debug;Release 配置。
#   - 最后按 --config Release / --config Debug 分别构建并安装。
#
# 依赖:
#   - 已配置好的 MSVC x64 环境 (本工程由 ilammy/msvc-dev-cmd 提供)
#   - download-sources.ps1 已下载好的源码目录
#   - init-tools.ps1 安装的 CMake/Ninja (本脚本也会自动补到 PATH)
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
# 将固定版本工具加入 PATH (本进程内)
$cmakeDir = Join-Path $ToolsDir "cmake-3.31.6"
$ninjaDir = Join-Path $ToolsDir "ninja-1.13.2"
$env:PATH = "$cmakeDir\bin;$ninjaDir;$env:PATH"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw '未找到 cmake, 请先运行 init-tools.ps1'
}
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    throw '未找到 cl.exe, 请确保已加载 MSVC x64 环境'
}

# ---------- 0.5 Debug 运行时 PATH 补全 ----------
# 编译 Debug 配置时, rcc/moc/uic 等工具需要 Debug 版 C 运行时 DLL
# (vcruntime140d.dll / msvcp140d.dll / ucrtbased.dll)。这些 DLL 只随
# VS/SDK 分发且默认不在 PATH 上, 缺失时工具进程启动即报 0xc0000135
# (STATUS_DLL_NOT_FOUND), 表现为 Release 构建正常、Debug 构建失败。
# 这里在 VS/SDK 安装树内递归定位这些 DLL, 并将其所在目录加入 PATH。
$need = @('vcruntime140d.dll', 'msvcp140d.dll', 'ucrtbased.dll')

# 1) 确定 VS 安装路径 (优先 vswhere, 兼容非默认安装位置)
$vsRoots = @('C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio')
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vsPath = (& $vswhere -latest -products * -property installationPath 2>$null | Select-Object -First 1)
    if ($vsPath) { $vsRoots = @($vsPath) + $vsRoots }
}

$searchRoots = @()
foreach ($root in $vsRoots) {
    if (-not (Test-Path $root)) { continue }
    # 仅搜索与运行时相关的子树, 避免全盘遍历拖慢构建
    $searchRoots += "$root\VC\Redist"
    $searchRoots += "$root\VC\Tools\MSVC"
    $searchRoots += "$root\Common7\IDE\VC\VCTargets"   # 部分组件会把 CRT 放到这里
}
foreach ($kitRoot in @('C:\Program Files (x86)\Windows Kits\10\bin', 'C:\Program Files\Windows Kits\10\bin')) {
    if (Test-Path $kitRoot) { $searchRoots += $kitRoot }
}
# System32 里也可能存在 (安装了 VS 的机器)
$searchRoots += 'C:\Windows\System32'

$dllDirs = @()
foreach ($root in ($searchRoots | Select-Object -Unique)) {
    if (-not (Test-Path $root)) { continue }
    Write-Host "搜索 Debug 运行时: $root"
    foreach ($dll in $need) {
        $hit = Get-ChildItem -Path $root -Recurse -Filter $dll -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) {
            $dir = $hit.DirectoryName
            if ($dllDirs -notcontains $dir) { $dllDirs += $dir }
            Write-Host "  找到 $dll -> $dir"
        }
    }
}

foreach ($d in $dllDirs) { $env:PATH = "$d;$env:PATH" }

# 诊断: 按实际 PATH 解析验证三个 DLL
$missing = @()
foreach ($dll in $need) {
    if (Get-Command $dll -ErrorAction SilentlyContinue) { Write-Host "Debug 运行时 OK: $dll" }
    else { $missing += $dll }
}
if ($missing.Count -gt 0) {
    Write-Warning "以下 Debug 运行时 DLL 未能加入 PATH: $($missing -join ', ')"
    Write-Warning "Debug 构建可能再次报 0xc0000135; 请检查上方搜索输出"
}
# PATH 统计 (过长 PATH 也可能是 0xc0000135 的诱因之一)
$pathLen = $env:PATH.Length
$pathCount = $env:PATH.Split(';').Count
Write-Host "PATH 诊断: $pathCount 个目录, 总长 $pathLen 字符"

# ---------- 1. 路径定义 ----------
$srcRoot = Join-Path $WorkDir "$QtVersion\src"
$installDir = Join-Path $WorkDir "$QtVersion-install\$Toolchain"
$buildRoot = Join-Path $WorkDir "$QtVersion\build-$Toolchain"

$components = @('qtbase', 'qttools', 'qttranslations', 'qtsvg')
foreach ($c in $components) {
    if (-not (Test-Path (Join-Path $srcRoot "$c\CMakeLists.txt"))) {
        throw "缺少组件源码: $c (请先运行 download-sources.ps1)"
    }
}

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

# ---------- 2. 编译 qtbase ----------
Write-Host ''
Write-Host '=========================================================='
Write-Host '==> [1/4] 编译 qtbase (Release + Debug, shared)'
Write-Host '=========================================================='

$qtbaseBuild = Join-Path $buildRoot 'qtbase'
if (Test-Path $qtbaseBuild) { Remove-Item $qtbaseBuild -Recurse -Force }
New-Item -ItemType Directory -Force -Path $qtbaseBuild | Out-Null
Push-Location $qtbaseBuild
try {
    $configure = Join-Path $srcRoot 'qtbase\configure.bat'

    # 注意: 不要在引号内拆分参数; 反斜杠结尾的目录会被 cmd 特殊处理
    $qtArgs = @(
        '-shared',
        '-debug-and-release',
        '-opensource',
        '-confirm-license',
        "-prefix `"$installDir`"",
        '-nomake', 'examples',
        '-nomake', 'tests',
        # 捆绑第三方依赖, 保证可复现
        '-qt-libpng', '-qt-libjpeg', '-qt-zlib', '-qt-pcre', '-qt-freetype',
        # Windows 平台特性
        '-schannel',
        '-opengl', 'desktop',
        '-platform', 'win32-msvc'
    )

    Write-Host "==> configure.bat $($qtArgs -join ' ')"
    & cmd.exe /c "call `"$configure`" $($qtArgs -join ' ')"
    if ($LASTEXITCODE -ne 0) { throw 'qtbase configure 失败' }

    Write-Host '==> 构建 Release ...'
    cmake --build . --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'qtbase Release 构建失败' }

    Write-Host '==> 构建 Debug ...'
    cmake --build . --config Debug --parallel
    if ($LASTEXITCODE -ne 0) { throw 'qtbase Debug 构建失败' }

    Write-Host '==> 安装 Release ...'
    cmake --install . --config Release
    if ($LASTEXITCODE -ne 0) { throw 'qtbase Release 安装失败' }

    Write-Host '==> 安装 Debug ...'
    cmake --install . --config Debug
    if ($LASTEXITCODE -ne 0) { throw 'qtbase Debug 安装失败' }
}
finally {
    Pop-Location
}

# ---------- 3. 编译其余开源组件 ----------
$rest = @('qttools', 'qttranslations', 'qtsvg')
$i = 2
foreach ($c in $rest) {
    Write-Host ''
    Write-Host '=========================================================='
    Write-Host "==> [$i/4] 编译 $c (Release + Debug)"
    Write-Host '=========================================================='

    $src = Join-Path $srcRoot $c
    $build = Join-Path $buildRoot $c
    if (Test-Path $build) { Remove-Item $build -Recurse -Force }

    # 使用 Ninja Multi-Config, 一个构建目录同时产出 Debug 和 Release
    cmake -S $src -B $build -G 'Ninja Multi-Config' `
        -D"CMAKE_CONFIGURATION_TYPES=Debug;Release" `
        "-DCMAKE_PREFIX_PATH=$installDir" `
        "-DCMAKE_INSTALL_PREFIX=$installDir" `
        -DCMAKE_VERBOSE_MAKEFILE=OFF
    if ($LASTEXITCODE -ne 0) { throw "$c 配置失败" }

    Write-Host "==> 构建 $c Release ..."
    cmake --build $build --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "$c Release 构建失败" }

    Write-Host "==> 构建 $c Debug ..."
    cmake --build $build --config Debug --parallel
    if ($LASTEXITCODE -ne 0) { throw "$c Debug 构建失败" }

    Write-Host "==> 安装 $c Release ..."
    cmake --install $build --config Release
    if ($LASTEXITCODE -ne 0) { throw "$c Release 安装失败" }

    Write-Host "==> 安装 $c Debug ..."
    cmake --install $build --config Debug
    if ($LASTEXITCODE -ne 0) { throw "$c Debug 安装失败" }

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

# 快速自检: shared 构建的 DLL 位于 bin/, 确认 Release 与 Debug 均已安装
$relCore = Get-ChildItem (Join-Path $installDir 'bin') -Filter 'Qt6Core.dll' -ErrorAction SilentlyContinue
$dbgCore = Get-ChildItem (Join-Path $installDir 'bin') -Filter 'Qt6Cored.dll' -ErrorAction SilentlyContinue
if (-not $relCore) { throw '自检失败: 未找到 Release 版 Qt6Core.dll' }
if (-not $dbgCore) { throw '自检失败: 未找到 Debug 版 Qt6Cored.dll' }
Write-Host "自检通过: $($relCore.FullName)"
Write-Host "自检通过: $($dbgCore.FullName)"
