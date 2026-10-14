using System;
using System.Runtime.InteropServices;

namespace BootStudio.Player
{
    // Read-only probe. Never switch desktops or change Winlogon security.
    public sealed class SurfaceState
    {
        public bool InputDesktopActive;
        public bool NativeVisible;
        public bool Cloaked;
        public bool HasBounds;
        public int DesktopError;
        public IntPtr Foreground;
        public int Left, Top, Width, Height;
        public bool SurfaceVisible { get { return NativeVisible && !Cloaked && HasBounds; } }
        public override string ToString()
        {
            return "inputActive=" + InputDesktopActive + "; visible=" + NativeVisible +
                "; cloaked=" + Cloaked + "; bounds=" + Left + "," + Top + "," + Width + "," + Height +
                "; foreground=" + Foreground.ToInt64().ToString("X") + "; desktopError=" + DesktopError;
        }
    }

    public static class DesktopProbe
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("user32.dll", EntryPoint="GetUserObjectInformationW", SetLastError=true)]
        private static extern bool GetUserObjectInformation(IntPtr handle, int index, out int value, uint length, out uint needed);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out int value, int size);

        public static SurfaceState Read(IntPtr window)
        {
            var state = new SurfaceState();
            state.Foreground = GetForegroundWindow();
            if (window == IntPtr.Zero) return state;
            uint process;
            uint thread = GetWindowThreadProcessId(window, out process);
            IntPtr desktop = thread == 0 ? IntPtr.Zero : GetThreadDesktop(thread);
            int receivingInput;
            uint needed;
            // UOI_IO reports whether this window's desktop is actually displayed.
            // A WPF IsVisible value alone cannot distinguish Default from Winlogon.
            if (desktop != IntPtr.Zero && GetUserObjectInformation(desktop, 6, out receivingInput, 4, out needed))
                state.InputDesktopActive = receivingInput != 0;
            else state.DesktopError = Marshal.GetLastWin32Error();
            state.NativeVisible = IsWindowVisible(window);
            int cloaked;
            state.Cloaked = DwmGetWindowAttribute(window, 14, out cloaked, 4) == 0 && cloaked != 0;
            Rect bounds;
            if (GetWindowRect(window, out bounds))
            {
                state.Left = bounds.Left; state.Top = bounds.Top;
                state.Width = bounds.Right - bounds.Left; state.Height = bounds.Bottom - bounds.Top;
                state.HasBounds = state.Width > 0 && state.Height > 0;
            }
            // The handle from GetThreadDesktop is borrowed; do not close it.
            return state;
        }
    }
}
