# Boot Studio 桌面应用 0.2.5.3

这是登录动画安装版中的 Windows 桌面应用，效果为“账号登录界面 → 动画 → 桌面”。安装程序负责配置 BootShell 与恢复保护，应用负责视频库、预览和切换。

## 使用

普通用户先运行仓库 `release/BootStudio_Setup.exe`，再从开始菜单或桌面快捷方式打开应用。安装位置为当前账号 `%LOCALAPPDATA%\BootStudio`。源码构建输出为 `app\bin\BootStudio.exe`，源码运行需要另行配置入口，不等于已安装。

点击“导入视频”选择本地视频，也可以把一个视频拖到预览区域。默认勾选“导入后自动设为开机动画”：通过 Windows 解码、时长和复制完整性检查后，立即切换下次登录使用的视频。关闭该选项可先预览，再点击“设为开机动画”。音量在应用动画时保存。

视频复制到运行目录的 `media\imports`，原文件移动或删除不影响开机播放。视频库和每次切换前的配置保存在 `boot-studio-data`。使用“撤回上次切换”恢复上次视频和配置；安装版的备份入口打开自己的安装配置备份目录，不包含其他电脑的个人恢复资料。

支持 MP4、WMV、M4V、MOV，具体编码以 Windows 能否解码为准；推荐 H.264 视频 + AAC 音频的 MP4。文件上限 1 GB，时长不能超过当前 `maxDurationSeconds`，安装版默认 45 秒。损坏、无画面、无法解码或超时的文件不会覆盖当前开机配置。

应用从 `app\bin` 自动定位项目根目录，也支持 `BootStudio.exe --root "运行目录"`。不要把 exe 单独移动到其他文件夹，建议使用根目录启动入口。

## 当前范围

本版本管理已完成配置的电脑，不自动安装或改写 Windows Shell、计划任务、自动登录或账号密码。若启动入口未配置，允许导入和预览，并禁用“设为开机动画”。它保留现有桌面恢复保护，不替换登录界面。

切换仅更新 `boot-intro.config.json` 中的 `introVideo` 和 `volume`，保留 Wallpaper Engine 配置及其他未知字段。采用临时文件和替换操作保存配置，同时保存旧配置。没有应用时不会改动当前配置。

## 构建与验证

依赖 Windows 的 .NET Framework 4.8 和 WPF，不需要安装 .NET SDK 或下载 NuGet 包。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\Build.ps1 -Test
```

输出 `app\bin\BootStudio.exe`。`-Test` 在独立测试目录验证导入副本、原文件独立性、配置保留、备份、视频校验和撤回，不写当前真实配置。真实解码集成检查：

```powershell
.\app\bin\BootStudio.exe --media-test "视频绝对路径.mp4" "结果绝对路径.json"
```

## 来源与许可证

启动播放机制来自 [Rantkid / DARLING-in-the-Windows](https://github.com/Rantkid/DARLING-in-the-Windows)。原作者版权声明与项目根目录的 PolyForm Noncommercial 1.0.0 许可证继续保留。此应用及所复用的代码按根目录许可证用于获准的非商业用途；不分发个人视频或第三方素材。
