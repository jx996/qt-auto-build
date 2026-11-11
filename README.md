# qt-auto-build

基于 GitHub Actions 的 **Qt 自动化编译 · 打包 · 发布** 工程。

从 Qt 官方源码自动构建 Windows x64 版 Qt 库（**Release + Debug** 双配置、shared 动态链接），打包为 7z 并发布到 GitHub Releases。构建采用 Qt 官方支持的 Ninja Multi-Config 生成器，一个构建目录同时产出双配置。

## 特性

- **双体系支持**：Qt5（5.15，qmake + jom）与 Qt6（Ninja Multi-Config）自动识别、各自走对应构建路径
- **工具链矩阵**：Qt6 用 VS2022 x64 + VS2026 x64 并行构建；Qt5 仅 VS2022 x64（官方支持范围），VS2026 自动跳过
- **双配置输出**：shared（动态链接）的 Release + Debug 一套构建搞定
- **仅开源组件**：只构建 qtbase / qttools / qttranslations / qtsvg，无任何商业模块，可免费商用
- **多版本自动监控**：可同时监控多条 Qt 版本线，官方发布新补丁即自动构建发布，无需人工干预
- **可复现**：固定版本工具链（CMake + Ninja + jom），不依赖 runner 镜像自带版本
- **完整交付**：7z 最大压缩 + SHA256 校验和 + 许可协议全文随包分发

## 目录结构

```
.
├── .github/workflows/
│   ├── build-qt.yml            # 构建/打包/发布工作流 (手动 + 自动触发)
│   └── check-qt-updates.yml    # 多版本线监控, 检测到新版本自动触发构建
├── scripts/
│   ├── init-tools.ps1          # 下载固定版本 CMake + Ninja + jom 并加入 PATH
│   ├── download-sources.ps1    # 下载开源组件源码 (官方源, Qt5 自动回退 archive 源)
│   ├── build-qt.ps1            # 入口: 按主版本分发 (Qt6: Ninja Multi-Config)
│   ├── build-qt5.ps1           # Qt5 构建路径 (qmake + jom, Debug + Release)
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

`check-qt-updates` 在**每次推送 main 分支后自动检查**，另每天 02:00 UTC（北京时间 10:00）定时检查一次，也可手动运行。它会：

1. 遍历**监控队列**中的每条版本线，抓取 qt.io 官方源解析该线最新补丁版本；
2. 查询仓库 Release tag（`Qt-<版本>-x64-shared-Release-Debug`），已存在即视为该版本构建完成；
3. 对每条"有新版"的线，并行调用 `build-qt` 完成编译 → 打包 → 发布。

**监控队列的配置优先级**（逗号分隔的版本线列表，如 `<主>.<次>,<主>.<次>`）：

| 方式 | 变量名 / 输入 | 取值样例 | 说明 |
|---|---|---|---|
| 手动输入 | `qt_minors` | `6.8, 6.11` | Run workflow 时在输入框填写队列，本次生效 |
| 仓库变量 | `QT_MINORS` | `6.8, 6.11` | Settings → Secrets and variables → Actions → Variables 新建，无需改代码；变量名固定为 `QT_MINORS`，值用英文逗号分隔 |
| 默认值 | — | 见 `check-qt-updates.yml` 的 `default` | 以上都未设置时生效 |

> 变量名必须与上表完全一致（区分大小写）；版本线可任意增删，例如只监控一条写 `6.8`，监控多条写 `6.8, 6.11, 6.13`。

修改定时频率：调整 `check-qt-updates.yml` 中 `schedule.cron`。

## 钉钉通知

以下三种情况会向钉钉群机器人推送通知：

- **检测到 Qt 新版本**：`check-qt-updates` 发现待构建版本并自动触发构建时；
- **构建发布成功**：`build-qt` 成功发布 Release 后（手动触发与自动调用均覆盖），消息附版本与 Release 链接；
- **构建/发布失败**：`build-qt` 的编译或发布任务失败时（手动触发与自动调用均覆盖），消息附失败任务与运行链接。

配置方式：在钉钉群添加**自定义机器人**，复制 webhook 地址（含 `access_token`），在仓库 **Settings → Secrets and variables → Actions → Secrets** 新建名为 `DINGTALK_WEBHOOK` 的机密，值为完整 webhook 地址。未配置时自动跳过通知，不影响构建。

> 必须用 **Secret** 而非 Variable：Secret 加密存储、创建后无法读回明文、日志自动脱敏；Variable 明文可见且不脱敏，会导致地址泄露。

> 机器人安全设置建议用**自定义关键词**并设为 `Qt`（所有通知均含该词）；GitHub 托管 runner 出口 IP 不固定，不要用 IP 白名单；如启用了**加签**，需额外实现签名逻辑（当前未支持）。

## Qt5 (5.15) 构建说明

Qt 5.15 与 Qt6 构建体系不同，本工程自动识别主版本走对应路径（`build-qt.ps1` 入口分发）：

- **源码**：Qt5 发布在 archive 区，`download-sources.ps1` 与版本检测均自动回退 archive 源
- **构建**：qtbase 用 `configure.bat -debug-and-release` 生成工程，`jom` 一次构建 Debug + Release 双配置；qttools / qttranslations / qtsvg 用安装后的 `qmake` + `jom` + `jom install`
- **工具链**：仅 VS2022 x64（Qt5 官方支持范围），VS2026 矩阵项在 Qt5 版本下自动跳过
- **产物**：包名/许可协议/校验和与 Qt6 完全一致（如 `Qt-5.15.19-msvc2022-x64-shared-Release-Debug.7z`）

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
- **自动触发**：`check-qt-updates` 在每次推送 main 后、每天定时各自动检查一次新版本；如需 `build-qt` 本身 push / tag 自动构建，取消 `build-qt.yml` 顶部注释并调整分支策略
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
