# Boot Studio 迁移记录

2026-10-09 从 [Rantkid/DARLING-in-the-Windows](https://github.com/Rantkid/DARLING-in-the-Windows) 的提交 `99c458439aa2ba8ab374c2484c5bf0141950b109` 迁移到独立私有仓库。未保留上游 Git 历史，未修改上游仓库。

Required Notice: Copyright (c) 2026 Rantkid.

原始 LICENSE 按字节保留，原始源码适用 PolyForm Noncommercial 1.0.0；商业用途需另获原作者授权。仓库不包含动画、壁纸或其他第三方媒体。

## 文件清单

| 文件 | 作用 |
| --- | --- |
| BootShell.cs | C# 登录 Shell Wrapper；启动隐藏的 STA PowerShell 播放器，等待退出并在异常或结束时兜底启动 explorer.exe，记录日志。 |
| Start-BootIntro.ps1 | WPF 全屏播放器；解析配置、判断本次启动/登录会话是否已播放、管理桌面与任务栏可见性、淡入淡出、按键跳过、播放失败与超时清理。 |
| Start-BootIntroHidden.vbs | 无控制台窗口地启动 PowerShell 播放器，可供登录计划任务使用。 |
| WallpaperBoot.ps1 | 管理入口；编译、登录计划任务、当前用户 Shell 注册/恢复、Wallpaper Engine/Steam 集成、启动项备份恢复、文件完整性与系统快照。 |
| boot-intro.config.example.json | 本机配置模板，定义视频路径、音量、淡入淡出、跳过键、最长时长及可选 Wallpaper Engine 路径。 |
| media/README.md | 媒体放置说明；上游目录只有此说明，没有视频。 |
| .gitignore | 排除本机配置、日志、状态、备份、生成的 EXE 与个人媒体。 |
| LICENSE | 完整上游许可证。 |
| README.md | 增加 Boot Studio 来源、版权和迁移范围说明，并保留上游完整文档。 |

所有 9 个上游文件在导入时均用 Git blob SHA 核对通过。README 随后仅新增迁移前言；其余 8 个上游文件保持原始字节。UPSTREAM-MANIFEST.json 记录上游文件的原始哈希。

## 工作机制（静态阅读）

1. 上游默认方案需要将当前用户 Winlogon Shell 指向编译后的 BootShell.exe；这一步只存在于迁移来的脚本中，本次未执行。
2. BootShell 以 `-STA -ShellMode` 启动 Start-BootIntro.ps1。脚本读取本机配置与授权视频，创建覆盖虚拟屏幕的 WPF 窗口。
3. 窗口渲染后启动 explorer.exe；视频获得前台焦点后播放，并按配置启动 Wallpaper Engine。脚本暂时隐藏任务栏、桌面图标及可见输入法窗口。
4. 视频结束、跳过、超时或失败会触发关闭流程，正常关闭对画面与音量做淡出；finally 恢复相关窗口并确保桌面进程启动。
5. 开机时间戳和登录会话标识共同防止重复播放，成功打开媒体后才记录已播放状态，兼容快速启动场景。
6. 管理脚本还保留可选登录计划任务方案，由 VBS 隐藏启动播放器。它不是固件、UEFI 或 Windows 内核启动画面的替换机制，而是登录后的动画遮罩。

静态阅读发现：wallpaperReady 被就绪探测器设置，但当前结束流程并未用它阻止淡出；BootShell 的 WaitForExit 没有独立超时。未来可靠性开发应评估壁纸等待行为和播放器卡死时的桌面兜底。

## 验证范围

完成源文件清单、字节哈希、目录、版权、配置 JSON 与 PowerShell 语法的静态检查。未运行任何上游脚本、未编译/运行 BootShell，未创建本机运行配置，未修改 Windows Shell、注册表、计划任务或其他启动设置。运行表现尚未验证。

## 后续开发建议

- 先建立与系统启动设置分离的动画库、授权来源记录、导入和预览界面。
- 对配置进行校验和原子保存，完善多显示器、DPI、缺失视频、媒体解码失败及焦点竞争处理。
- 为启动管理建立显式启用、可验证备份、一键恢复和超时兜底；在虚拟机中验证登录流程及故障恢复。
- 保留原始许可与来源；如计划收费、商业展示或商业产品集成，先向 Rantkid 取得授权。
