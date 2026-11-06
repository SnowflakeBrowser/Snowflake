using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Web.WebView2.Core;

namespace Veil;

/// Hosts one WebView2 controller in a child window. (We own the controller so we can receive
/// AcceleratorKeyPressed for browser shortcuts, which the stock WPF control does not expose.)
public sealed class WebViewHost : HwndHost
{
    IntPtr hwnd;
    readonly TaskCompletionSource<IntPtr> created = new();
    public CoreWebView2Controller Controller;
    public Task<IntPtr> HandleReady => created.Task;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateWindowEx(int exStyle, string cls, string name, int style, int x, int y, int w, int h,
                                        IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr hwnd);

    protected override HandleRef BuildWindowCore(HandleRef hwndParent)
    {
        const int WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000, WS_CLIPCHILDREN = 0x02000000, WS_CLIPSIBLINGS = 0x04000000;
        hwnd = CreateWindowEx(0, "static", "", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 0, 0,
                              hwndParent.Handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        created.TrySetResult(hwnd);
        return new HandleRef(this, hwnd);
    }

    protected override void DestroyWindowCore(HandleRef hwnd_)
    {
        try { Controller?.Close(); } catch { }
        Controller = null;
        DestroyWindow(hwnd_.Handle);
    }

    protected override void OnWindowPositionChanged(Rect rc)
    {
        base.OnWindowPositionChanged(rc);
        if (Controller != null)
            Controller.Bounds = new System.Drawing.Rectangle(0, 0, Math.Max(1, (int)rc.Width), Math.Max(1, (int)rc.Height));
    }

    protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.Property == UIElement.IsVisibleProperty && Controller != null) Controller.IsVisible = (bool)e.NewValue;
    }
}
