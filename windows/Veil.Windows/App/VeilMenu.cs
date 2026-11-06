using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace Veil;

public sealed class MenuEntry
{
    public string Title = "", Hint = "";
    public bool Enabled = true, IsSeparator;
    public Action Run;

    public static MenuEntry Item(string title, Action run, string hint = "", bool enabled = true) =>
        new MenuEntry { Title = title, Run = run, Hint = hint, Enabled = enabled };

    public static MenuEntry Sep() => new MenuEntry { IsSeparator = true };
}

/// Veil's own drop-down menu: rounded, themed, accent highlight (same look as the Mac menus).
public static class VeilMenu
{
    [StructLayout(LayoutKind.Sequential)]
    struct PT { public int X, Y; }
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out PT p);

    static Popup current;
    static DispatcherTimer watcher;

    public static void Close()
    {
        if (watcher != null) { watcher.Stop(); watcher = null; }
        var pop = current;
        current = null;
        if (pop != null) pop.IsOpen = false;
    }

    static Brush Res(string key) => (Brush)Application.Current.FindResource(key);

    /// Opens the menu under a button.
    public static void Show(UIElement anchor, IEnumerable<MenuEntry> entries, bool rightAlign = false) =>
        Open(anchor, entries, rightAlign, false);

    /// Opens the menu at the mouse pointer (right-click menus).
    public static void ShowAtMouse(IEnumerable<MenuEntry> entries) =>
        Open(null, entries, false, true);

    static void Open(UIElement anchor, IEnumerable<MenuEntry> entries, bool rightAlign, bool atMouse)
    {
        Close();
        Brush field = Res("Field"), line = Res("Line"), text = Res("Text"), mute = Res("Mute");
        var ac = ((SolidColorBrush)Res("Accent")).Color;
        Brush hover = new SolidColorBrush(Color.FromArgb(0x38, ac.R, ac.G, ac.B));

        var list = new StackPanel();
        foreach (var entry in entries)
        {
            if (entry.IsSeparator)
            {
                list.Children.Add(new Border { Height = 1, Margin = new Thickness(8, 5, 8, 5), Background = line });
                continue;
            }
            var title = new TextBlock { Text = entry.Title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, Foreground = entry.Enabled ? text : mute };
            var hint = new TextBlock { Text = entry.Hint, FontSize = 12, Foreground = mute, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(28, 0, 0, 0) };
            DockPanel.SetDock(hint, Dock.Right);
            var dock = new DockPanel { LastChildFill = true };
            dock.Children.Add(hint);
            dock.Children.Add(title);
            var row = new Border
            {
                Height = 30, CornerRadius = new CornerRadius(7), Padding = new Thickness(12, 0, 12, 0),
                Background = Brushes.Transparent, Child = dock,
                Cursor = entry.Enabled ? System.Windows.Input.Cursors.Hand : System.Windows.Input.Cursors.Arrow,
            };
            if (entry.Enabled)
            {
                row.MouseEnter += (_, __) => row.Background = hover;
                row.MouseLeave += (_, __) => row.Background = Brushes.Transparent;
                var run = entry.Run;
                row.MouseLeftButtonUp += (_, __) =>
                {
                    Close();
                    if (run != null) Application.Current.Dispatcher.BeginInvoke(new Action(() => run()));
                };
            }
            list.Children.Add(row);
        }

        var card = new Border
        {
            Background = field, BorderBrush = line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(11),
            Padding = new Thickness(6), MinWidth = 210, Child = list, Margin = new Thickness(12),
            Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.35, Color = Colors.Black },
        };
        card.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        double visibleWidth = card.DesiredSize.Width - 24;

        var pop = new Popup { AllowsTransparency = true, StaysOpen = false, PopupAnimation = PopupAnimation.Fade, Child = card };
        if (atMouse)
        {
            pop.Placement = PlacementMode.MousePoint;
            pop.HorizontalOffset = -12;
            pop.VerticalOffset = -12;
        }
        else
        {
            pop.PlacementTarget = anchor;
            pop.Placement = PlacementMode.Bottom;
            double anchorWidth = anchor is FrameworkElement fe ? fe.ActualWidth : 0;
            pop.HorizontalOffset = (rightAlign ? anchorWidth - visibleWidth : 0) - 12;
            pop.VerticalOffset = -8;
        }
        pop.Closed += (_, __) =>
        {
            if (current == pop) { if (watcher != null) { watcher.Stop(); watcher = null; } current = null; }
        };
        current = pop;
        pop.IsOpen = true;

        // Clicks inside the web page do not reach WPF, so watch the mouse ourselves and close the menu on any outside click.
        bool armed = false;
        watcher = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        watcher.Tick += (_, __) =>
        {
            bool down = (GetAsyncKeyState(0x01) & 0x8000) != 0 || (GetAsyncKeyState(0x02) & 0x8000) != 0 || (GetAsyncKeyState(0x04) & 0x8000) != 0;
            if (!down) { armed = true; return; }
            if (!armed) return;
            if (!GetCursorPos(out var pt)) return;
            try
            {
                var local = card.PointFromScreen(new Point(pt.X, pt.Y));
                if (local.X < 0 || local.Y < 0 || local.X > card.ActualWidth || local.Y > card.ActualHeight) Close();
            }
            catch { Close(); }
        };
        watcher.Start();
    }
}
