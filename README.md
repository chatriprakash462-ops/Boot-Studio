# Boot Studio

Windows 个性化开机动画管理器，支持本地视频导入、预览、切换及登录启动管理。

当前测试版为 **v0.25 / 0.2.5.5**，包含安装程序、桌面应用、登录动画入口、桌面恢复保护和完整卸载。播放顺序为“账号登录 → 动画 → 桌面”，不覆盖 Windows 登录界面，安装版不依赖 Wallpaper Engine。

## 下载、安装与卸载

安装后默认使用《新宿决战·雨爱版》，也可以在视频库中选择备用测试图或导入自己的视频。

普通用户下载 [BootStudio_Setup.exe](https://github.com/chatriprakash462-ops/Boot-Studio/releases/download/v0.2.5.5/BootStudio_Setup.exe)，也可进入 [GitHub Releases](https://github.com/chatriprakash462-ops/Boot-Studio/releases/tag/v0.2.5.5) 的 Assets 下载安装包。发行说明和校验记录另见 [release 目录](release)。

在要使用动画的 Windows 账号中运行安装程序，接受许可，保留启动入口选项。安装完成后打开 Boot Studio，导入有权使用的视频，默认自动设为下一次登录播放。应用复制视频到自己的目录，不修改源视频。

卸载：先关闭应用，再通过 Windows 设置 → 应用 → 已安装的应用/应用和功能 → Boot Studio → 卸载。卸载先恢复并独立核验启动设置，再清理程序、配置、导入副本、日志及快捷方式；原视频不受影响。

目标系统为 Windows 10/11 x64，需要 .NET Framework 4.8、Windows PowerShell 5.1 和系统媒体解码组件，无需安装开发环境。当前已在 Windows 11 虚拟机完成安装、导入/切换、预览、卸载及卸载后正常启动检查；用户也反馈 0.2.5.3 在干净快照和个人电脑测试成功。Windows 10 尚未实测。本版未签名，兼容性仍需更多电脑验证。

完整说明见 [release/README.md](release/README.md)，校验见 [SHA256SUMS.txt](release/SHA256SUMS.txt)，测试范围见 [TEST-REPORT.md](release/TEST-REPORT.md)。源码使用与构建见 [app/README.md](app/README.md) 和 [installer/README.md](installer/README.md)。

0.2.5.4 将视频时长上限提高至 120 秒（两分钟），同步延长播放与桌面恢复保护期限。当前构建测试范围以发行目录报告为准，旧版实测结果仅供参考。

## 来源、版权与许可

- 原始项目：[DARLING-in-the-Windows](https://github.com/Rantkid/DARLING-in-the-Windows)。
- 原作者：[Rantkid](https://github.com/Rantkid)。
- 迁移版本：`99c458439aa2ba8ab374c2484c5bf0141950b109`（上游 main），迁移日期：2026-10-09。
- 完整保留原始源码、配置模板、脚本、`LICENSE` 和作者版权声明；未导入上游 Git 提交历史。
- 原始源码继续遵守 [PolyForm Noncommercial License 1.0.0](LICENSE)。非商业用途须遵守该许可证；商业用途须先取得原作者的单独授权，私有仓库不改变这些许可条件。
- 安装包附带经提供者确认有权公开分发的《新宿决战·雨爱版》，来源和权利说明见 [媒体说明](installer/assets/MEDIA-NOTICE.txt)。素材权利不包含在源码许可证内。

Required Notice: Copyright (c) 2026 Rantkid.

## Boot Studio 安装测试版

安装包开发代码与验证方式见 [installer/README.md](installer/README.md)。发行文件包含程序、维护脚本、默认附带视频和生成的备用测试图，不包含私人视频库、本机配置或恢复备份。0.2.5.3 修复了从光盘导入只读视频导致卸载失败的问题。

下方保留最初迁移时的上游文档，供源码机制参考；普通用户请使用上方安装包，不需要执行其中的手动配置命令。安装包开发和测试记录与原始迁移记录分别保存。

迁移清单和静态阅读结果见 [MIGRATION.md](MIGRATION.md) 与 [UPSTREAM-MANIFEST.json](UPSTREAM-MANIFEST.json)。

---

# DARLING in the Windows

一个 Windows 登录开机动画系统：登录后先播放全屏动画，同时在后台启动桌面和 Wallpaper Engine，动画结束后自然进入日常桌面。

`DARLING in the Windows` 使用“当前用户 Shell Wrapper”的方式工作。Windows 登录后先启动 `BootShell.exe`，它会拉起全屏 WPF 动画遮罩，再在遮罩后面启动 `explorer.exe` 和 Wallpaper Engine。动画播放完后遮罩淡出，露出已经准备好的桌面。

## 0. 项目概览

目标效果：

```text
Windows 登录
  -> BootShell.exe
  -> 全屏 WPF 开机动画遮罩
  -> explorer.exe 和 Wallpaper Engine 在后台启动
  -> 动画淡出
  -> 进入日常桌面
```

本项目不会替换或修改 `C:\Windows\explorer.exe` 文件，只会把“当前用户”的 Shell 指向 `BootShell.exe`。如果需要恢复，执行 `RestoreShell` 即可回到普通 Windows 桌面启动流程。

## 1. 效果展示

真实启动效果演示：

[DARLING in the Windows【开机动画】](https://www.bilibili.com/video/BV1HzTD6PEST)

> 演示视频中的动画素材请替换为你自己拥有版权或授权的内容。本仓库不分发第三方版权视频素材。

## 2. 功能特性

- 登录后播放全屏开机动画。
- 动画期间隐藏桌面图标和任务栏。
- 后台启动 `explorer.exe` 和 Wallpaper Engine。
- 支持淡入、淡出、打断淡出、每次开机只播放一次。
- 支持 `Esc` 或 `Space` 跳过动画，直接进入桌面。
- 用一个总控脚本管理构建、注册、恢复、Steam 集成和完整性检查。
- 使用当前用户 Shell Wrapper，不修改系统 `explorer.exe` 文件。

## 3. 环境要求

- Windows 10 / Windows 11。
- PowerShell 5.1 或更新版本。
- 如果需要重新编译 `BootShell.exe`，需要本机可用的 .NET Framework C# 编译器。
- Wallpaper Engine 可选，但推荐搭配使用。

## 4. 项目结构

```text
DARLING-in-the-Windows
├── BootShell.cs
├── Start-BootIntro.ps1
├── Start-BootIntroHidden.vbs
├── WallpaperBoot.ps1
├── boot-intro.config.example.json
├── media
│   └── README.md
└── README.md
```

## 5. 快速开始

在项目目录打开 PowerShell：

```powershell
cd D:\DARLING-in-the-Windows
```

创建本机配置文件：

```powershell
Copy-Item .\boot-intro.config.example.json .\boot-intro.config.json
```

把自己的开机动画视频放到：

```text
media\boot-intro.mp4
```

修改 `boot-intro.config.json`，重点确认 Wallpaper Engine 路径：

```json
{
  "wallpaperEngineExe": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\wallpaper_engine\\wallpaper64.exe"
}
```

如果使用 Wallpaper Engine，并希望开机时不等待或拉起 Steam，建议先启用独立启动模式，同时关闭 Steam 和 Wallpaper Engine 自带的重复启动项：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action DisableSteamIntegration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action DisableAutostarts
```

第一条命令会创建 `nosteam.txt`，让 Wallpaper Engine 直接使用已下载的本地壁纸；需要下载或更新创意工坊内容时，按第 8 节临时恢复 Steam 集成。

先手动测试动画遮罩：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\Start-BootIntro.ps1" -Force
```

编译 `BootShell.exe`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action Build
```

手动测试 Shell Wrapper。这个命令不会修改 Windows 设置：

```powershell
.\BootShell.exe --force
```

注册当前用户 Shell Wrapper：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action RegisterShell
```

重启 Windows，测试真实登录流程。

## 6. 配置说明

本机配置文件：

```text
boot-intro.config.json
```

常用配置项：

| 配置项 | 说明 |
| --- | --- |
| `introVideo` | 开机动画视频路径。相对路径会从项目目录解析。 |
| `wallpaperEngineExe` | `wallpaper64.exe` 的路径。 |
| `playOncePerBoot` | 每次用户登录会话只播放一次；兼容 Windows 快速启动后的关机再开机。 |
| `waitForWallpaperEngineSeconds` | 遮罩后面等待 Wallpaper Engine 的时间。 |
| `hideDesktopIcons` | 动画期间隐藏桌面图标。 |
| `hideTaskbar` | 动画期间隐藏任务栏。 |
| `skipKeys` | 跳过动画的按键，默认 `Escape`、`Space`。 |
| `volume` | 开机动画音量。 |
| `fadeInMilliseconds` | 遮罩淡入时间。 |
| `fadeOutMilliseconds` | 正常结束时的淡出时间。 |
| `skipFadeOutMilliseconds` | 手动跳过时的淡出时间。 |
| `maxDurationSeconds` | 动画最长播放时间。 |

## 7. 命令参考

所有管理操作都走同一个入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action <ActionName>
```

常用动作：

| 动作 | 说明 |
| --- | --- |
| `Status` | 查看当前 Shell、计划任务、Wallpaper Engine 和保护状态。 |
| `Build` | 从 `BootShell.cs` 编译 `BootShell.exe`。 |
| `RegisterShell` | 为当前用户启用 Shell Wrapper。 |
| `RestoreShell` | 恢复普通 `explorer.exe` Shell。 |
| `DisableSteamIntegration` | 创建 `nosteam.txt`，让 Wallpaper Engine 不拉起 Steam。 |
| `EnableSteamIntegration` | 删除 `nosteam.txt`，用于创意工坊下载和更新。 |
| `DisableAutostarts` | 关闭 Steam / Wallpaper Engine 自身开机启动项。 |
| `RestoreAutostarts` | 从备份恢复启动项。 |
| `RestoreDesktop` | 恢复任务栏和桌面图标。 |
| `Protect` | 设置核心文件只读，并生成 SHA256 清单。 |
| `Unprotect` | 编辑前解除只读保护。 |
| `Check` | 根据 SHA256 清单检查核心文件。 |
| `Snapshot` | 运行高风险脚本前保存系统快照。 |
| `Compare` | 对比当前系统状态和快照。 |

## 8. Wallpaper Engine 与 Steam

Wallpaper Engine 可以直接从安装目录启动：

```text
...\Steam\steamapps\common\wallpaper_engine\wallpaper64.exe
```

如果不想开机时拉起 Steam：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action DisableSteamIntegration
```

需要下载或更新创意工坊壁纸时，临时恢复 Steam 集成：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action EnableSteamIntegration
```

更新完成后，退出 Steam 和 Wallpaper Engine，再切回开机优化状态：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action DisableSteamIntegration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action DisableAutostarts
```

## 9. 恢复与应急

恢复普通 Windows Shell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action RestoreShell
```

如果登录后没有出现桌面：

```text
Ctrl + Shift + Esc
任务管理器
运行新任务
```

然后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\DARLING-in-the-Windows\WallpaperBoot.ps1" -Action RestoreShell
```

如果任务栏或桌面图标没有恢复：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action RestoreDesktop
```

## 10. 二次开发说明

编辑核心文件前：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action Unprotect
```

编辑完成后：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action Protect
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WallpaperBoot.ps1" -Action Check
```

## 11. License

项目源码采用 [PolyForm Noncommercial License 1.0.0](LICENSE)，以源码公开方式发布。

个人学习、研究、实验及其他非商业用途可以依照许可证免费使用、修改和分发。商业展示、收费服务、商业产品集成或其他商业用途不在免费授权范围内，使用前需要取得作者的单独商业授权。

本节中文内容仅为摘要；如果与 `LICENSE` 原文存在差异，以 `LICENSE` 原文为准。媒体与壁纸素材不包含在该许可证范围内。

Required Notice: Copyright (c) 2026 Rantkid.

