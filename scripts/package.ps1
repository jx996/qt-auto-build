# =============================================================================
# package.ps1 —— 打包 Qt 构建产物
#
# 产物:
#   - Qt-<版本>-<工具链>-x64-Release-Debug.7z   (7z 最大压缩比)
#   - 压缩包内附 version-info.txt (版本/工具链/组件/许可证说明)
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
    [string]$DistDir
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
$pkgName = "Qt-$QtVersion-$Toolchain-x64-Release-Debug"
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
链接方式    : shared (动态链接)
构建配置    : Release + Debug
开源组件    : qtbase / qttools / qttranslations / qtsvg
组件协议    : 仅开源组件 (LGPL-3.0 / GPL-3.0, 详见各组件 LICENSES/ 目录)
构建时间    : $buildTime
源码提交    : $sha
下载来源    : https://download.qt.io/official_releases/qt/
"@
$versionInfo | Out-File -FilePath (Join-Path $pkgDir 'version-info.txt') -Encoding utf8

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
