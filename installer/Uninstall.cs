using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;
internal static class UninstallLauncher
{
    [STAThread] private static int Main()
    {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            string expected=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BootStudio");
            if(!string.Equals(root,expected,StringComparison.OrdinalIgnoreCase)) throw new IOException("请从 Boot Studio 安装目录运行卸载程序。");
            if(MessageBox.Show("卸载 Boot Studio，并恢复安装前的桌面启动设置？\n\n将删除安装目录内的程序、配置、日志和导入的视频副本。原始视频不会删除。请先关闭 Boot Studio。","卸载 Boot Studio",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes) return 0;
            string stage=Path.Combine(Path.GetTempPath(),"BootStudio-Uninstall-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage);
            foreach(string name in new[]{"Uninstall.ps1","Removal.Core.psm1","Invoke-Startup.ps1","Startup.Core.psm1"})
                using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
                using(var output=File.Create(Path.Combine(stage,name))) input.CopyTo(output);
            Process.Start(new ProcessStartInfo {
                FileName=Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments="-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \""+Path.Combine(stage,"Uninstall.ps1")+"\" -Root \""+root+"\" -LauncherPid "+Process.GetCurrentProcess().Id+" -ConfirmRemoval",
                UseShellExecute=false,CreateNoWindow=true
            });
            return 0;
        } catch(Exception ex){MessageBox.Show(ex.Message,"Boot Studio 卸载未完成",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
    }
}
