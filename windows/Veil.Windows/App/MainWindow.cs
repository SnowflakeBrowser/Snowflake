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
    static readonly Dictionary<string, string> Accents = new()
    {
        ["mist"] = "#8fb3c9", ["coral"] = "#f0907d", ["mint"] = "#6fd0a8", ["violet"] = "#ab94f5", ["amber"] = "#e8b058",
        ["pink"] = "#f48fbe", ["sky"] = "#64b5f6", ["lime"] = "#aad65c", ["crimson"] = "#e8646e",
    };
    static Brush Hex(string h) { var b = (SolidColorBrush)new BrushConverter().ConvertFromString(h); b.Freeze(); return b; }

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
        r["Bg"] = Hex(dark ? "#17171a" : "#f4f4f6");
        r["Bar"] = Hex(dark ? "#202024" : "#e9e9ed");
        r["Field"] = Hex(dark ? "#2b2b31" : "#ffffff");
        r["Text"] = Hex(dark ? "#ececf0" : "#1b1b1f");
        r["Mute"] = Hex(dark ? "#9a9aa6" : "#66666f");
        r["TabActive"] = Hex(dark ? "#34343c" : "#ffffff");
        r["Line"] = Hex(dark ? "#2e2e35" : "#d4d4da");
        r["Accent"] = Hex(Accents.TryGetValue(Services.Settings.Str("accent"), out var a) ? a : Accents["mist"]);
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
        tabScroll.Content = tabStrip;
        tabScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
        tabArea.Children.Add(newTabBtn);
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

        topWrap.Padding = new Thickness(6, 4, 6, 0);
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
        Loaded += async (s, e) => await StartAsync();
        Closing += OnClosing;
    }

    // ---------- startup ----------
    async Task StartAsync()
    {
        try { await Services.InitEnvAsync(); }
        catch (Exception ex)
        {
            if (MessageBox.Show("Veil needs the Microsoft WebView2 Runtime, which could not be started.\n\n" + ex.Message +
                                "\n\nOpen the download page?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Error) == MessageBoxResult.Yes)
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
        menuB = Btn("\uE712", "Menu", () => { var m = BuildMenu(); m.PlacementTarget = menuB; m.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom; m.IsOpen = true; });

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
        var field = new Border { CornerRadius = new CornerRadius(8), Height = 32, Margin = new Thickness(6, 0, 6, 0), Child = address };
        field.SetResourceReference(Border.BackgroundProperty, "Field");

        var dock = new DockPanel { Margin = new Thickness(6, 4, 6, 6) };
        foreach (var b in new[] { backB, fwdB, reloadB }) { DockPanel.SetDock(b, Dock.Left); dock.Children.Add(b); }
        foreach (var b in new[] { menuB, dlB, shieldB, starB }) { DockPanel.SetDock(b, Dock.Right); dock.Children.Add(b); }
        dock.Children.Add(field);
        var wrap = new Border { Child = dock };
        wrap.SetResourceReference(Border.BackgroundProperty, "Bar");
        return wrap;
    }

    ContextMenu BuildMenu()
    {
        var m = new ContextMenu();
        MenuItem Item(string text, Action a, string gesture = null) { var i = new MenuItem { Header = text, InputGestureText = gesture }; i.Click += (_, __) => a(); return i; }
        m.Items.Add(Item("New tab", () => NewTab(), "Ctrl+T"));
        m.Items.Add(Item("New private tab", () => NewTab(null, true), "Ctrl+Shift+N"));
        m.Items.Add(new Separator());
        m.Items.Add(Item("History", () => OpenInternal("veil://history"), "Ctrl+H"));
        m.Items.Add(Item("Bookmarks", () => OpenInternal("veil://bookmarks")));
        m.Items.Add(Item("Downloads", () => OpenInternal("veil://downloads"), "Ctrl+J"));
        m.Items.Add(Item("Privacy", () => OpenInternal("veil://privacy")));
        m.Items.Add(Item("Settings", () => OpenInternal("veil://settings"), "Ctrl+,"));
        m.Items.Add(new Separator());
        m.Items.Add(Item("Toggle vertical tabs", ToggleVertical, "Ctrl+Shift+\\"));
        m.Items.Add(Item("Full screen", () => SetFullscreen(!fullscreen), "F11"));
        m.Items.Add(new Separator());
        m.Items.Add(Item("Exit", Close));
        return m;
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
            Title = new TextBlock { TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center },
            Audio = Btn("\uE767", "Mute / unmute tab", t.ToggleMute, 11),
            Close = Btn("\uE711", "Close tab (Ctrl+W)", () => CloseTab(t), 9),
        };
        p.Title.SetResourceReference(TextBlock.ForegroundProperty, "Text");
        foreach (var b in new[] { p.Audio, p.Close }) { b.Width = 22; b.Height = 22; }
        p.Audio.Visibility = Visibility.Collapsed;
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(p.Title, 1); Grid.SetColumn(p.Audio, 2); Grid.SetColumn(p.Close, 3);
        g.Children.Add(p.Fav); g.Children.Add(p.Title); g.Children.Add(p.Audio); g.Children.Add(p.Close);
        var b2 = new Border { Child = g, CornerRadius = new CornerRadius(7), Padding = new Thickness(8, 4, 3, 4), Margin = new Thickness(1, 0, 1, 2), Cursor = Cursors.Hand, Tag = p, Background = Brushes.Transparent };
        b2.MouseLeftButtonDown += (s, e) => Activate(t);
        b2.MouseDown += (s, e) => { if (e.ChangedButton == MouseButton.Middle) CloseTab(t); };
        return b2;
    }

    void Refresh(BrowserTab t)
    {
        if (t.Header == null) return;
        var p = (Parts)t.Header.Tag;
        p.Title.Text = (t.IsPrivate ? "🕶 " : "") + t.DisplayTitle;
        p.Fav.Source = t.Favicon;
        p.Audio.Content = t.Muted ? "\uE74F" : "\uE767";
        p.Audio.Visibility = t.Audible || t.Muted ? Visibility.Visible : Visibility.Collapsed;
        if (t == active) t.Header.SetResourceReference(Border.BackgroundProperty, "TabActive");
        else { t.Header.ClearValue(Border.BackgroundProperty); t.Header.Background = Brushes.Transparent; }
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
        DockPanel.SetDock(newTabBtn, vert ? Dock.Bottom : Dock.Right);
        (vert ? sideWrap : topWrap).Child = tabArea;
        sideWrap.Visibility = vert ? Visibility.Visible : Visibility.Collapsed;
        topWrap.Visibility = vert ? Visibility.Collapsed : Visibility.Visible;
        double w = S.Str("tabWidth") switch { "compact" => 120, "wide" => 240, _ => 180 };
        foreach (var t in tabs) { t.Header.Width = vert ? double.NaN : w; t.Header.HorizontalAlignment = HorizontalAlignment.Stretch; }

        RebuildBookmarks();
        foreach (var t in tabs) { _ = t.ApplyScriptsAsync(); Refresh(t); }
        UpdateChrome(false);
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
            var b = new Button { Content = title, Template = FlatTemplate, Background = Brushes.Transparent, Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(1, 0, 1, 0), Focusable = false, ToolTip = bm.Url, FontSize = 12 };
            b.SetResourceReference(Control.ForegroundProperty, "Text");
            var url = bm.Url;
            b.Click += (_, __) => active?.Navigate(url);
            b.MouseDown += (s, e) => { if (e.ChangedButton == MouseButton.Middle) NewTab(url); };
            var cm = new ContextMenu();
            var rm = new MenuItem { Header = "Remove bookmark" };
            rm.Click += (_, __) => { Services.Bookmarks.Remove(url); Services.Notify(); };
            cm.Items.Add(rm);
            b.ContextMenu = cm;
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
