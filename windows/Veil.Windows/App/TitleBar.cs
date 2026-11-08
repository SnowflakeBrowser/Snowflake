using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace Veil;

/// Makes the Windows title bar blend into Veil's tab bar: same colour, no visible title text.
/// Windows 11 gets the full effect; Windows 10 only switches the bar to dark or light.
static class TitleBar
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint crKey, byte bAlpha, uint dwFlags);

    /// "See-through window" setting: 100 = solid, lower = more see-through.
    public static void SetOpacity(Window w, int percent)
    {
        try
        {
            var h = new WindowInteropHelper(w).Handle;
            if (h == IntPtr.Zero) return;
            const int GWL_EXSTYLE = -20, WS_EX_LAYERED = 0x80000;
            int ex = GetWindowLong(h, GWL_EXSTYLE);
            if (percent >= 100 || percent <= 0)
            {
                if ((ex & WS_EX_LAYERED) != 0) SetWindowLong(h, GWL_EXSTYLE, ex & ~WS_EX_LAYERED);
                return;
            }
            if ((ex & WS_EX_LAYERED) == 0) SetWindowLong(h, GWL_EXSTYLE, ex | WS_EX_LAYERED);
            SetLayeredWindowAttributes(h, 0, (byte)Math.Max(80, Math.Min(255, percent * 255 / 100)), 2);
        }
        catch { }
    }

    static int Bgr(Color c) => c.R | (c.G << 8) | (c.B << 16);

    public static void Apply(Window w, Color chrome, bool dark)
    {
        try
        {
            var h = new WindowInteropHelper(w).Handle;
            if (h == IntPtr.Zero) return;
            int d = dark ? 1 : 0;
            DwmSetWindowAttribute(h, 20, ref d, 4);      // dark title bar (Windows 10 20H1+ and 11)
            DwmSetWindowAttribute(h, 19, ref d, 4);      // same switch on older Windows 10 builds
            int c = Bgr(chrome);
            DwmSetWindowAttribute(h, 35, ref c, 4);      // title bar colour (Windows 11)
            DwmSetWindowAttribute(h, 34, ref c, 4);      // window border colour (Windows 11)
            DwmSetWindowAttribute(h, 36, ref c, 4);      // title text colour = bar colour, so the text is invisible
        }
        catch { }
    }
}
