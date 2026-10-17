using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace BootStudio
{
    public sealed class VideoEntry
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Path { get; set; }
        public string Hash { get; set; }
        public double Duration { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public string Subtitle { get { return Duration > 0 ? string.Format("{0:0.#} 秒 · {1} × {2}", Duration, Width, Height) : "当前使用的本地视频"; } }
    }

    public sealed class BootProfileStore
    {
        public readonly string Root;
        public readonly string Data;
        private readonly string configPath;
        private readonly JavaScriptSerializer json = new JavaScriptSerializer();
        public BootProfileStore(string root)
        {
            Root = System.IO.Path.GetFullPath(root);
            configPath = System.IO.Path.Combine(Root, "boot-intro.config.json");
            if (!File.Exists(configPath) || !File.Exists(System.IO.Path.Combine(Root, "BootShell.exe")))
                throw new InvalidOperationException("未找到已配置的动画运行目录。请从项目中的 app\\bin 打开应用。");
            ReadConfig();
            Data = System.IO.Path.Combine(Root, "boot-studio-data");
        }
        public Dictionary<string, object> ReadConfig()
        {
            var config = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(configPath, Encoding.UTF8));
            if (config == null || !config.ContainsKey("introVideo")) throw new InvalidDataException("动画配置缺少 introVideo。");
            return config;
        }
        public string CurrentVideo()
        {
            return Resolve(Convert.ToString(ReadConfig()["introVideo"]));
        }
        public string Resolve(string path)
        {
            return System.IO.Path.GetFullPath(System.IO.Path.IsPathRooted(path) ? path : System.IO.Path.Combine(Root, path));
        }
        public double CurrentVolume()
        {
            var config = ReadConfig();
            return config.ContainsKey("volume") ? Convert.ToDouble(config["volume"]) : 0.1;
        }
        public double MaximumDuration()
        {
            var config = ReadConfig();
            double maximum = config.ContainsKey("maxDurationSeconds") ? Convert.ToDouble(config["maxDurationSeconds"]) : 120;
            return maximum > 0 && !double.IsInfinity(maximum) ? Math.Min(maximum, 120) : 120;
        }
        public List<VideoEntry> Library()
        {
            string path = System.IO.Path.Combine(Data, "library.json");
            var result = File.Exists(path) ? json.Deserialize<List<VideoEntry>>(File.ReadAllText(path, Encoding.UTF8)) : new List<VideoEntry>();
            result = result ?? new List<VideoEntry>();
            string current = CurrentVideo();
            if (File.Exists(current) && !result.Any(item => string.Equals(Resolve(item.Path), current, StringComparison.OrdinalIgnoreCase)))
                result.Insert(0, new VideoEntry { Id = "existing", Name = System.IO.Path.GetFileNameWithoutExtension(current), Path = current });
            return result;
        }
        public VideoEntry Import(string source, double duration, int width, int height)
        {
            if (!File.Exists(source)) throw new FileNotFoundException("找不到选中的视频。", source);
            if (new FileInfo(source).Length > 1024L * 1024 * 1024) throw new InvalidDataException("视频超过 1 GB，请先压缩后导入。");
            if (double.IsNaN(duration) || double.IsInfinity(duration) || duration <= 0 || duration > MaximumDuration()) throw new InvalidDataException(string.Format("请使用时长在 {0:0} 秒以内的视频，以匹配当前开机播放时限。", MaximumDuration()));
            if (width <= 0 || height <= 0) throw new InvalidDataException("文件没有可播放的视频画面。");
            string ext = System.IO.Path.GetExtension(source).ToLowerInvariant();
            if (ext != ".mp4" && ext != ".wmv" && ext != ".m4v" && ext != ".mov") throw new InvalidDataException("请选择 MP4、WMV、M4V 或 MOV 视频。");
            string hash = Hash(source);
            var library = Library();
            var existing = library.FirstOrDefault(item => item.Hash == hash && File.Exists(Resolve(item.Path)));
            if (existing != null) return existing;
            string id = Guid.NewGuid().ToString("N");
            string relative = "media\\imports\\" + id + ext;
            string destination = Resolve(relative);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination));
            string temp = destination + ".importing";
            try
            {
                File.Copy(source, temp, false);
                // A CD/download's read-only attribute must not become a property of our managed copy.
                File.SetAttributes(temp, File.GetAttributes(temp) & ~FileAttributes.ReadOnly);
                if (Hash(temp) != hash) throw new IOException("视频复制校验失败，请重新导入。");
                File.Move(temp, destination);
                var entry = new VideoEntry { Id = id, Name = System.IO.Path.GetFileNameWithoutExtension(source), Path = relative, Hash = hash, Duration = duration, Width = width, Height = height };
                library.Add(entry);
                Directory.CreateDirectory(Data);
                WriteAtomic(System.IO.Path.Combine(Data, "library.json"), json.Serialize(library), null);
                return entry;
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        public string Apply(VideoEntry entry, double volume)
        {
            if (entry == null || !File.Exists(Resolve(entry.Path))) throw new FileNotFoundException("视频不存在，请重新导入。");
            if (entry.Hash != null && Hash(Resolve(entry.Path)) != entry.Hash) throw new InvalidDataException("视频已被修改，请重新导入并检查。");
            var config = ReadConfig();
            config["introVideo"] = entry.Path;
            config["volume"] = Math.Max(0, Math.Min(1, volume));
            Directory.CreateDirectory(System.IO.Path.Combine(Data, "config-history"));
            string backup = System.IO.Path.Combine(Data, "config-history", DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N") + ".json");
            WriteAtomic(configPath, json.Serialize(config), backup);
            return backup;
        }
        public string Undo()
        {
            string history = System.IO.Path.Combine(Data, "config-history");
            if (!Directory.Exists(history)) throw new InvalidOperationException("还没有可撤回的切换。");
            string previous = Directory.GetFiles(history, "*.json").OrderByDescending(path => path, StringComparer.Ordinal).FirstOrDefault();
            if (previous == null) throw new InvalidOperationException("还没有可撤回的切换。");
            string content = File.ReadAllText(previous, Encoding.UTF8);
            var config = json.Deserialize<Dictionary<string, object>>(content);
            if (config == null || !config.ContainsKey("introVideo") || !File.Exists(Resolve(Convert.ToString(config["introVideo"]))))
                throw new InvalidDataException("上次配置的视频已不存在，无法撤回。请从可用状态备份恢复。");
            string redo = System.IO.Path.Combine(Data, "撤回前配置-" + Guid.NewGuid().ToString("N") + ".json");
            WriteAtomic(configPath, content, redo);
            File.Move(previous, previous + ".restored");
            return CurrentVideo();
        }
        public bool CanUndo()
        {
            string history = System.IO.Path.Combine(Data, "config-history");
            return Directory.Exists(history) && Directory.GetFiles(history, "*.json").Length > 0;
        }
        public static string Hash(string path)
        {
            using (var stream = File.OpenRead(path)) using (var sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
        }
        public static void WriteAtomic(string path, string content, string backup)
        {
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    byte[] bytes = new UTF8Encoding(false).GetBytes(content);
                    stream.Write(bytes, 0, bytes.Length); stream.Flush(true);
                }
                if (File.Exists(path)) File.Replace(temp, path, backup);
                else File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
}
