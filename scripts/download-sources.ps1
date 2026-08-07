# =============================================================================
# download-sources.ps1 —— 下载并解压 Qt 开源组件源码
#
# 组件协议说明 (仅开源组件):
#   只下载并构建 4 个开源协议组件, 不包含任何商业/闭源模块:
#     - qtbase          (LGPL-3.0 / GPL-3.0)  核心基础库
#     - qttools         (LGPL-3.0 / GPL-3.0)  工具 (linguist/lrelease 等)
#     - qttranslations  (LGPL-3.0 / GPL-3.0)  翻译文件
#     - qtsvg           (LGPL-3.0 / GPL-3.0)  SVG 渲染
#   来源: https://download.qt.io/official_releases/qt/<major.minor>/<version>/submodules/
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$QtVersion,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$ToolsDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# 由完整版本号推导出次要版本路径 (如 x.y.z -> x.y)
$QtVersion2 = $QtVersion.Substring(0, $QtVersion.LastIndexOf('.'))

# 仅开源组件列表
$components = @('qtbase', 'qttools', 'qttranslations', 'qtsvg')

$srcDir = Join-Path $WorkDir "$QtVersion\src"
$baseUrl = "https://download.qt.io/official_releases/qt/$QtVersion2/$QtVersion/submodules"

New-Item -ItemType Directory -Force -Path $srcDir | Out-Null

foreach ($comp in $components) {
    $extractDir = Join-Path $srcDir $comp

    if (Test-Path (Join-Path $extractDir "CMakeLists.txt")) {
        Write-Host "==> 源码已存在, 跳过下载: $comp"
        continue
    }

    # 不同 Qt 版本官方源码包命名存在差异, 依次尝试两种命名:
    #   <comp>-everywhere-src-<ver>.zip
    #   <comp>-everywhere-opensource-src-<ver>.zip
    $zipNames = @(
        "${comp}-everywhere-src-$QtVersion.zip",
        "${comp}-everywhere-opensource-src-$QtVersion.zip"
    )

    $downloaded = $false
    foreach ($candidate in $zipNames) {
        $zipPath = Join-Path $srcDir $candidate
        $url = "$baseUrl/$candidate"
        Write-Host "==> 下载 $comp (尝试命名 $candidate)"
        # -f: HTTP 404 等错误码时返回非零退出码
        curl.exe -f -L --retry 3 -sS -o $zipPath $url
        if ($LASTEXITCODE -eq 0) { $downloaded = $true; break }
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $downloaded) { throw "下载失败: $comp (两种命名均已尝试)" }

    Write-Host "==> 解压 $comp ..."
    Expand-Archive -Path $zipPath -DestinationPath $srcDir -Force
    # 压缩包内顶层目录名与 zip 命名一致, 重命名去掉版本号便于引用
    $inner = Join-Path $srcDir "${comp}-everywhere-src-$QtVersion"
    if (-not (Test-Path $inner)) { $inner = Join-Path $srcDir "${comp}-everywhere-opensource-src-$QtVersion" }
    if (Test-Path $inner) { Rename-Item $inner $extractDir }
    Remove-Item $zipPath -Force
}

Write-Host '==> 源码下载完成:'
Get-ChildItem $srcDir -Directory | Select-Object -ExpandProperty Name
