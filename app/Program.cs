using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace BootStudio
{
    internal static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            try
            {
                if (args.Length == 2 && args[0] == "--self-test") return StoreTests.Run(args[1]);
                if (args.Length == 3 && args[0] == "--media-test") return MediaTests.Run(args[1], args[2]);
                string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
                if (args.Length == 2 && args[0] == "--root") root = Path.GetFullPath(args[1]);
                bool created;
                string key = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(root)).Replace("/", "_").Replace("+", "-");
                using (var mutex = new Mutex(true, "Local\\BootStudio-" + key, out created))
                {
                    if (!created) { MessageBox.Show("Boot Studio 已经打开，请切换到现有窗口。", "Boot Studio"); return 0; }
                    var app = new Application();
                    app.DispatcherUnhandledException += delegate(object sender, DispatcherUnhandledExceptionEventArgs e)
                    { MessageBox.Show(e.Exception.Message, "Boot Studio", MessageBoxButton.OK, MessageBoxImage.Error); e.Handled = true; };
                    using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BootStudio.MainWindow.xaml"))
                    {
                        if (stream == null) throw new FileNotFoundException("应用界面资源缺失。");
                        var window = (Window)XamlReader.Load(stream);
                        var controller = new StudioController(window, new BootProfileStore(root));
                        return app.Run(window);
                    }
                }
            }
            catch (Exception e) { MessageBox.Show(e.Message, "Boot Studio", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
        }
    }

    internal sealed class Metadata
    {
        public double Duration; public int Width; public int Height;
    }
    internal sealed class StudioController
    {
        private readonly Window window;
        private readonly BootProfileStore store;
        private readonly ListBox library;
        private readonly MediaElement preview;
        private readonly Slider volume;
        private readonly Button import, apply, play, undo;
        private bool busy, playing;
        private bool startupEnabled;
        private VideoEntry Selected { get { return library.SelectedItem as VideoEntry; } }
        private T Find<T>(string name) where T : class { return (T)window.FindName(name); }

        public StudioController(Window window, BootProfileStore store)
        {
            this.window = window; this.store = store;
            library = Find<ListBox>("LibraryList"); preview = Find<MediaElement>("Preview"); volume = Find<Slider>("Volume");
            import = Find<Button>("ImportButton"); apply = Find<Button>("ApplyButton"); play = Find<Button>("PlayButton"); undo = Find<Button>("UndoButton");
            volume.Value = Math.Max(0, Math.Min(1, store.CurrentVolume()));
            preview.Volume = volume.Value;
            Find<TextBlock>("VolumeLabel").Text = Math.Round(volume.Value * 100) + "%";
            startupEnabled = StartupEnabled();
            Find<TextBlock>("StartupStatus").Text = startupEnabled ? "●  已启用 · 下次登录播放" : "●  启动入口未配置";
            import.Click += async delegate { var dialog = new OpenFileDialog { Title = "导入开机动画", Filter = "视频文件|*.mp4;*.wmv;*.m4v;*.mov", Multiselect = false }; if (dialog.ShowDialog(window) == true) await ImportAsync(dialog.FileName); };
            apply.Click += async delegate { await ApplySelectedAsync(); };
            play.Click += delegate { TogglePreview(); };
            undo.Click += async delegate
            {
                SetBusy(true, "正在恢复上一次配置…");
                try { await Task.Run(() => store.Undo()); volume.Value = store.CurrentVolume(); RefreshLibrary(null); Notify("已撤回上次切换，下次登录将使用原动画。", false); }
                catch (Exception e) { Notify(e.Message, true); }
                finally { SetBusy(false, null); }
            };
            library.SelectionChanged += delegate { SelectVideo(); };
            volume.ValueChanged += delegate { preview.Volume = volume.Value; Find<TextBlock>("VolumeLabel").Text = Math.Round(volume.Value * 100) + "%"; };
            var drop = Find<Border>("DropZone");
            drop.DragOver += delegate(object sender, DragEventArgs e) { e.Effects = !busy && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
            drop.Drop += async delegate(object sender, DragEventArgs e)
            {
                if (busy || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
                var files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files.Length != 1) { Notify("请每次导入一段视频。", true); return; }
                await ImportAsync(files[0]);
            };
            Find<Button>("BackupButton").Click += delegate { OpenBackup(); };
            Find<Button>("AboutButton").Click += delegate
            {
                MessageBox.Show(window, "Boot Studio v0.25 (0.2.5.3)\n\n导入、预览、切换本机登录动画。\n启动机制基于 Rantkid / DARLING-in-the-Windows。\nhttps://github.com/Rantkid/DARLING-in-the-Windows\n\n遵守 PolyForm Noncommercial 1.0.0，仅用于获准的非商业用途。\n视频素材由你提供，应用不分发第三方动画。", "关于 Boot Studio", MessageBoxButton.OK, MessageBoxImage.Information);
            };
            preview.MediaOpened += delegate
            {
                Find<StackPanel>("EmptyPreview").Visibility = Visibility.Collapsed;
                if (!playing) preview.Pause();
                if (preview.NaturalDuration.HasTimeSpan)
                    Find<TextBlock>("VideoDetails").Text = string.Format("{0:0.#} 秒 · {1} × {2} · 本地视频", preview.NaturalDuration.TimeSpan.TotalSeconds, preview.NaturalVideoWidth, preview.NaturalVideoHeight);
            };
            preview.MediaEnded += delegate { playing = false; preview.Position = TimeSpan.Zero; preview.Pause(); play.Content = "▶  预览"; };
            preview.MediaFailed += delegate { playing = false; play.Content = "▶  预览"; Notify("此视频无法在 Windows 中播放。建议转换成 H.264 + AAC 的 MP4 后导入。", true); };
            window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e)
            {
                if (busy) { e.Cancel = true; Notify("正在保存，请稍候再关闭应用。", true); return; }
                preview.Close();
            };
            RefreshLibrary(null);
        }
        private bool StartupEnabled()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows NT\CurrentVersion\Winlogon"))
                {
                    string value = key == null ? null : key.GetValue("Shell") as string;
                    return value != null && string.Equals(Path.GetFullPath(value.Trim().Trim('"')), Path.Combine(store.Root, "BootShell.exe"), StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }
        private void RefreshLibrary(VideoEntry selected)
        {
            var items = store.Library();
            library.ItemsSource = items;
            string current = store.CurrentVideo();
            library.SelectedItem = selected == null ? items.FirstOrDefault(item => string.Equals(store.Resolve(item.Path), current, StringComparison.OrdinalIgnoreCase)) : items.FirstOrDefault(item => item.Id == selected.Id);
            Find<TextBlock>("LibraryCount").Text = items.Count + " 段动画 · MP4 / WMV / M4V / MOV";
            Find<TextBlock>("CurrentAnimation").Text = "当前动画：" + (items.FirstOrDefault(item => string.Equals(store.Resolve(item.Path), current, StringComparison.OrdinalIgnoreCase)) ?? new VideoEntry { Name = Path.GetFileName(current) }).Name;
            UpdateButtons();
        }
        private void SelectVideo()
        {
            playing = false; play.Content = "▶  预览"; preview.Close();
            var selected = Selected;
            Find<StackPanel>("EmptyPreview").Visibility = Visibility.Visible;
            if (selected != null)
            {
                Find<TextBlock>("VideoTitle").Text = selected.Name;
                Find<TextBlock>("VideoDetails").Text = selected.Subtitle;
                string path = store.Resolve(selected.Path);
                if (File.Exists(path)) { preview.Source = new Uri(path); preview.Play(); }
                else Notify("这个视频文件已不存在，请重新导入。", true);
            }
            UpdateButtons();
        }
        private void TogglePreview()
        {
            if (Selected == null) return;
            playing = !playing;
            if (playing) preview.Play(); else preview.Pause();
            play.Content = playing ? "Ⅱ  暂停" : "▶  预览";
        }
        private async Task ImportAsync(string source)
        {
            if (busy) return;
            SetBusy(true, "正在检查视频，原开机动画仍然保留…");
            try
            {
                var metadata = await ProbeAsync(source);
                double savedVolume = volume.Value;
                var entry = await Task.Run(() => store.Import(source, metadata.Duration, metadata.Width, metadata.Height));
                bool auto = Find<CheckBox>("AutoApply").IsChecked == true;
                if (auto && startupEnabled)
                {
                    Notify("正在保存视频和配置…", false);
                    await Task.Run(() => store.Apply(entry, savedVolume));
                    Notify("已切换为「" + entry.Name + "」，下次登录播放。原配置已自动备份。", false);
                }
                else Notify(auto ? "视频已导入。此电脑尚未配置启动入口，请先完成 BootShell 安装。" : "已导入，可以预览后点击“设为开机动画”。", auto && !startupEnabled);
                RefreshLibrary(entry);
            }
            catch (Exception e) { Notify("导入未完成：" + e.Message, true); }
            finally { SetBusy(false, null); }
        }
        private async Task ApplySelectedAsync()
        {
            var entry = Selected;
            if (entry == null || busy) return;
            SetBusy(true, "正在检查并切换动画…");
            try
            {
                var metadata = await ProbeAsync(store.Resolve(entry.Path));
                if (metadata.Duration > store.MaximumDuration()) throw new InvalidDataException("视频超出当前开机播放时限。");
                double savedVolume = volume.Value;
                await Task.Run(() => store.Apply(entry, savedVolume));
                RefreshLibrary(entry);
                Notify("「" + entry.Name + "」已设为开机动画，下次登录生效。", false);
            }
            catch (Exception e) { Notify("切换未完成：" + e.Message, true); }
            finally { SetBusy(false, null); }
        }
        internal static async Task<Metadata> ProbeAsync(string source)
        {
            if (!File.Exists(source)) throw new FileNotFoundException("找不到视频文件。");
            string extension = Path.GetExtension(source).ToLowerInvariant();
            if (!new[] { ".mp4", ".wmv", ".m4v", ".mov" }.Contains(extension)) throw new InvalidDataException("请选择 MP4、WMV、M4V 或 MOV 视频。");
            if (new FileInfo(source).Length > 1024L * 1024 * 1024) throw new InvalidDataException("视频超过 1 GB，请先压缩后导入。");
            var media = new MediaPlayer();
            var completion = new TaskCompletionSource<Metadata>();
            EventHandler opened = delegate
            {
                if (!media.HasVideo || !media.NaturalDuration.HasTimeSpan) completion.TrySetException(new InvalidDataException("文件没有可播放的视频画面或有效时长。"));
                else completion.TrySetResult(new Metadata { Duration = media.NaturalDuration.TimeSpan.TotalSeconds, Width = media.NaturalVideoWidth, Height = media.NaturalVideoHeight });
            };
            EventHandler<ExceptionEventArgs> failed = delegate { completion.TrySetException(new InvalidDataException("Windows 无法解码此视频。建议转换成 H.264 + AAC 的 MP4 后导入。")); };
            var timeout = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
            timeout.Tick += delegate { completion.TrySetException(new TimeoutException("视频读取超时，请检查文件是否已下载完整。")); };
            media.MediaOpened += opened; media.MediaFailed += failed;
            try { timeout.Start(); media.Volume = 0; media.Open(new Uri(Path.GetFullPath(source))); return await completion.Task; }
            finally { timeout.Stop(); media.MediaOpened -= opened; media.MediaFailed -= failed; media.Close(); }
        }
        private void SetBusy(bool value, string message) { busy = value; UpdateButtons(); if (message != null) Notify(message, false); }
        private void UpdateButtons()
        {
            import.IsEnabled = !busy; library.IsEnabled = !busy; volume.IsEnabled = !busy; Find<CheckBox>("AutoApply").IsEnabled = !busy;
            apply.IsEnabled = !busy && Selected != null && startupEnabled;
            play.IsEnabled = !busy && Selected != null;
            undo.IsEnabled = !busy && store.CanUndo();
        }
        private void Notify(string message, bool error)
        {
            var text = Find<TextBlock>("Message"); text.Text = message;
            text.Foreground = (Brush)new BrushConverter().ConvertFrom(error ? "#FFB9AA" : "#A8C5EF");
        }
        private void OpenBackup()
        {
            string folder = File.Exists(Path.Combine(store.Root, "install-manifest.json")) ? Path.Combine(store.Data, "installation") : Path.Combine(store.Root, "本机备份");
            if (!Directory.Exists(folder)) { Notify("尚未找到本机可用状态备份。", true); return; }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(folder) { UseShellExecute = true });
        }
    }
}
