# qt-auto-build

基于 GitHub Actions 的 **Qt 自动化编译 · 打包 · 发布** 工程。

从 Qt 官方源码自动构建 Windows x64 版 Qt 动态库（**Release + Debug** 双配置），打包为 7z 并发布到 GitHub Releases。参考 [HelloActions-Qt](https://github.com/jaredtao/HelloActions-Qt) 与 [buildQt](https://github.com/yuanpeirong/buildQt) 的思路实现，并对构建流程做了简化与修正（使用官方支持的 Ninja Multi-Config 双配置构建）。

## 特性

- 工具链矩阵：**VS2022 x64** 与 **VS2026 x64** 并行构建
- 双配置输出：shared（动态链接）的 **Release + Debug** 一套搞定
- **仅开源组件**：只构建 qtbase / qttools / qttranslations / qtsvg，不包含任何商业模块
- 固定版本工具链（CMake 3.31.6 + Ninja 1.13.2），构建可复现
- 自动打包（7z 最大压缩）、SHA256 校验和、GitHub Release 发布

## 目录结构

```
.
├── .github/workflows/
│   └── build-qt.yml          # GitHub Actions 工作流 (构建/打包/发布)
├── scripts/
│   ├── init-tools.ps1        # 下载固定版本 CMake + Ninja 并加入 PATH
│   ├── download-sources.ps1  # 下载 4 个开源组件源码 (qt.io 官方源)
│   ├── build-qt.ps1          # configure + 编译 + 安装 (Release/Debug)
│   └── package.ps1           # 7z 打包 + SHA256 + version-info.txt
├── config/
│   └── qt.conf               # 相对 Prefix 配置, 使安装目录可整体搬移
├── README.md
└── LICENSE
```

## 工作原理

| 阶段 | 说明 |
|---|---|
| 编译 | `configure.bat -shared -debug-and-release`，Qt configure 在 PATH 中检测到 ninja 且指定 debug-and-release 时自动选用 **Ninja Multi-Config** 生成器，一个构建目录同时产出 Release 与 Debug |
| 组件 | qtbase 用官方 configure 构建；qttools / qttranslations / qtsvg 用 CMake `-G "Ninja Multi-Config" -DCMAKE_CONFIGURATION_TYPES=Debug;Release` 构建，均只构建开源协议模块 |
| 打包 | 7z 压缩（`-mx=9`），包内附 `version-info.txt`，包外附 SHA256 校验和 |
| 发布 | 一个版本一个 tag（`Qt-<版本>-x64-Release-Debug`），汇总两个工具链的包，可手动触发指定 Qt 版本 |

## 使用方法

1. 将本仓库推送到 GitHub（推送到 GitHub 后在 Actions 页面可看到 `build-qt` 工作流）。
2. 打开 **Actions → build-qt → Run workflow**，可选择：
   - `qt_version`：目标 Qt 版本（留空使用默认值；需为 qt.io 官方已发布版本，默认版本在 `build-qt.yml` 的 `inputs` 中定义）
   - `publish_release`：是否自动发布 GitHub Release（默认开启）
3. 等待构建完成（完整双配置构建约 2~4 小时，取决于 runner 规格）。构建产物会同时上传到 Artifact 与 GitHub Releases。

## 产物说明

- 发布方式：**每个版本一个 tag**（`Qt-<版本>-x64-Release-Debug`），同一 Release 下包含两个工具链的包
- 包名：`Qt-<版本>-msvc2022-x64-Release-Debug.7z` 与 `Qt-<版本>-msvc2026-x64-Release-Debug.7z`
- 包含：`bin/`（含 Qt6Core.dll / Qt6Cored.dll 等）、`lib/`、`include/`、`mkspecs/`、`translations/`、`plugins/` 等
- 校验：每个包附带同名 `.sha256.txt` 校验和

## 自动检测 Qt 新版本

`check-qt-updates` 工作流每天 02:00 UTC（北京时间 10:00）自动检查一次，也可以手动运行：

1. 抓取 qt.io 官方源，解析监控版本线（默认 `6.8`）的最新补丁版本；
2. 查询仓库 Release tag（`Qt-<版本>-x64-Release-Debug`），存在即视为该版本已构建完成；
3. 检测到官方有新版时，自动调用 `build-qt` 完成编译 → 打包 → 发布，无需人工干预。

手动检查 / 更换监控版本线：Actions → `check-qt-updates` → Run workflow，在 `qt_minor` 输入框填 `6.8` / `6.9` / `6.11` 等即可。修改定时频率：调整 `check-qt-updates.yml` 中 `schedule.cron`。

## 自定义

- **更换 Qt 版本**：Run workflow 时填写 `qt_version`，或修改 `build-qt.yml` 中 `env.QT_VERSION` 默认值。
- **调整编译器矩阵**：修改 `build-qt.yml` 的 `strategy.matrix`。当前 VS2026 使用 `windows-latest` 镜像（已内置 VS 2026 / v18.x）；待官方 `windows-2026` 稳定镜像发布后可直接改为该值。
- **自动触发**：默认仅手动触发。如需 push / tag 自动构建，取消 `build-qt.yml` 顶部注释并调整分支策略。
- **本地调试**：在已安装 VS（含 C++ 工作负载）、PowerShell 环境下可依次运行三个脚本模拟 CI 流程：
  ```powershell
  # 需先在 VS Developer PowerShell 中执行 (或 cmd: vcvarsall.bat amd64)
  # <Qt版本> 填 qt.io 官方已发布的版本号, 与 workflow 的 qt_version 输入一致
  .\scripts\init-tools.ps1 -ToolsDir .\tools
  .\scripts\download-sources.ps1 -QtVersion <Qt版本> -WorkDir .\qt -ToolsDir .\tools
  .\scripts\build-qt.ps1 -QtVersion <Qt版本> -Toolchain msvc2022 -WorkDir .\qt -ToolsDir .\tools
  .\scripts\package.ps1 -QtVersion <Qt版本> -Toolchain msvc2022 -WorkDir .\qt -DistDir .\dist
  ```

## 组件协议声明

本工程仅构建 Qt **开源协议**组件，产物遵循各组件自身许可证（均为 LGPL-3.0-only / GPL-3.0-only 双许可，详见各组件源码 `LICENSES/` 目录）：

- qtbase — Qt 核心基础库
- qttools — 开发工具（linguist、lrelease、windeployqt 等）
- qttranslations — 界面翻译文件
- qtsvg — SVG 渲染支持

构建时显式传入 `-opensource -confirm-license`。不包含 Qt WebEngine（Chromium 等）相关模块。**向下游分发二进制时请遵守 LGPL-3.0 的相关义务**（如允许反向工程以重新链接、在可接受条件下再分发等）。本仓库自身脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。

## 参考项目

- [jaredtao/HelloActions-Qt](https://github.com/jaredtao/HelloActions-Qt) — Qt 多平台 CI 打包发布示例
- [yuanpeirong/buildQt](https://github.com/yuanpeirong/buildQt) — GitHub Actions 从源码构建 Qt 并发布
- Qt 源码下载：<https://download.qt.io/official_releases/qt/>
