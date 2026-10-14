using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BootStudioInstaller
{
    public sealed class PayloadFile { public string Path { get; set; } public string Hash { get; set; } }
    public sealed class PayloadManifest { public string Product { get; set; } public string Version { get; set; } public string OwnerSid { get; set; } public List<PayloadFile> Files { get; set; } }
    internal static class Installer
    {
        internal static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
        internal static string DefaultRoot { get { return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BootStudio"); } }
        internal static string Hash(string path)
        {
            using(var input=File.OpenRead(path)) using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "");
        }
        internal static string SafePath(string root, string relative)
        {
            if(string.IsNullOrWhiteSpace(relative) || System.IO.Path.IsPathRooted(relative) || relative.Contains(":")) throw new InvalidDataException("Invalid package path.");
            if(relative.Split('/', '\\').Any(part => part == ".." || part == "." || part.Length == 0)) throw new InvalidDataException("Invalid package path.");
            string full=System.IO.Path.GetFullPath(System.IO.Path.Combine(root,relative.Replace('/', '\\')));
            if(!full.StartsWith(System.IO.Path.GetFullPath(root).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Package path escapes the installation directory.");
            string parent=System.IO.Path.GetDirectoryName(full);
            while(!string.IsNullOrEmpty(parent))
            {
                if(Directory.Exists(parent) && (File.GetAttributes(parent)&FileAttributes.ReparsePoint)!=0) throw new IOException("Installation refuses directory links.");
                parent=System.IO.Path.GetDirectoryName(parent);
            }
            return full;
        }
        internal static PayloadManifest Extract(string root, string owner)
        {
            root=System.IO.Path.GetFullPath(root);
            if(Directory.Exists(root) && Directory.EnumerateFileSystemEntries(root).Any()) throw new IOException("目标目录已有文件。请使用已有安装，或先卸载。安装程序不会覆盖现有配置。");
            var written=new List<string>();
            try
            {
                using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("BootStudio.Payload.zip"))
                using(var zip=new ZipArchive(stream,ZipArchiveMode.Read))
                {
                    var manifestEntry=zip.GetEntry("payload-manifest.json");
                    if(manifestEntry==null) throw new InvalidDataException("Package manifest is missing.");
                    PayloadManifest manifest;
                    using(var reader=new StreamReader(manifestEntry.Open(),Encoding.UTF8)) manifest=Json.Deserialize<PayloadManifest>(reader.ReadToEnd());
                    if(manifest==null || manifest.Product!="BootStudio.Install" || manifest.Files==null || manifest.Files.Count>64) throw new InvalidDataException("Invalid package manifest.");
                    var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    long size=0;
                    foreach(var file in manifest.Files)
                    {
                        string destination=SafePath(root,file.Path);
                        if(!paths.Add(file.Path.Replace('/', '\\'))) throw new InvalidDataException("Duplicate package file.");
                        var entry=zip.Entries.SingleOrDefault(e=>string.Equals(e.FullName.Replace('\\','/'),file.Path.Replace('\\','/'),StringComparison.Ordinal));
                        if(entry==null) throw new InvalidDataException("Package file is missing: "+file.Path);
                        size+=entry.Length;
                        if(size>16*1024*1024) throw new InvalidDataException("Package exceeds its expected size.");
                        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination));
                        using(var input=entry.Open()) using(var output=new FileStream(destination,FileMode.CreateNew)) input.CopyTo(output);
                        written.Add(destination);
                        if(Hash(destination)!=file.Hash) throw new InvalidDataException("Package checksum mismatch: "+file.Path);
                    }
                    manifest.OwnerSid=owner;
                    // The generated playback config is retained during uninstall, not treated as a program file.
                    manifest.Files=manifest.Files.Where(f=>f.Path!="boot-intro.config.json").ToList();
                    string marker=System.IO.Path.Combine(root,"install-manifest.json");
                    File.WriteAllText(marker,Json.Serialize(manifest),new UTF8Encoding(false)); written.Add(marker);
                    return manifest;
                }
            }
            catch { foreach(string path in written.AsEnumerable().Reverse()) if(File.Exists(path)) File.Delete(path); throw; }
        }
        internal static void CheckEnvironment()
        {
            if(!Environment.Is64BitOperatingSystem) throw new NotSupportedException("此测试版本需要 64 位 Windows。");
            using(var key=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
                if(key==null || Convert.ToInt32(key.GetValue("Release",0))<528040) throw new NotSupportedException("需要 .NET Framework 4.8。请通过微软官方安装程序安装后再运行。\nhttps://dotnet.microsoft.com/download/dotnet-framework/net48");
            using(var key=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                int build;
                if(key==null || !int.TryParse(Convert.ToString(key.GetValue("CurrentBuildNumber")),out build) || build<10240) throw new NotSupportedException("此版本面向 Windows 10/11。");
            }
            if(Process.GetCurrentProcess().SessionId==0) throw new InvalidOperationException("请从准备使用动画的 Windows 账号桌面运行安装包。");
        }
        internal static void RegisterApplication(string root, bool desktopShortcut)
        {
            string ps=System.IO.Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe");
            using(var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\BootStudio"))
            {
                key.SetValue("DisplayName","Boot Studio v0.25 (Test)"); key.SetValue("DisplayVersion","0.2.5.3");
                key.SetValue("Publisher","Boot Studio contributors"); key.SetValue("InstallLocation",root);
                key.SetValue("UninstallString","\""+System.IO.Path.Combine(root,"Uninstall.exe")+"\"");
                key.SetValue("DisplayIcon",System.IO.Path.Combine(root,@"app\bin\BootStudio.exe"));
                key.SetValue("NoModify",1,RegistryValueKind.DWord); key.SetValue("NoRepair",1,RegistryValueKind.DWord);
            }
            Type type=Type.GetTypeFromProgID("WScript.Shell"); dynamic shell=Activator.CreateInstance(type);
            CreateShortcut(root,Environment.GetFolderPath(Environment.SpecialFolder.Programs));
            if(desktopShortcut) CreateShortcut(root,Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
        }
        internal static void CreateShortcut(string root,string folder)
        {
            Type type=Type.GetTypeFromProgID("WScript.Shell"); dynamic shell=Activator.CreateInstance(type);
            string shortcut=System.IO.Path.Combine(folder,"Boot Studio.lnk");
            dynamic link=shell.CreateShortcut(shortcut);
            if(!File.Exists(shortcut) || string.Equals((string)link.TargetPath,System.IO.Path.Combine(root,@"app\bin\BootStudio.exe"),StringComparison.OrdinalIgnoreCase))
            {
                link.TargetPath=System.IO.Path.Combine(root,@"app\bin\BootStudio.exe"); link.WorkingDirectory=root; link.Description="Boot Studio 登录动画管理"; link.Save();
            }
        }
        internal static string Configure(string root)
        {
            var info=new ProcessStartInfo {
                FileName=System.IO.Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+System.IO.Path.Combine(root,@"maintenance\Invoke-Startup.ps1")+"\" -Action Enable -Root \""+root+"\"",
                UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true
            };
            using(var child=Process.Start(info))
            {
                Task<string> output=child.StandardOutput.ReadToEndAsync(), error=child.StandardError.ReadToEndAsync();
                child.WaitForExit(); Task.WaitAll(output,error);
                File.WriteAllText(System.IO.Path.Combine(root,"installation-result.txt"),output.Result+Environment.NewLine+error.Result,Encoding.UTF8);
                if(child.ExitCode!=0) throw new InvalidOperationException(DescribeFailure(output.Result,error.Result));
                return output.Result;
            }
        }
        internal static string DescribeFailure(string output,string error)
        {
            string code="", detail=(output??"")+"\n"+(error??"");
            try {
                var result=Json.Deserialize<Dictionary<string,object>>(output);
                if(result!=null && result.ContainsKey("Code")) code=Convert.ToString(result["Code"]);
            } catch { }
            string message;
            if(code=="ExistingCustomShell" || detail.Contains("Another custom user Shell"))
                message="检测到此账号已有另一个动画或自定义 Shell 入口。\n本次启用已停止，没有覆盖原启动入口。\n请继续使用原来的动画管理应用；新安装的应用目前只能预览。";
            else if(code=="TaskTimeout" || detail.Contains("Timed out while waiting"))
                message="启动配置任务等待超时，尚未确认配置结果。\n请求已过期；稍后启动的任务不会继续配置 Shell。\n程序和恢复文件已保留，请先核对启动状态。";
            else if(code=="RequestExpired") message="启动配置请求已超时或取消，本次未继续配置。";
            else if(code=="ManagedShellPolicy" || code=="MachineShellConflict") message="此电脑使用受管理的 Shell 策略或整机自定义 Shell。\n为保留现有环境，安装程序已停止启用。";
            else message="启动入口配置未完成。程序和恢复文件已保留。";
            return message+"\n\n详细记录：安装目录中的 installation-result.txt。";
        }
    }
    internal sealed class SetupWindow : Form
    {
        private readonly Button install = new Button(), open = new Button();
        private readonly CheckBox agree = new CheckBox(), enable = new CheckBox(), desktop = new CheckBox();
        private readonly Label status = new Label();
        private bool installing;
        internal SetupWindow()
        {
            Text="Boot Studio v0.25 安装 · 测试版"; ClientSize=new Size(660,585); StartPosition=FormStartPosition.CenterScreen;
            FormBorderStyle=FormBorderStyle.FixedDialog; MaximizeBox=false; Font=new Font("Microsoft YaHei UI",10);
            Controls.Add(new Label { Text="Boot Studio", Font=new Font("Microsoft YaHei UI",23,FontStyle.Bold), Bounds=new Rectangle(25,18,600,45) });
            Controls.Add(new Label { Text="安装到当前账号："+Installer.DefaultRoot+"\n效果：账号登录 → 动画 → 桌面。导入自己的视频后生效。\n不会设置自动登录或修改账号密码，附带生成的测试动画，不含第三方素材。", Bounds=new Rectangle(25,77,605,90) });
            var license=new TextBox { Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,Bounds=new Rectangle(25,170,610,180),Font=new Font("Consolas",8.5f) };
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("BootStudio.License")) using(var reader=new StreamReader(stream,Encoding.UTF8)) license.Text=reader.ReadToEnd().Replace("\r\n","\n").Replace("\n",Environment.NewLine);
            Controls.Add(license);
            agree.Text="我已阅读许可证，按许可允许的用途使用"; agree.SetBounds(25,362,600,27); Controls.Add(agree);
            enable.Text="配置登录动画入口，并备份原设置、安装桌面恢复保护"; enable.Checked=true; enable.SetBounds(25,392,610,27); Controls.Add(enable);
            desktop.Text="创建桌面快捷方式"; desktop.Checked=true; desktop.SetBounds(25,422,610,27); Controls.Add(desktop);
            status.Text="测试版：动画在账号登录后播放，安装前请保存工作。"; status.SetBounds(25,457,605,57); Controls.Add(status);
            install.Text="安装"; install.Enabled=false; install.SetBounds(395,520,110,37); Controls.Add(install);
            open.Text="打开应用"; open.Enabled=false; open.SetBounds(520,520,115,37); Controls.Add(open);
            agree.CheckedChanged+=delegate{install.Enabled=agree.Checked&&!installing;};
            open.Click+=delegate{Process.Start(new ProcessStartInfo(System.IO.Path.Combine(Installer.DefaultRoot,@"app\bin\BootStudio.exe")){UseShellExecute=true});};
            install.Click+=async delegate{
                installing=true; install.Enabled=false; agree.Enabled=false; enable.Enabled=false; desktop.Enabled=false;
                bool configure=enable.Checked;
                try{
                    Installer.CheckEnvironment();
                    status.Text="正在安装程序并校验文件…";
                    await Task.Run(()=>Installer.Extract(Installer.DefaultRoot,WindowsIdentity.GetCurrent().User.Value));
                    Installer.RegisterApplication(Installer.DefaultRoot,desktop.Checked);
                    open.Enabled=true;
                    if(configure){status.Text="正在备份并配置当前账号的启动入口…"; await Task.Run(()=>Installer.Configure(Installer.DefaultRoot));}
                    status.Text=configure?"已安装并配置启动入口。打开应用导入视频，下次登录生效。":"程序已安装。当前只能预览；启用启动入口后才能切换登录动画。";
                    install.Text="已安装";
                }catch(Exception ex){status.Text="安装或启动配置未完成，详情见提示。";MessageBox.Show(this,ex.Message,"Boot Studio",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
                finally{installing=false;}
            };
            FormClosing+=delegate(object sender,FormClosingEventArgs e){if(installing){e.Cancel=true;status.Text="正在处理，请等待完成后关闭。";}};
        }
    }
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                if(args.Length==2 && args[0]=="--extract-test")
                {
                    var manifest=Installer.Extract(args[1],"TEST-USER");
                    File.WriteAllText(System.IO.Path.Combine(args[1],"extraction-result.txt"),"PASS: "+manifest.Files.Count+" program files verified; no registry, tasks or shortcuts changed."); return 0;
                }
                if(args.Length==2 && args[0]=="--diagnostics-test")
                {
                    string timeout=Installer.DescribeFailure("{\"Code\":\"TaskTimeout\"}","");
                    string conflict=Installer.DescribeFailure("{\"Code\":\"ExistingCustomShell\"}","");
                    if(timeout.Contains("另一个动画") || !timeout.Contains("超时") || !conflict.Contains("没有覆盖")) throw new InvalidDataException("Failure diagnosis mismatch.");
                    File.WriteAllText(args[1],"PASS: timeout and existing Shell conflict have distinct, accurate messages.",Encoding.UTF8); return 0;
                }
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new SetupWindow()); return 0;
            }
            catch(Exception ex)
            {
                if(args.Length==2 && args[0]=="--extract-test"){File.WriteAllText(args[1]+".error.txt",ex.ToString());}
                else MessageBox.Show(ex.Message,"Boot Studio setup");
                return 1;
            }
        }
    }
}
