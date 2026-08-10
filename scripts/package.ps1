# =============================================================================
# package.ps1 —— 打包 Qt 构建产物
#
# 产物:
#   - Qt-<版本>-<工具链>-x64-<链接方式>-Release-Debug.7z   (7z 最大压缩比)
#     (链接方式: shared=动态链接库 / static=静态链接库)
#   - 压缩包内附 version-info.txt 与 licenses/ 许可协议
#   - dist 目录下附带 <包名>.sha256.txt 校验和
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$QtVersion,

    [Parameter(Mandatory = $true)]
    [string]$Toolchain,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$DistDir,

    # 链接方式: shared=动态链接 / static=静态链接 (用于包名与发布标识)
    [string]$LinkType = 'shared'
)

$ErrorActionPreference = 'Stop'

$installParent = Join-Path $WorkDir "$QtVersion-install"
$installDir = Join-Path $installParent $Toolchain

if (-not (Test-Path $installDir)) {
    throw "未找到安装目录: $installDir (请先运行 build-qt.ps1)"
}

if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    throw '未找到 7z (GitHub windows runner 已预装; 本地调试需安装 7-Zip 并加入 PATH)'
}

# ---------- 1. 包名与目录整理 ----------
# 命名规则: Qt-<版本>-<工具链>-<架构>-<链接方式>-<配置>
$pkgName = "Qt-$QtVersion-$Toolchain-x64-$LinkType-Release-Debug"
$pkgDir = Join-Path $installParent $pkgName

if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
Rename-Item $installDir $pkgDir

# 将 DistDir 转为绝对路径: 下方 7z 会在 Push-Location 后的目录中执行,
# 若保持相对路径, 压缩包会被写到错误的目录 (与之前打包失败一致)
$DistDir = (New-Item -ItemType Directory -Force -Path $DistDir).FullName
$archive = Join-Path $DistDir "$pkgName.7z"

# ---------- 2. 写入版本说明 ----------
$buildTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')
$sha = (git rev-parse HEAD 2>$null | Out-String).Trim()

$versionInfo = @"
Qt 构建产物说明
===============
Qt 版本     : $QtVersion
工具链      : $Toolchain (x64)
链接方式    : $LinkType ($(if ($LinkType -eq 'static') { '静态链接' } else { '动态链接' }))
构建配置    : Release + Debug
开源组件    : qtbase / qttools / qttranslations / qtsvg
组件协议    : 仅开源组件 (LGPL-3.0 / GPL-3.0, 详见各组件 LICENSES/ 目录)
构建时间    : $buildTime
源码提交    : $sha
下载来源    : https://download.qt.io/official_releases/qt/
"@
$versionInfo | Out-File -FilePath (Join-Path $pkgDir 'version-info.txt') -Encoding utf8

# ---------- 2.5 打包许可协议 ----------
# 复制各组件源码自带的 LICENSES/ 与 LICENSE 文件 (含 LGPL-3.0 / GPL-3.0 全文),
# 并附上商用合规说明, 随包分发给下游开发者。
$licRoot = Join-Path $pkgDir 'licenses'
New-Item -ItemType Directory -Force -Path $licRoot | Out-Null
$srcRoot = Join-Path $WorkDir "$QtVersion\src"
foreach ($comp in @('qtbase', 'qttools', 'qttranslations', 'qtsvg')) {
    $srcLic = Join-Path $srcRoot "$comp\LICENSES"
    if (Test-Path $srcLic) {
        Copy-Item $srcLic (Join-Path $licRoot "$comp-LICENSES") -Recurse -Force
    }
    $srcLicense = Join-Path $srcRoot "$comp\LICENSE"
    if (Test-Path $srcLicense) {
        Copy-Item $srcLicense (Join-Path $licRoot "$comp-LICENSE") -Force
    }
}
$licNote = @"
许可说明 (商用合规)
====================
本包为 Qt 开源组件构建产物, 各组件为 LGPL-3.0-only 与 GPL-3.0-only 双许可
(许可全文见本目录各组件 LICENSES/ 子目录)。

- 闭源商用产品: 选择 LGPL-3.0 条款使用即可免费商用; 动态链接且不修改库本体时
  义务最轻 (附带本许可文本、保留版权声明、提供源码获取方式);
- 静态链接: LGPL-3.0 允许, 但须履行第 4 条"可重新链接"义务 (向用户提供库的
  目标文件或等效机制、附带许可文本、提供源码/书面要约);
- 不履行上述义务的静态链接商用, 需购买 Qt 商业许可。

源码获取: https://download.qt.io/official_releases/qt/
"@
$licNote | Out-File -FilePath (Join-Path $licRoot '许可说明.txt') -Encoding utf8

# ---------- 3. 7z 压缩 ----------
Write-Host "==> 压缩 $pkgName ..."
Push-Location $installParent
try {
    $sevenOut = 7z a $archive $pkgName -mx=9 -mmt=on 2>&1
    if ($LASTEXITCODE -ne 0) {
        $sevenOut | Select-Object -Last 15 | ForEach-Object { Write-Host "   $_" }
        throw "7z 压缩失败 (exit $LASTEXITCODE)"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $archive)) { throw "压缩产物缺失: $archive" }

# ---------- 4. SHA256 校验和 ----------
$hash = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLower()
$checksumFile = Join-Path $DistDir "$pkgName.sha256.txt"
"$hash  $pkgName.7z" | Out-File -FilePath $checksumFile -Encoding ascii

Write-Host '==> 打包完成:'
Write-Host "    包: $archive"
Write-Host "    大小: $([math]::Round((Get-Item $archive).Length / 1MB, 1)) MB"
Write-Host "    SHA256: $hash"
