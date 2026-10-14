using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Web.Script.Serialization;

namespace BootStudio
{
    internal static class StoreTests
    {
        private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
        public static int Run(string resultsPath)
        {
            string root = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(resultsPath)), "fixture-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var serializer = new JavaScriptSerializer();
                string original = "{\"introVideo\":\"old.mp4\",\"volume\":0.1,\"maxDurationSeconds\":45,\"wallpaperEngineExe\":\"E:\\\\keep\\\\wallpaper64.exe\",\"unknownSetting\":{\"nested\":true}}";
                File.WriteAllText(Path.Combine(root, "boot-intro.config.json"), original, Encoding.UTF8);
                File.WriteAllBytes(Path.Combine(root, "BootShell.exe"), new byte[] { 1 });
                File.WriteAllBytes(Path.Combine(root, "old.mp4"), new byte[] { 2, 3 });
                string source = Path.Combine(root, "新动画.mp4"); File.WriteAllBytes(source, new byte[] { 4, 5, 6 });
                File.SetAttributes(source, File.GetAttributes(source) | FileAttributes.ReadOnly);
                var store = new BootProfileStore(root);
                var entry = store.Import(source, 15, 1920, 1080);
                Assert(File.Exists(store.Resolve(entry.Path)), "Import did not copy the file.");
                Assert((File.GetAttributes(store.Resolve(entry.Path)) & FileAttributes.ReadOnly) == 0, "Managed import retained source read-only attribute.");
                Assert((File.GetAttributes(source) & FileAttributes.ReadOnly) != 0, "Import changed the source attributes.");
                File.SetAttributes(source, File.GetAttributes(source) & ~FileAttributes.ReadOnly);
                File.Delete(source);
                Assert(File.Exists(store.Resolve(entry.Path)), "Managed video depends on the source file.");
                string backup = store.Apply(entry, 0.25);
                Assert(File.ReadAllText(backup, Encoding.UTF8) == original, "Original configuration was not backed up exactly.");
                var config = store.ReadConfig();
                Assert(Convert.ToString(config["introVideo"]) == entry.Path, "Video selection was not applied.");
                Assert(Convert.ToString(config["wallpaperEngineExe"]) == "E:\\keep\\wallpaper64.exe", "Wallpaper Engine configuration changed.");
                Assert(config.ContainsKey("unknownSetting"), "Unknown configuration was discarded.");
                string applied = File.ReadAllText(Path.Combine(root, "boot-intro.config.json"), Encoding.UTF8);
                File.AppendAllText(store.Resolve(entry.Path), "changed");
                bool rejected = false; try { store.Apply(entry, 0.9); } catch (InvalidDataException) { rejected = true; }
                Assert(rejected, "Modified video was accepted without validation.");
                Assert(File.ReadAllText(Path.Combine(root, "boot-intro.config.json"), Encoding.UTF8) == applied, "Failed apply changed the active configuration.");
                store.Undo();
                Assert(File.ReadAllText(Path.Combine(root, "boot-intro.config.json"), Encoding.UTF8) == original, "Undo did not recover exact original configuration.");
                rejected = false; try { store.Import(Path.Combine(root, "old.mp4"), 60, 1920, 1080); } catch (InvalidDataException) { rejected = true; }
                Assert(rejected, "Overlong video was accepted.");
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(resultsPath)));
                File.WriteAllText(resultsPath, "PASS: managed import, source independence, config preservation, exact backup, integrity rejection, failure leaves config intact, exact undo, duration guard.\r\nTest runtime: " + root, Encoding.UTF8);
                return 0;
            }
            catch (Exception e) { File.WriteAllText(resultsPath, "FAIL: " + e.ToString(), Encoding.UTF8); return 1; }
        }
    }
}
