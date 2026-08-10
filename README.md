# qt-auto-build

基于 GitHub Actions 的 **Qt 自动化编译 · 打包 · 发布** 工程。

从 Qt 官方源码自动构建 Windows x64 版 Qt 库（**Release + Debug** 双配置、shared 动态链接），打包为 7z 并发布到 GitHub Releases。构建采用 Qt 官方支持的 Ninja Multi-Config 生成器，一个构建目录同时产出双配置。

## 特性

- **工具链矩阵**：VS2022 x64 与 VS2026 x64 并行构建，产物自动合并发布
- **双配置输出**：shared（动态链接）的 Release + Debug 一套构建搞定
- **仅开源组件**：只构建 qtbase / qttools / qttranslations / qtsvg，无任何商业模块，可免费商用
- **多版本自动监控**：可同时监控多条 Qt 版本线，官方发布新补丁即自动构建发布，无需人工干预
- **可复现**：固定版本工具链（CMake + Ninja），不依赖 runner 镜像自带版本
- **完整交付**：7z 最大压缩 + SHA256 校验和 + 许可协议全文随包分发

## 目录结构

```
.
├── .github/workflows/
│   ├── build-qt.yml            # 构建/打包/发布工作流 (手动 + 自动触发)
│   └── check-qt-updates.yml    # 多版本线监控, 检测到新版本自动触发构建
├── scripts/
│   ├── init-tools.ps1          # 下载固定版本 CMake + Ninja 并加入 PATH
│   ├── download-sources.ps1    # 下载开源组件源码 (qt.io 官方源)
│   ├── build-qt.ps1            # configure + 编译 + 安装 (Debug 优先, 双配置)
│   └── package.ps1             # 7z 打包 + SHA256 + 许可协议 + version-info
├── config/
│   └── qt.conf                 # 相对 Prefix 配置, 使安装目录可整体搬移
├── README.md
└── LICENSE
```

## 快速开始

1. 将本仓库推送到 GitHub，Actions 页面即可看到 `build-qt` 与 `check-qt-updates` 两个工作流。
2. 打开 **Actions → build-qt → Run workflow**：
   - `qt_version`：目标 Qt 版本（留空使用默认值，默认版本在 `build-qt.yml` 的 `inputs` 中定义）
   - `publish_release`：是否自动发布 GitHub Release（默认开启）
3. 等待构建完成（完整双配置构建约 2~4 小时，取决于 runner 规格）。产物会同时上传到 Artifact 与 GitHub Releases。

## 自动监控多条 Qt 版本线

`check-qt-updates` 每天 02:00 UTC（北京时间 10:00）自动检查一次，也可手动运行。它会：

1. 遍历**监控队列**中的每条版本线，抓取 qt.io 官方源解析该线最新补丁版本；
2. 查询仓库 Release tag（`Qt-<版本>-x64-shared-Release-Debug`），已存在即视为该版本构建完成；
3. 对每条"有新版"的线，并行调用 `build-qt` 完成编译 → 打包 → 发布。

**监控队列的配置优先级**（逗号分隔的版本线列表，如 `<主>.<次>,<主>.<次>`）：

| 方式 | 说明 |
|---|---|
| 手动输入 | Run workflow 时在 `qt_minors` 输入框填写队列，本次生效 |
| 仓库变量 | Settings → Secrets and variables → Actions → Variables 新建 `QT_MINORS`，无需改代码 |
| 默认值 | 以上都未设置时使用 `check-qt-updates.yml` 中的 `default` |

修改定时频率：调整 `check-qt-updates.yml` 中 `schedule.cron`。

## 产物说明

- **发布方式**：一个版本一个 tag（`Qt-<版本>-x64-shared-Release-Debug`），同一 Release 下包含两个工具链的包；`shared` = 动态链接库（将来如需静态链接变体为 `static`）
- **包名**：`Qt-<版本>-msvc2022-x64-shared-Release-Debug.7z` 与 `Qt-<版本>-msvc2026-x64-shared-Release-Debug.7z`
- **包含**：`bin/`（含 Qt6Core.dll / Qt6Cored.dll 等）、`lib/`、`include/`、`mkspecs/`、`translations/`、`plugins/`，以及 `version-info.txt` 和 `licenses/`（各组件 LGPL/GPL 许可全文 + 商用合规说明）
- **校验**：每个包附带同名 `.sha256.txt` 校验和

## 工作原理

| 阶段 | 说明 |
|---|---|
| 编译 | `configure.bat -shared -debug-and-release`；Qt configure 在 PATH 中检测到 ninja 且指定 debug-and-release 时自动选用 **Ninja Multi-Config** 生成器，一个构建目录同时产出 Release 与 Debug |
| 组件 | qtbase 用官方 configure 构建；qttools / qttranslations / qtsvg 用 CMake `-G "Ninja Multi-Config" -DCMAKE_CONFIGURATION_TYPES=Debug;Release` 构建 |
| 打包 | 7z 最大压缩，包内附 `version-info.txt` 与 `licenses/`，包外附 SHA256 校验和 |
| 发布 | release job 汇总两个工具链的包，单 tag 发布，可重复执行（自动清理同名 tag/Release） |

## 商用合规

本工程仅构建 Qt **开源协议**组件，各组件均为 **LGPL-3.0-only / GPL-3.0-only 双许可**，闭源商用产品选择 LGPL-3.0 条款即可免费使用：

- **动态链接**（当前 `shared` 构建）：不修改库本体时义务最轻——附带许可文本、保留版权声明、提供源码获取方式
- **静态链接**（如需 `static` 变体）：LGPL-3.0 允许，但须履行"可重新链接"义务（向用户提供库的目标文件或等效机制）；不履行则需购买 Qt 商业许可

构建时显式传入 `-opensource -confirm-license`，不包含 Qt WebEngine 等附加模块。压缩包内 `licenses/` 已随包分发各组件许可全文与说明。本仓库自身脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。

## 自定义

- **更换 Qt 版本**：Run workflow 时填写 `qt_version`，或修改 `build-qt.yml` 中 `env.QT_VERSION` 默认值
- **监控版本线队列**：见上文"自动监控多条 Qt 版本线"
- **调整编译器矩阵**：修改 `build-qt.yml` 的 `strategy.matrix`。当前 VS2026 使用 `windows-latest` 镜像（内置 VS 2026 / v18.x）；待官方 `windows-2026` 稳定镜像发布后可直接改为该值
- **自动触发**：默认仅手动触发 + 定时监控。如需 push / tag 自动构建，取消 `build-qt.yml` 顶部注释并调整分支策略
- **本地调试**：在已安装 VS（含 C++ 工作负载）的 PowerShell 环境下可依次运行脚本模拟 CI 流程：
  ```powershell
  # 需先在 VS Developer PowerShell 中执行 (或 cmd: vcvarsall.bat amd64)
  # <Qt版本> 填 qt.io 官方已发布的版本号, 与 workflow 的 qt_version 输入一致
  .\scripts\init-tools.ps1 -ToolsDir .\tools
  .\scripts\download-sources.ps1 -QtVersion <Qt版本> -WorkDir .\qt -ToolsDir .\tools
  .\scripts\build-qt.ps1 -QtVersion <Qt版本> -Toolchain msvc2022 -WorkDir .\qt -ToolsDir .\tools
  .\scripts\package.ps1 -QtVersion <Qt版本> -Toolchain msvc2022 -WorkDir .\qt -DistDir .\dist
  ```

## 参考项目

- [jaredtao/HelloActions-Qt](https://github.com/jaredtao/HelloActions-Qt) — Qt 多平台 CI 打包发布示例
- [yuanpeirong/buildQt](https://github.com/yuanpeirong/buildQt) — GitHub Actions 从源码构建 Qt 并发布
- Qt 源码下载：<https://download.qt.io/official_releases/qt/>
