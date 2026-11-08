using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Veil.Core;

namespace Veil;

static class Theme
{
    // dark accent, light accent (same colours as the start page and settings)
    static readonly Dictionary<string, (string dark, string light)> Accents = new()
    {
        ["mist"] = ("#8fb3c9", "#3d6c8a"), ["coral"] = ("#f0907d", "#c4503a"), ["mint"] = ("#6fd0a8", "#26896a"),
        ["violet"] = ("#ab94f5", "#6f52c9"), ["amber"] = ("#e8b058", "#a8700f"), ["pink"] = ("#f48fbe", "#be3c78"),
        ["sky"] = ("#64b5f6", "#1976d2"), ["lime"] = ("#aad65c", "#628c14"), ["crimson"] = ("#e8646e", "#b02838"),
    };

    // Browser themes (hue, saturation), same table as the Mac version.
    static readonly Dictionary<string, (double hue, double sat)> Hues = new()
    {
        ["midnight"] = (222, 0.60), ["forest"] = (140, 0.45), ["rose"] = (340, 0.50), ["sunset"] = (18, 0.62), ["grape"] = (272, 0.50),
        ["ocean"] = (190, 0.58), ["mocha"] = (28, 0.35), ["mint"] = (160, 0.48), ["graphite"] = (220, 0.0),
    };

    /// Colour of the tab bar / toolbar; the Windows title bar is painted the same colour.
    public static Color ChromeColor = Color.FromRgb(19, 20, 23);

    static Color Rgb(int r, int g, int b) => Color.FromRgb((byte)r, (byte)g, (byte)b);
    static Color Alpha(int a, int v) => Color.FromArgb((byte)a, (byte)v, (byte)v, (byte)v);
    static Brush Solid(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    static Color HexColor(string h) => (Color)ColorConverter.ConvertFromString(h);

    static Color Hsb(double h, double s, double v)
    {
        h = ((h % 360) + 360) % 360 / 60.0;
        int i = (int)Math.Floor(h);
        double f = h - i;
        double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
        double r, g, b;
        switch (i)
        {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            default: r = v; g = p; b = q; break;
        }
        return Rgb((int)Math.Round(r * 255), (int)Math.Round(g * 255), (int)Math.Round(b * 255));
    }

    public static bool IsDark()
    {
        var t = Services.Settings.Str("theme");
        if (t == "light") return false;
        if (t != "system") return true;
        try
        {
            using var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return !(k?.GetValue("AppsUseLightTheme") is int v && v == 1);
        }
        catch { return true; }
    }

    public static void Apply()
    {
        bool dark = IsDark();
        var r = Application.Current.Resources;

        Color chrome, field, tab, back;
        var themeName = Services.Settings.Str("browserTheme") ?? "";
        if (Hues.TryGetValue(themeName, out var hs))
        {
            if (dark) { chrome = Hsb(hs.hue, hs.sat, 0.16); field = Hsb(hs.hue, hs.sat * 0.9, 0.23); tab = Hsb(hs.hue, hs.sat * 0.8, 0.31); back = Hsb(hs.hue, hs.sat, 0.14); }
            else { chrome = Hsb(hs.hue, hs.sat * 0.28, 0.93); field = Hsb(hs.hue, hs.sat * 0.10, 0.99); tab = Colors.White; back = Hsb(hs.hue, hs.sat * 0.20, 0.96); }
        }
        else if (dark) { chrome = Rgb(19, 20, 23); field = Rgb(32, 34, 39); tab = Rgb(44, 47, 55); back = Rgb(19, 20, 23); }
        else { chrome = Rgb(232, 232, 228); field = Rgb(250, 250, 248); tab = Colors.White; back = Rgb(244, 244, 241); }
        ChromeColor = chrome;

        r["Bg"] = Solid(back);
        r["Bar"] = Solid(chrome);
        r["Field"] = Solid(field);
        r["TabActive"] = Solid(tab);
        r["Text"] = Solid(dark ? Rgb(236, 236, 240) : Rgb(27, 27, 31));
        r["Mute"] = Solid(dark ? Rgb(154, 154, 166) : Rgb(102, 102, 111));
        r["Line"] = Solid(dark ? Alpha(0x2B, 255) : Alpha(0x2B, 0));
        r["TabIdle"] = Solid(dark ? Alpha(0x09, 255) : Alpha(0x08, 0));
        r["TabHover"] = Solid(dark ? Alpha(0x14, 255) : Alpha(0x0F, 0));
        var accent = Accents.TryGetValue(Services.Settings.Str("accent") ?? "", out var a) ? a : Accents["mist"];
        r["Accent"] = Solid(HexColor(dark ? accent.dark : accent.light));
    }
}

public sealed class MainWindow : Window
{
    public static MainWindow Current;

    sealed class Parts { public Image Fav; public TextBlock Title; public Button Audio, Close; }

    static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    static readonly ControlTemplate FlatTemplate = (ControlTemplate)XamlReader.Parse(
        "<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='Button'>" +
        "<Border x:Name='b' Background='{TemplateBinding Background}' CornerRadius='6' Padding='{TemplateBinding Padding}'>" +
        "<ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border>" +
        "<ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#33888888'/></Trigger></ControlTemplate.Triggers></ControlTemplate>");

    readonly List<BrowserTab> tabs = new();
    readonly Stack<string> closed = new();
    BrowserTab active;
    readonly string startupUrl;

    readonly Grid content = new();
    readonly StackPanel tabStrip = new();
    readonly ScrollViewer tabScroll = new();
    readonly DockPanel tabArea = new();
    readonly Border topWrap = new(), sideWrap = new();
    readonly Button newTabBtn;
    readonly TextBox address = new();
    Button backB, fwdB, reloadB, starB, shieldB, dlB, menuB;
    readonly StackPanel bookmarksBar = new();
    readonly Border bookmarksWrap = new();
    readonly Grid chrome = new();
    readonly Grid rootGrid = new();
    bool fullscreen; WindowState prevState; WindowStyle prevStyle;

    public MainWindow(string startUrl)
    {
        Current = this;
        startupUrl = startUrl;
        Title = "Veil";
        MinWidth = 520; MinHeight = 360;
        Theme.Apply();
        SetResourceReference(BackgroundProperty, "Bg");

        newTabBtn = Btn("\uE710", "New tab (Ctrl+T)", () => NewTab());
        newTabBtn.Margin = new Thickness(2, 0, 0, 4);
        tabScroll.Content = tabStrip;
        tabScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
        tabScroll.SizeChanged += (_, __) => FitTabs();
        tabArea.Children.Add(tabScroll);

        // columns: [side tabs] [main]
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        sideWrap.Width = 210; sideWrap.Padding = new Thickness(4);
        sideWrap.SetResourceReference(Border.BackgroundProperty, "Bar");
        Grid.SetColumn(sideWrap, 0);
        rootGrid.Children.Add(sideWrap);

        for (int i = 0; i < 4; i++) chrome.RowDefinitions.Add(new RowDefinition { Height = i == 3 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
        Grid.SetColumn(chrome, 1);
        rootGrid.Children.Add(chrome);

        topWrap.Padding = new Thickness(8, 6, 8, 0);
        topWrap.SetResourceReference(Border.BackgroundProperty, "Bar");
        Grid.SetRow(topWrap, 0); chrome.Children.Add(topWrap);

        var toolbar = BuildToolbar();
        Grid.SetRow(toolbar, 1); chrome.Children.Add(toolbar);

        bookmarksWrap.Child = new ScrollViewer { Content = bookmarksBar, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
        bookmarksBar.Orientation = Orientation.Horizontal;
        bookmarksWrap.Padding = new Thickness(6, 0, 6, 4);
        bookmarksWrap.SetResourceReference(Border.BackgroundProperty, "Bar");
        Grid.SetRow(bookmarksWrap, 2); chrome.Children.Add(bookmarksWrap);

        Grid.SetRow(content, 3); chrome.Children.Add(content);
        Content = rootGrid;

        PreviewKeyDown += (s, e) =>
        {
            var k = e.Key == Key.System ? e.SystemKey : e.Key;
            var m = Keyboard.Modifiers;
            if (HandleShortcut(k, m.HasFlag(ModifierKeys.Control), m.HasFlag(ModifierKeys.Shift), m.HasFlag(ModifierKeys.Alt))) e.Handled = true;
        };
        Services.Changed += () => Dispatcher.BeginInvoke(new Action(OnServicesChanged));
        SourceInitialized += (s, e) => ApplyTitleBar();
        Loaded += async (s, e) => await StartAsync();
        Closing += OnClosing;
    }

    // ---------- startup ----------
    async Task StartAsync()
    {
        try { await Services.InitEnvAsync(); }
        catch (Exception ex)
        {
            if (MessageBox.Show("Veil could not start its browser engine.\n\n" + ex.Message +
                                "\n\nIf this says the Microsoft WebView2 Runtime is missing, install it. Open the download page?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Error) == MessageBoxResult.Yes)
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://developer.microsoft.com/microsoft-edge/webview2/") { UseShellExecute = true });
            Close();
            return;
        }
        _ = Services.Blocker.RebuildAsync();
        var w = Services.Window.Value;
        if (Services.Settings.Bool("rememberWindow") && !double.IsNaN(w.Left))
        {
            Left = w.Left; Top = w.Top; Width = w.Width; Height = w.Height;
            if (w.Maximized) WindowState = WindowState.Maximized;
        }
        var sess = Services.Session.Value;
        if (Services.Settings.Bool("restoreSession") && sess.Tabs.Count > 0)
        {
            foreach (var st in sess.Tabs) { var t = NewTab(st.Url, false, false); t.Title = st.Title ?? ""; }
            Activate(tabs[Math.Max(0, Math.Min(sess.Active, tabs.Count - 1))]);
        }
        else NewTab(UrlResolver.NewTab);
        if (!string.IsNullOrWhiteSpace(startupUrl)) OpenExternal(startupUrl);
        OnServicesChanged();
        if (Services.Settings.Str("cookieMode") == "all") _ = PurgeCookiesAsync();
        Services.Blocker.MaybeAutoUpdate();
        OfferLists();
    }

    void OfferLists()
    {
        if (Services.Settings.Bool("didOfferLists")) return;
        Services.Settings.Set("didOfferLists", System.Text.Json.Nodes.JsonValue.Create(true));
        var r = MessageBox.Show("Veil can block ads and trackers using the public EasyList / uBlock Origin filter lists.\n\n" +
            "Downloading them contacts easylist.to and ublockorigin.github.io (no cookies, no identifiers). A small built-in list works offline.\n\n" +
            "Download the lists now?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (r == MessageBoxResult.Yes) _ = Services.Blocker.DownloadListsAsync();
    }

    async Task PurgeCookiesAsync()
    {
        try
        {
            var deadline = DateTime.UtcNow.AddSeconds(15);
            CoreWebView2 core;
            while ((core = PersistentCore()) == null && DateTime.UtcNow < deadline) await Task.Delay(300);
            if (core == null) return;
            var keep = Services.Settings.List("cookieExceptions").Select(x => x.Trim().ToLowerInvariant()).Where(x => x.Length > 0).ToList();
            foreach (var c in await core.CookieManager.GetCookiesAsync(null))
            {
                var d = c.Domain.TrimStart('.').ToLowerInvariant();
                if (!keep.Any(k => d == k || d.EndsWith("." + k))) core.CookieManager.DeleteCookie(c);
            }
        }
        catch { }
    }

    public void OpenExternal(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) { Activate_Window(); return; }
        var resolved = UrlResolver.Resolve(url, SearchEngines.Template(Services.Settings.Str("searchEngine")));
        NewTab(resolved);
        Activate_Window();
    }
    void Activate_Window()
    {
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        base.Activate();
    }

    public CoreWebView2 PersistentCore() =>
        (active != null && !active.IsPrivate && active.Core != null ? active : tabs.FirstOrDefault(t => !t.IsPrivate && t.Core != null))?.Core;

    // ---------- toolbar ----------
    Button Btn(string glyph, string tip, Action click, double size = 14)
    {
        var b = new Button
        {
            Content = glyph, FontFamily = IconFont, FontSize = size, Width = 32, Height = 30, Template = FlatTemplate,
            Background = Brushes.Transparent, BorderThickness = new Thickness(0), ToolTip = tip, Focusable = false,
            Margin = new Thickness(1, 0, 1, 0), Padding = new Thickness(0),
        };
        b.SetResourceReference(Control.ForegroundProperty, "Text");
        b.Click += (_, __) => click();
        return b;
    }

    UIElement BuildToolbar()
    {
        backB = Btn("\uE72B", "Back (Alt+Left)", () => active?.GoBack());
        fwdB = Btn("\uE72A", "Forward (Alt+Right)", () => active?.GoForward());
        reloadB = Btn("\uE72C", "Reload (Ctrl+R)", () => { if (active != null) { if (active.Loading) active.Stop(); else active.Reload(); } });
        starB = Btn("\uE734", "Bookmark this page (Ctrl+D)", ToggleBookmark);
        shieldB = Btn("🛡", "Blocking for this site", ToggleShield, 13); shieldB.FontFamily = new FontFamily("Segoe UI Emoji");
        dlB = Btn("\uE896", "Downloads (Ctrl+J)", () => OpenInternal("veil://downloads"));
        menuB = Btn("\uE712", "Menu", () => ShowMainMenu());

        address.BorderThickness = new Thickness(0);
        address.Background = Brushes.Transparent;
        address.VerticalContentAlignment = VerticalAlignment.Center;
        address.FontSize = 14;
        address.Padding = new Thickness(6, 0, 6, 0);
        address.SetResourceReference(Control.ForegroundProperty, "Text");
        address.SetResourceReference(TextBox.CaretBrushProperty, "Text");
        address.GotKeyboardFocus += (s, e) => address.Dispatcher.BeginInvoke(new Action(address.SelectAll));
        address.KeyDown += (s, e) =>
        {
            if (e.Key == Key.Enter)
            {
                var url = UrlResolver.Resolve(address.Text, SearchEngines.Template(Services.Settings.Str("searchEngine")));
                active?.Navigate(url);
                active?.FocusPage();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape) { UpdateChrome(true); active?.FocusPage(); e.Handled = true; }
        };
        var field = new Border { CornerRadius = new CornerRadius(10), Height = 34, Margin = new Thickness(6, 0, 6, 0), Child = address, BorderThickness = new Thickness(1) };
        field.SetResourceReference(Border.BackgroundProperty, "Field");
        field.SetResourceReference(Border.BorderBrushProperty, "Line");

        var dock = new DockPanel { Margin = new Thickness(6, 4, 6, 6) };
        foreach (var b in new[] { backB, fwdB, reloadB }) { DockPanel.SetDock(b, Dock.Left); dock.Children.Add(b); }
        foreach (var b in new[] { menuB, dlB, shieldB, starB }) { DockPanel.SetDock(b, Dock.Right); dock.Children.Add(b); }
        dock.Children.Add(field);
        var wrap = new Border { Child = dock };
        wrap.SetResourceReference(Border.BackgroundProperty, "Bar");
        return wrap;
    }

    void ShowMainMenu()
    {
        VeilMenu.Show(menuB, new[]
        {
            MenuEntry.Item("New tab", () => NewTab(), "Ctrl+T"),
            MenuEntry.Item("New private tab", () => NewTab(null, true), "Ctrl+Shift+N"),
            MenuEntry.Sep(),
            MenuEntry.Item("History", () => OpenInternal("veil://history"), "Ctrl+H"),
            MenuEntry.Item("Bookmarks", () => OpenInternal("veil://bookmarks")),
            MenuEntry.Item("Downloads", () => OpenInternal("veil://downloads"), "Ctrl+J"),
            MenuEntry.Sep(),
            MenuEntry.Item("Privacy", () => OpenInternal("veil://privacy")),
            MenuEntry.Item("Settings", () => OpenInternal("veil://settings"), "Ctrl+,"),
            MenuEntry.Sep(),
            MenuEntry.Item("Vertical tabs", () => ToggleVertical(), "Ctrl+Shift+\\"),
            MenuEntry.Item("Full screen", () => SetFullscreen(!fullscreen), "F11"),
            MenuEntry.Sep(),
            MenuEntry.Item("Exit", () => Close()),
        }, rightAlign: true);
    }

    void ShowTabMenu(BrowserTab t)
    {
        int idx = tabs.IndexOf(t);
        VeilMenu.ShowAtMouse(new[]
        {
            MenuEntry.Item("Reload tab", () => t.Reload()),
            MenuEntry.Item("Duplicate tab", () => NewTab(t.Url, t.IsPrivate), "", t.Url.Length > 0),
            MenuEntry.Item(t.Muted ? "Unmute tab" : "Mute tab", () => t.ToggleMute()),
            MenuEntry.Item("Copy address", () => { try { Clipboard.SetText(t.DisplayUrl); } catch { } }, "", t.Url.Length > 0),
            MenuEntry.Sep(),
            MenuEntry.Item("Close tab", () => CloseTab(t), "Ctrl+W"),
            MenuEntry.Item("Close other tabs", () => CloseOthers(t), "", tabs.Count > 1),
            MenuEntry.Item("Close tabs to the right", () => CloseRight(t), "", idx >= 0 && idx < tabs.Count - 1),
        });
    }

    void CloseOthers(BrowserTab keep)
    {
        foreach (var x in tabs.ToList()) if (x != keep) CloseTab(x);
        Activate(keep);
    }

    void CloseRight(BrowserTab from)
    {
        int i = tabs.IndexOf(from);
        if (i < 0) return;
        foreach (var x in tabs.Skip(i + 1).ToList()) CloseTab(x);
    }

    void ApplyTitleBar() => TitleBar.Apply(this, Theme.ChromeColor, Theme.IsDark());

    /// Tabs share the strip like on the Mac: they shrink to fit instead of scrolling out of sight.
    void FitTabs()
    {
        bool vert = Services.Settings.Bool("verticalTabs");
        double max = Services.Settings.Str("tabWidth") switch { "compact" => 150, "wide" => 280, _ => 210 };
        double avail = tabScroll.ActualWidth > 80 ? tabScroll.ActualWidth - 44 : max * Math.Max(1, tabs.Count);
        double per = Math.Max(96, Math.Min(max, avail / Math.Max(1, tabs.Count) - 4));
        foreach (var t in tabs)
        {
            if (t.Header == null) continue;
            t.Header.Width = vert ? double.NaN : per;
            t.Header.HorizontalAlignment = HorizontalAlignment.Stretch;
        }
    }

    void ToggleVertical() { Services.Settings.Set("verticalTabs", System.Text.Json.Nodes.JsonValue.Create(!Services.Settings.Bool("verticalTabs"))); Services.Notify(); }

    void ToggleBookmark()
    {
        if (active == null || !active.DisplayUrl.StartsWith("http")) return;
        if (Services.Bookmarks.Contains(active.Url)) Services.Bookmarks.Remove(active.Url);
        else Services.Bookmarks.Add(active.Url, active.Title);
        Services.Notify();
    }

    void ToggleShield()
    {
        var host = active == null ? "" : UrlResolver.HostOf(active.Url);
        if (host.Length == 0 || !active.Url.StartsWith("http")) return;
        if (Services.Allowlist.Contains(host)) Services.Allowlist.Remove(host); else Services.Allowlist.Add(host);
        Services.Notify();
        active.Reload();
    }

    // ---------- tabs ----------
    public void OpenInternal(string url)
    {
        var existing = tabs.FirstOrDefault(t => t.Url == url && !t.IsPrivate);
        if (existing != null) { Activate(existing); return; }
        if (active != null && active.Url == UrlResolver.NewTab) active.Navigate(url); else NewTab(url);
    }

    public BrowserTab NewTab(string url = null, bool isPrivate = false, bool activate = true)
    {
        var t = new BrowserTab(this, isPrivate) { Url = url ?? UrlResolver.NewTab };
        t.PendingUrl = t.Url;
        t.Header = MakeHeader(t);
        t.Changed += () => Refresh(t);
        int idx = Services.Settings.Bool("newTabNextToCurrent") && active != null ? tabs.IndexOf(active) + 1 : tabs.Count;
        tabs.Insert(idx, t);
        tabStrip.Children.Insert(idx, t.Header);
        FitTabs();
        Refresh(t);
        if (activate) Activate(t);
        return t;
    }

    public async Task<BrowserTab> CreatePopupTabAsync(bool priv)
    {
        var t = NewTab("", priv, false);
        t.IsPopup = true; t.PendingUrl = null;
        Activate(t);
        await t.EnsureCreatedAsync(content);
        return t;
    }

    public void Activate(BrowserTab t)
    {
        active = t;
        foreach (var x in tabs) { if (x.Host != null) x.Host.Visibility = x == t ? Visibility.Visible : Visibility.Collapsed; Refresh(x); }
        _ = ShowAsync(t);
        UpdateChrome(true);
        SaveSession();
    }

    async Task ShowAsync(BrowserTab t)
    {
        try { await t.EnsureCreatedAsync(content); }
        catch (Exception ex) { MessageBox.Show("Could not create a browser view:\n" + ex.Message, "Veil"); return; }
        if (t.Host == null) return;
        t.Host.Visibility = active == t ? Visibility.Visible : Visibility.Collapsed;
        if (active != t) return;
        if (t.Url == UrlResolver.NewTab || t.Url == "") { address.Focus(); address.SelectAll(); } else t.FocusPage();
    }

    public void CloseTab(BrowserTab t)
    {
        int i = tabs.IndexOf(t);
        if (i < 0) return;
        if (!t.IsPrivate && t.Url.StartsWith("http")) closed.Push(t.Url);
        tabs.RemoveAt(i);
        tabStrip.Children.Remove(t.Header);
        FitTabs();
        t.Dispose(content);
        if (tabs.Count == 0) { Close(); return; }
        if (active == t) Activate(tabs[Math.Min(i, tabs.Count - 1)]);
        else SaveSession();
    }

    Border MakeHeader(BrowserTab t)
    {
        var p = new Parts
        {
            Fav = new Image { Width = 16, Height = 16, Margin = new Thickness(0, 0, 8, 0) },
            Title = new TextBlock { TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 },
            Audio = Btn("\uE767", "Mute / unmute tab", t.ToggleMute, 11),
            Close = Btn("\uE711", "Close tab (Ctrl+W)", () => CloseTab(t), 9),
        };
        foreach (var b in new[] { p.Audio, p.Close }) { b.Width = 22; b.Height = 22; }
        p.Audio.Visibility = Visibility.Collapsed;
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(p.Title, 1); Grid.SetColumn(p.Audio, 2); Grid.SetColumn(p.Close, 3);
        g.Children.Add(p.Fav); g.Children.Add(p.Title); g.Children.Add(p.Audio); g.Children.Add(p.Close);
        var b2 = new Border
        {
            Child = g, CornerRadius = new CornerRadius(9), Padding = new Thickness(10, 0, 4, 0), Margin = new Thickness(2, 0, 2, 4),
            Height = 32, BorderThickness = new Thickness(1), Cursor = Cursors.Hand, Tag = p,
        };
        b2.MouseLeftButtonDown += (s, e) => Activate(t);
        b2.MouseDown += (s, e) => { if (e.ChangedButton == MouseButton.Middle) CloseTab(t); };
        b2.MouseRightButtonUp += (s, e) => { ShowTabMenu(t); e.Handled = true; };
        b2.MouseEnter += (s, e) => { if (t != active) b2.SetResourceReference(Border.BackgroundProperty, "TabHover"); };
        b2.MouseLeave += (s, e) => StyleHeader(t);
        return b2;
    }

    /// Mac-style tab: soft pill with a thin border; the selected tab gets the accent colour border.
    void StyleHeader(BrowserTab t)
    {
        if (t.Header == null) return;
        var p = (Parts)t.Header.Tag;
        bool on = t == active;
        t.Header.SetResourceReference(Border.BackgroundProperty, on ? "TabActive" : "TabIdle");
        t.Header.SetResourceReference(Border.BorderBrushProperty, on ? "Accent" : "Line");
        p.Title.SetResourceReference(TextBlock.ForegroundProperty, on ? "Text" : "Mute");
    }

    void Refresh(BrowserTab t)
    {
        if (t.Header == null) return;
        var p = (Parts)t.Header.Tag;
        p.Title.Text = (t.IsPrivate ? "🕶 " : "") + t.DisplayTitle;
        p.Fav.Source = t.Favicon;
        p.Audio.Content = t.Muted ? "\uE74F" : "\uE767";
        p.Audio.Visibility = t.Audible || t.Muted ? Visibility.Visible : Visibility.Collapsed;
        StyleHeader(t);
        if (t == active) UpdateChrome(false);
        SaveSession();
    }

    void UpdateChrome(bool force)
    {
        if (active == null) return;
        var url = active.DisplayUrl;
        if (force || !address.IsKeyboardFocusWithin) address.Text = UrlResolver.Display(url);
        backB.IsEnabled = active.CanGoBack;
        fwdB.IsEnabled = active.CanGoForward;
        reloadB.Content = active.Loading ? "\uE711" : "\uE72C";
        bool web = active.Url.StartsWith("http");
        starB.Content = web && Services.Bookmarks.Contains(active.Url) ? "\uE735" : "\uE734";
        starB.SetResourceReference(Control.ForegroundProperty, web && Services.Bookmarks.Contains(active.Url) ? "Accent" : "Text");
        var host = UrlResolver.HostOf(active.Url);
        shieldB.Opacity = web && Services.Allowlist.Contains(host) ? 0.35 : 1.0;
        Title = active.DisplayTitle + (active.IsPrivate ? " (Private)" : "") + " – Veil";
    }

    // ---------- settings-driven chrome ----------
    void OnServicesChanged()
    {
        Theme.Apply();
        ApplyTitleBar();
        var S = Services.Settings;
        Topmost = S.Bool("alwaysOnTop");
        starB.Visibility = S.Bool("hideBookmarkButton") ? Visibility.Collapsed : Visibility.Visible;
        shieldB.Visibility = S.Bool("hideShieldButton") ? Visibility.Collapsed : Visibility.Visible;
        dlB.Visibility = S.Bool("hideDownloadsButton") ? Visibility.Collapsed : Visibility.Visible;
        try { Native.SetWindowDisplayAffinity(new WindowInteropHelper(this).Handle, S.Bool("hideFromCapture") ? 0x11u : 0u); } catch { }

        bool vert = S.Bool("verticalTabs");
        topWrap.Child = null; sideWrap.Child = null;
        tabStrip.Orientation = vert ? Orientation.Vertical : Orientation.Horizontal;
        tabScroll.HorizontalScrollBarVisibility = vert ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Hidden;
        tabScroll.VerticalScrollBarVisibility = vert ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled;
        // The "+" button sits right after the newest tab (or on top of the list when the tabs are vertical).
        (newTabBtn.Parent as Panel)?.Children.Remove(newTabBtn);
        if (vert) { DockPanel.SetDock(newTabBtn, Dock.Top); newTabBtn.HorizontalAlignment = HorizontalAlignment.Left; tabArea.Children.Insert(0, newTabBtn); }
        else tabStrip.Children.Add(newTabBtn);
        (vert ? sideWrap : topWrap).Child = tabArea;
        sideWrap.Visibility = vert ? Visibility.Visible : Visibility.Collapsed;
        topWrap.Visibility = vert ? Visibility.Collapsed : Visibility.Visible;
        FitTabs();

        RebuildBookmarks();
        foreach (var t in tabs) { _ = t.ApplyScriptsAsync(); Refresh(t); }
        UpdateChrome(false);
    }

    readonly Dictionary<string, ImageSource> favCache = new();
    readonly HashSet<string> favTried = new();

    ImageSource FaviconFor(string host)
    {
        if (string.IsNullOrEmpty(host)) return null;
        if (favCache.TryGetValue(host, out var cached)) return cached;
        ImageSource src = null;
        var bytes = Services.LoadFavicon(host);
        if (bytes != null && bytes.Length > 0)
        {
            try
            {
                var bi = new System.Windows.Media.Imaging.BitmapImage();
                bi.BeginInit();
                bi.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
                bi.StreamSource = new MemoryStream(bytes);
                bi.EndInit();
                bi.Freeze();
                src = bi;
            }
            catch { }
        }
        if (src != null) favCache[host] = src;
        return src;
    }

    /// Bookmarks of sites that were never opened get their icon from the site's own /favicon.ico (once per site).
    async Task FetchFaviconAsync(string host)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(6) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0");
            var bytes = await http.GetByteArrayAsync("https://" + host + "/favicon.ico");
            if (bytes.Length < 100 || bytes.Length > 300000) return;
            var bi = new System.Windows.Media.Imaging.BitmapImage();
            bi.BeginInit();
            bi.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            bi.StreamSource = new MemoryStream(bytes);
            bi.EndInit();                       // throws if the file is not a real image
            Services.SaveFavicon(host, bytes);  // the bar redraws with the icon
        }
        catch { }
    }

    FrameworkElement LetterIcon(string host, string title)
    {
        var t = !string.IsNullOrEmpty(host) ? host : (title ?? "");
        if (t.StartsWith("www.")) t = t.Substring(4);
        var letter = t.Length > 0 ? t.Substring(0, 1).ToUpperInvariant() : "+";
        var tb = new TextBlock { Text = letter, FontSize = 9, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        tb.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
        var bd = new Border { Width = 16, Height = 16, CornerRadius = new CornerRadius(4), Margin = new Thickness(0, 0, 6, 0), Child = tb, BorderThickness = new Thickness(1) };
        bd.SetResourceReference(Border.BorderBrushProperty, "Line");
        return bd;
    }

    void RebuildBookmarks()
    {
        bookmarksBar.Children.Clear();
        bool show = Services.Settings.Bool("showBookmarksBar") && Services.Bookmarks.All.Count > 0;
        bookmarksWrap.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (!show) return;
        foreach (var bm in Services.Bookmarks.All)
        {
            var title = bm.Title.Length > 22 ? bm.Title.Substring(0, 21) + "…" : bm.Title;
            var host = UrlResolver.HostOf(bm.Url);
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            var ico = FaviconFor(host);
            if (ico != null) row.Children.Add(new Image { Source = ico, Width = 16, Height = 16, Margin = new Thickness(0, 0, 6, 0) });
            else
            {
                row.Children.Add(LetterIcon(host, bm.Title));
                if (!string.IsNullOrEmpty(host) && favTried.Add(host) && bm.Url.StartsWith("http", StringComparison.OrdinalIgnoreCase)) _ = FetchFaviconAsync(host);
            }
            row.Children.Add(new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center });
            var b = new Button { Content = row, Template = FlatTemplate, Background = Brushes.Transparent, Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(1, 0, 1, 0), Focusable = false, ToolTip = bm.Url, FontSize = 12 };
            b.SetResourceReference(Control.ForegroundProperty, "Text");
            var url = bm.Url;
            b.Click += (_, __) => active?.Navigate(url);
            b.MouseDown += (s, e) => { if (e.ChangedButton == MouseButton.Middle) NewTab(url); };
            b.MouseRightButtonUp += (s, e) =>
            {
                VeilMenu.ShowAtMouse(new[] { MenuEntry.Item("Remove bookmark", () => { Services.Bookmarks.Remove(url); Services.Notify(); }) });
                e.Handled = true;
            };
            bookmarksBar.Children.Add(b);
        }
    }

    // ---------- shortcuts ----------
    public bool HandleShortcut(Key key, bool ctrl, bool shift, bool alt)
    {
        if (ctrl && alt && key == Key.H) { Panic(); return true; }
        if (ctrl && !alt)
        {
            if (key >= Key.D1 && key <= Key.D8) { int i = key - Key.D1; if (i < tabs.Count) Activate(tabs[i]); return true; }
            switch (key)
            {
                case Key.T: if (shift) ReopenClosed(); else NewTab(); return true;
                case Key.W: if (active != null) CloseTab(active); return true;
                case Key.N when shift: NewTab(null, true); return true;
                case Key.L: address.Focus(); address.SelectAll(); return true;
                case Key.D: ToggleBookmark(); return true;
                case Key.R: active?.Reload(); return true;
                case Key.Tab: Cycle(shift ? -1 : 1); return true;
                case Key.PageDown: Cycle(1); return true;
                case Key.PageUp: Cycle(-1); return true;
                case Key.H: OpenInternal("veil://history"); return true;
                case Key.J: OpenInternal("veil://downloads"); return true;
                case Key.OemComma: OpenInternal("veil://settings"); return true;
                case Key.OemPipe when shift: ToggleVertical(); return true;
                case Key.D9: if (tabs.Count > 0) Activate(tabs[^1]); return true;
            }
            return false;
        }
        if (alt && !ctrl)
        {
            switch (key)
            {
                case Key.Left: active?.GoBack(); return true;
                case Key.Right: active?.GoForward(); return true;
                case Key.D: address.Focus(); address.SelectAll(); return true;
            }
            return false;
        }
        switch (key)
        {
            case Key.F5: active?.Reload(); return true;
            case Key.F6: address.Focus(); address.SelectAll(); return true;
            case Key.F11: SetFullscreen(!fullscreen); return true;
        }
        return false;
    }

    void Cycle(int d)
    {
        if (tabs.Count == 0 || active == null) return;
        Activate(tabs[(tabs.IndexOf(active) + d + tabs.Count) % tabs.Count]);
    }

    void ReopenClosed() { if (closed.Count > 0) NewTab(closed.Pop()); }

    void Panic()
    {
        foreach (var t in tabs) t.SetMuted(true);
        WindowState = WindowState.Minimized;
    }

    public void SetFullscreen(bool on)
    {
        if (on == fullscreen) return;
        fullscreen = on;
        if (on)
        {
            prevState = WindowState; prevStyle = WindowStyle;
            WindowStyle = WindowStyle.None; WindowState = WindowState.Normal; WindowState = WindowState.Maximized;
            topWrap.Visibility = sideWrap.Visibility = Visibility.Collapsed;
            chrome.RowDefinitions[1].Height = new GridLength(0);
            bookmarksWrap.Visibility = Visibility.Collapsed;
        }
        else
        {
            WindowStyle = prevStyle; WindowState = prevState;
            chrome.RowDefinitions[1].Height = GridLength.Auto;
            OnServicesChanged();
        }
    }

    // ---------- persistence ----------
    void SaveSession()
    {
        if (tabs.Count == 0) return;
        var s = new SessionState();
        foreach (var t in tabs.Where(t => !t.IsPrivate && t.Url.Length > 0))
        {
            if (t == active) s.Active = s.Tabs.Count;
            s.Tabs.Add(new SavedTab { Url = t.Url, Title = t.Title });
        }
        Services.Session.Value = s;
    }

    void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        if (Services.Settings.Bool("confirmCloseWindow") || (Services.Settings.Bool("confirmQuit")))
            if (MessageBox.Show("Close Veil?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) { e.Cancel = true; return; }
        if (Services.Downloads.HasActive &&
            MessageBox.Show("A download is still running. Quit anyway?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) { e.Cancel = true; return; }
        SaveSession();
        var rb = RestoreBounds;
        Services.Window.Value = new WindowBounds { Left = rb.Left, Top = rb.Top, Width = rb.Width, Height = rb.Height, Maximized = WindowState == WindowState.Maximized };
        if (Services.Settings.Bool("clearHistoryOnQuit")) Services.History.Clear();
        Services.FlushAll();
    }
}
