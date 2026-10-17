# Boot Studio v0.25 测试发行版

本次发行编号为 v0.25，程序内部版本 0.2.5.5（0.2.5-preview.5）。它是包含完整安装与卸载流程的新测试构建，不等同于早期 0.2.5-preview 二进制文件。

Boot Studio 可导入、预览和切换 Windows 登录后的全屏视频。顺序为：账号登录 → 动画 → 桌面。它不能覆盖联想标志、系统引导转圈或账号登录界面，也不会设置自动登录或更改密码。无需 Wallpaper Engine。

## 下载与系统要求

普通用户只需下载 `BootStudio_Setup.exe`。这是包含所需程序、DLL、PowerShell 脚本、默认配置、许可证、默认动画《新宿决战·雨爱版》和生成的备用测试视频的安装包，不需要 Visual Studio、.NET SDK、Python 或 FFmpeg。

- Windows 10/11 x64，建议 Windows 10 22H2 或 Windows 11。
- .NET Framework 4.8 或更新的兼容版本；安装器会检查版本。Windows 11 已包含相应运行时，较旧 Windows 10 可能需要先安装微软运行时。
- Windows PowerShell 5.1、WPF、任务计划程序及 Windows 视频解码组件可用。Windows N/KN 可能需要 Media Feature Pack。
- 当前账号允许注册自己的交互登录任务；受组织策略限制的电脑可能无法启用。
- 程序连同附带动画约数十 MB；导入视频额外占用磁盘空间。单视频最多 1 GB、120 秒（两分钟），支持 MP4/WMV/M4V/MOV 容器，实际取决于系统解码能力；建议 H.264 + AAC MP4。

微软运行时说明：https://learn.microsoft.com/dotnet/framework/install/on-windows-and-server
运行时下载：https://dotnet.microsoft.com/download/dotnet-framework/net48

## 安装

1. 在要使用动画的 Windows 账号中运行安装包，不要切换到另一个管理员账号安装。
2. 阅读并接受 PolyForm Noncommercial 1.0.0 使用许可。
3. 默认启用登录动画入口，可选择创建桌面快捷方式。开始菜单快捷方式始终创建。
4. 安装到当前账号 `%LOCALAPPDATA%\BootStudio`。安装前会保存原 Shell 设置；启用后用独立任务核验。
5. 安装完成后打开应用。默认使用附带的《新宿决战·雨爱版》（约 1 分 50 秒），视频库另有 6 秒生成测试图供备用；导入自己的视频即可替换。

已有其他自定义 Shell 或受管理的 Shell 策略时，安装器不会覆盖。发现非空旧安装目录会停止，需先用原版卸载。旧预览版可能保留数据；只有确认恢复普通启动后，才可把旧数据目录备份移走再安装。

## 使用

点击“导入视频”，选择本地文件。默认“导入后自动设为开机动画”；也可以取消自动应用，预览后点“设为开机动画”。应用复制视频到自己的目录，后续删除原文件不会影响已导入副本。

下一次登录生效。Escape 或 Space 可跳过动画。音量保存在应用配置中。120 秒（两分钟）是本版导入限制；播放时限另留 5 秒解码/淡出余量，启动器另有 180 秒硬超时和登录后 210 秒桌面恢复保护。

关闭动画但保留软件：运行安装目录中的 `Disable-Animation.cmd`；重新启用使用 `Enable-Animation.cmd`。这些入口不要求保存密码。

## 完整卸载

1. 关闭 Boot Studio，等待正在播放的动画结束。
2. 打开 Windows 设置 → 应用 → 已安装的应用/应用和功能 → Boot Studio → 卸载；或双击安装目录的 `Uninstall.exe`。
3. 确认卸载。先恢复原启动设置，用独立登录任务核验，再删除安装目录、配置、缓存、日志、导入视频副本、应用注册信息及本应用创建的快捷方式。
4. 成功会显示“Boot Studio 已卸载”。以后可直接重新安装，不需要手工删除旧目录。

导入视频的原始文件和用户另存的备份不会删除。应用内部的历史配置和启动备份会随完整卸载删除。默认安装前使用普通 Explorer，因此卸载后恢复普通桌面。若其他程序后来接管 Shell，卸载停止并保留文件，不擅自覆盖对方设置。

## 恢复与风险

启用前保存原始 Shell 和原恢复任务。修改失败尝试回滚；原始备份意外丢失或损坏时，仅当 Shell 仍属于本应用、整机 Shell 是 Explorer 且无自定义策略时，恢复继承系统默认 Shell。身份不符或状态不明确则拒绝删除程序。

如动画无法播放，播放器失败或超时后会尝试恢复桌面，独立登录任务提供第二层保护。若仍无桌面，可按 Ctrl+Shift+Esc 打开任务管理器，运行新任务 `explorer.exe`，再使用 `Disable-Animation.cmd`。没有软件能承诺在磁盘故障、系统策略阻止或外部篡改等所有情况下都成功恢复；不要直接删除仍被 Shell 引用的安装目录。

## 已知问题与测试范围

- 测试版，未进行代码签名，Windows 可能显示发布者未知。请核对发布附带的 SHA256SUMS.txt，不要关闭系统安全保护。
- Windows 10 与 Windows 11 各硬件、编码、多屏和第三方桌面软件组合仍需分别验证。
- 不支持自动升级、任意目录安装、跨账号迁移或登录前视频覆盖。
- 当前构建的实际测试结果见发行目录 `TEST-REPORT.md`。早期版本的虚拟机成功记录不能替代本构建测试。
- 不提供便携版：登录动画需要可靠固定安装路径和恢复任务，安装包是推荐交付形式。

## 来源、许可与素材

启动机制基于 Rantkid 的 DARLING-in-the-Windows：https://github.com/Rantkid/DARLING-in-the-Windows

Required Notice: Copyright (c) 2026 Rantkid.

随包保留 LICENSE 和 NOTICE.txt，遵守 PolyForm Noncommercial 1.0.0。只用于许可允许的非商业用途。备用测试图由 FFmpeg testsrc2 生成。附带《新宿决战·雨爱版》及其音轨，提供者已确认有权随软件公开分发，来源和媒体权利说明见 MEDIA-NOTICE.txt。软件许可证不额外授予动画、画面或音乐的权利。包内不含用户账号凭据或本机配置。
