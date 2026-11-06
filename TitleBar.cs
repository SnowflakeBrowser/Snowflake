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
