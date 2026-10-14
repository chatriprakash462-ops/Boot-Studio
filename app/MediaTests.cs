using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Web.Script.Serialization;

namespace BootStudio
{
    internal static class MediaTests
    {
        public static int Run(string source, string resultsPath)
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.Startup += async delegate
            {
                try
                {
                    var metadata = await StudioController.ProbeAsync(source);
                    string root = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(resultsPath)), "media-fixture-" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(root);
                    File.WriteAllBytes(Path.Combine(root, "BootShell.exe"), new byte[] { 1 });
                    File.Copy(source, Path.Combine(root, "original.mp4"));
                    string original = "{\"introVideo\":\"original.mp4\",\"volume\":0.1,\"maxDurationSeconds\":45,\"hideTaskbar\":true}";
                    File.WriteAllText(Path.Combine(root, "boot-intro.config.json"), original, Encoding.UTF8);
                    var store = new BootProfileStore(root);
                    var entry = store.Import(source, metadata.Duration, metadata.Width, metadata.Height);
                    var duplicate = store.Import(source, metadata.Duration, metadata.Width, metadata.Height);
                    if (entry.Id != duplicate.Id) throw new Exception("Duplicate detection failed.");
                    store.Apply(entry, 0.1);
                    if (BootProfileStore.Hash(store.CurrentVideo()) != BootProfileStore.Hash(source)) throw new Exception("Applied video does not match source.");
                    store.Undo();
                    if (File.ReadAllText(Path.Combine(root, "boot-intro.config.json"), Encoding.UTF8) != original) throw new Exception("Undo failed.");
                    string invalid = Path.Combine(root, "corrupt.mp4"); File.WriteAllText(invalid, "This is not a video.");
                    bool rejected = false;
                    try { await StudioController.ProbeAsync(invalid); } catch { rejected = true; }
                    if (!rejected) throw new Exception("Decoder accepted invalid video.");
                    File.WriteAllText(resultsPath, new JavaScriptSerializer().Serialize(new { Result = "PASS", Duration = metadata.Duration, Width = metadata.Width, Height = metadata.Height, ManagedCopy = true, DuplicateDetection = true, AppliedVideoHashMatches = true, ExactUndo = true, InvalidVideoRejected = true, Fixture = root }), Encoding.UTF8);
                    app.Shutdown(0);
                }
                catch (Exception e) { File.WriteAllText(resultsPath, "FAIL: " + e.ToString(), Encoding.UTF8); app.Shutdown(1); }
            };
            return app.Run();
        }
    }
}
