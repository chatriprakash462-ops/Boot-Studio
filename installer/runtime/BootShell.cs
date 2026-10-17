using System;
using System.Diagnostics;
using System.IO;

// Package-specific launcher. The confirmed local launcher is not overwritten.
internal static class BootShell
{
    private const int PlayerDeadlineSeconds = 180;
    [STAThread]
    private static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        try
        {
            Log(root, "BootShell started.");
            var start = new ProcessStartInfo {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + Path.Combine(root, "Start-BootIntro.ps1") + "\" -ShellMode",
                WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true
            };
            using (var child = Process.Start(start))
            {
                if (child == null) throw new IOException("Cannot start animation player.");
                if (!child.WaitForExit(PlayerDeadlineSeconds * 1000))
                {
                    try { child.Kill(); child.WaitForExit(2000); } catch { }
                    Log(root, "Player exceeded the 180-second safety deadline.");
                    return 2;
                }
                Log(root, "Player exited with code " + child.ExitCode + ".");
                return child.ExitCode;
            }
        }
        catch (Exception ex) { Log(root, ex.ToString()); return 1; }
        finally { EnsureDesktop(root); }
    }
    private static void EnsureDesktop(string root)
    {
        try
        {
            int session = Process.GetCurrentProcess().SessionId;
            foreach (var process in Process.GetProcessesByName("explorer"))
                using (process) if (process.SessionId == session) return;
            Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")) { UseShellExecute = true });
        }
        catch (Exception ex) { Log(root, "Desktop fallback: " + ex.Message); }
    }
    private static void Log(string root, string message)
    {
        try { File.AppendAllText(Path.Combine(root, "boot-shell.log"), DateTime.Now.ToString("o") + " " + message + Environment.NewLine); }
        catch { }
    }
}
