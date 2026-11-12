using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Veil.Core;
using Veil.Tor;

namespace Veil;

/// "New Tor window": the normal MainWindow running in Tor mode. Same toolbar, tab strip and theme; differences:
///  - its own WebView2 environment + in-private profile (TorBrowserEnv), all traffic via Tor's SOCKS5 port,
///  - no bookmarks / history / downloads list / session saving / bridge pages,
///  - fails closed: nothing loads unless Tor is verified and currently connected.
public sealed partial class MainWindow
{
    static readonly List<MainWindow> torWindows = new();
    static readonly Brush TorPurple = Frozen(Color.FromRgb(0x7D, 0x46, 0x98));
    static readonly Brush TorPurpleTint = Frozen(Color.FromArgb(0x30, 0x7D, 0x46, 0x98));
    static readonly Brush DotGreen = Frozen(Color.FromRgb(0x3F, 0xB9, 0x50));
    static readonly Brush DotAmber = Frozen(Color.FromRgb(0xE8, 0xB0, 0x58));
    static readonly Brush DotRed = Frozen(Color.FromRgb(0xE0, 0x4F, 0x4F));
    static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

    readonly bool isTor;
    public bool IsTor => isTor;
    public string TorProfileName { get; } = "VeilTor" + Guid.NewGuid().ToString("N").Substring(0, 12);

    readonly TaskCompletionSource<CoreWebView2Environment> torEnvTcs = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public Task<CoreWebView2Environment> TorEnvTask => torEnvTcs.Task;
    readonly CancellationTokenSource torCts = new();

    bool torReady;        // verified through Tor itself AND through this window's browser: http(s) may load while Tor is connected
    bool torVerifying;    // only check.torproject.org's API may load
    bool torLease, torEnvHeld, torClosed, torFailed;
    string torFailText = "";
    Action torChangedHandler;

    Border torPill, torOverlay;
    System.Windows.Shapes.Ellipse torDot;
    TextBlock torLabel, torOverlayTitle, torOverlayText;
    Button torRetryBtn;

    string SearchTemplate => isTor ? SearchEngines.Template("duckduckgo") : SearchEngines.Template(Services.Settings.Str("searchEngine"));

    /// True only while this window may talk to the network: verified AND Tor reports Connected right now.
    public bool TorUsable => isTor && torReady && TorManager.Instance.State == TorState.Connected;

    /// Navigation gate used by every Tor tab (see BrowserTab.NavigationStarting).
    public bool TorAllows(string uri)
    {
        if (!isTor) return true;
        var low = (uri ?? "").ToLowerInvariant();
        if (low == "about:blank" || low.StartsWith("data:") || low.StartsWith("veil://")) return true;   // local pages, no network
        if (low.StartsWith("http://") || low.StartsWith("https://"))
            return TorUsable || (torVerifying && uri.StartsWith(TorManager.CheckApi, StringComparison.Ordinal));
        return false;     // file:, ftp:, edge: ... are not available in a Tor window
    }

    // ---------- opening / closing ----------

    public static void OpenTorWindow()
    {
        if (!TorManager.IsInstalled)
        {
            MessageBox.Show("Tor is not included in this copy of Veil.\n\nRun windows\\scripts\\fetch_tor.ps1 and rebuild, or copy the official Tor Expert Bundle " +
                            "into a folder named \"tor\" next to Veil.exe.", "Veil", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var opener = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault(x => x.IsActive) ?? Current;
        var w = new MainWindow(null, true);
        if (opener != null && opener.WindowState == WindowState.Normal && opener.ActualWidth > 300)
        {
            w.WindowStartupLocation = WindowStartupLocation.Manual;
            w.Width = opener.ActualWidth; w.Height = opener.ActualHeight;
            w.Left = opener.Left + 32; w.Top = opener.Top + 32;
        }
        else { w.Width = 1100; w.Height = 720; w.WindowStartupLocation = WindowStartupLocation.CenterScreen; }
        torWindows.Add(w);
        w.Closed += (s, e) => w.TorOnClosed();
        w.Show();
    }

    static void CloseAllTorWindows()
    {
        foreach (var w in torWindows.ToList()) { try { w.Close(); } catch { } }
    }

    /// Runs while the window is closing: stop everything that could still touch the network and wipe cookies.
    void TorOnClosing()
    {
        torClosed = true;
        try { torCts.Cancel(); } catch { }
        if (torChangedHandler != null) TorManager.Instance.Changed -= torChangedHandler;
        try { tabs.Select(t => t.Core).FirstOrDefault(c => c != null)?.CookieManager.DeleteAllCookies(); } catch { }
    }

    /// Runs after the window is gone: drop the browser views, then the profile environment (deletes its folder),
    /// then our lease on Tor (the last lease stops tor.exe).
    async void TorOnClosed()
    {
        torWindows.Remove(this);
        try { foreach (var t in tabs.ToList()) t.Dispose(content); } catch { }
        tabs.Clear();
        try { if (torEnvHeld) { torEnvHeld = false; await TorBrowserEnv.ReleaseAsync(); } } catch { }
        try { if (torLease) { torLease = false; TorManager.Instance.Release(); } } catch { }
    }

    // ---------- startup ----------

    async Task TorStartAsync()
    {
        torChangedHandler = () => Dispatcher.BeginInvoke(new Action(OnTorChanged));
        TorManager.Instance.Changed += torChangedHandler;
        OnServicesChanged();      // lays out the tab strip and applies the theme
        await TorConnectAsync();
    }

    async Task TorConnectAsync()
    {
        torFailed = false; torFailText = "";
        var ct = torCts.Token;
        try
        {
            ShowTorOverlay("Connecting to Tor", "Starting Tor…", false);
            if (!torLease)
            {
                await TorManager.Instance.AcquireAsync(ct);
                torLease = true;
                if (torClosed) { torLease = false; TorManager.Instance.Release(); return; }
            }
            await TorManager.Instance.WaitConnectedAsync(ct);

            if (!torEnvHeld)
            {
                var env = await TorBrowserEnv.AcquireAsync(TorManager.Instance.SocksPort);
                torEnvHeld = true;
                if (torClosed) { torEnvHeld = false; await TorBrowserEnv.ReleaseAsync(); return; }
                torEnvTcs.TrySetResult(env);
            }

            // Second, independent proof: load the Tor Project's check API inside THIS window's own browser engine.
            HideTorOverlay();
            UpdateTorPill();
            if (!await VerifyBrowserPathAsync(ct))
                throw new IOException("Pages in this window did not arrive through Tor (check.torproject.org says IsTor = false, or it could not be reached). " +
                                      "The window was locked instead of falling back to a direct connection.");
            torReady = true;
            var first = tabs.FirstOrDefault();
            if (first != null) first.Navigate(UrlResolver.NewTab); else NewTab();
            if (TorManager.Instance.State != TorState.Connected) OnTorChanged(); else HideTorOverlay();
            UpdateTorPill();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            torFailed = true; torFailText = ex.Message;
            ShowTorOverlay("Could not start the Tor window", ex.Message, true);
        }
    }

    async Task<bool> VerifyBrowserPathAsync(CancellationToken ct)
    {
        torVerifying = true;
        UpdateTorPill();
        try
        {
            var t = tabs.FirstOrDefault() ?? NewTab("about:blank");
            if (t == null) return false;
            await t.EnsureCreatedAsync(content);
            var core = t.Core;
            if (core == null) return false;

            ulong navId = 0;
            var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            EventHandler<CoreWebView2NavigationStartingEventArgs> started = (s, e) =>
            {
                if (e.Uri.StartsWith(TorManager.CheckApi, StringComparison.Ordinal)) navId = e.NavigationId;
            };
            EventHandler<CoreWebView2NavigationCompletedEventArgs> completed = (s, e) =>
            {
                if (navId != 0 && e.NavigationId == navId) tcs.TrySetResult(e.IsSuccess);
            };
            core.NavigationStarting += started;
            core.NavigationCompleted += completed;
            try
            {
                t.Navigate(TorManager.CheckApi);
                var done = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(75), ct));
                if (done != tcs.Task || !tcs.Task.Result) return false;
                var raw = await core.ExecuteScriptAsync("document.body ? document.body.innerText : ''");
                var text = JsonSerializer.Deserialize<string>(raw) ?? "";
                using var doc = JsonDocument.Parse(text);
                return doc.RootElement.TryGetProperty("IsTor", out var v) && v.ValueKind == JsonValueKind.True;
            }
            finally { core.NavigationStarting -= started; core.NavigationCompleted -= completed; }
        }
        catch (OperationCanceledException) { throw; }
        catch { return false; }
        finally { torVerifying = false; }
    }

    // ---------- reacting to Tor going away / coming back ----------

    void OnTorChanged()
    {
        if (torClosed) return;
        var m = TorManager.Instance;
        if (!torReady)
        {
            if (!torFailed && !torVerifying && m.State == TorState.Starting) torOverlayText.Text = m.Detail;
            UpdateTorPill();
            return;
        }
        if (m.State == TorState.Connected)
        {
            if (torOverlay.Visibility == Visibility.Visible) HideTorOverlay();
        }
        else if (m.State == TorState.Failed)
            ShowTorOverlay("Tor is not connected", m.Detail + "\n\nNothing loads until Tor is back. Veil never falls back to a direct connection.", true);
        else
            ShowTorOverlay("Tor is not connected", (m.Detail.Length > 0 ? m.Detail : "Reconnecting…") + "\n\nNothing loads until Tor is back. Veil never falls back to a direct connection.", false);
        UpdateTorPill();
    }

    async void TorRetry()
    {
        if (!torReady)
        {
            await TorConnectAsync();       // startup or browser verification failed: run the whole sequence again
            return;
        }
        ShowTorOverlay("Reconnecting to Tor", "Restarting Tor…", false);
        await TorManager.Instance.RetryAsync();
    }

    // ---------- UI ----------

    static UIElement OnionImage(double size, Thickness margin)
    {
        try
        {
            return new Image { Source = TorLogo.Bitmap(), Width = size, Height = size, Margin = margin, Stretch = Stretch.Uniform,
                               VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        }
        catch { return new TextBlock { Text = "Tor", FontWeight = FontWeights.SemiBold, Margin = margin, VerticalAlignment = VerticalAlignment.Center }; }
    }

    void BuildTorOverlay()
    {
        torOverlayTitle = new TextBlock { FontSize = 20, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 10, 0, 8) };
        torOverlayText = new TextBlock { FontSize = 13, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, MaxWidth = 520 };
        torOverlayTitle.SetResourceReference(TextBlock.ForegroundProperty, "Text");
        torOverlayText.SetResourceReference(TextBlock.ForegroundProperty, "Mute");
        torRetryBtn = new Button
        {
            Content = "Try again", Template = FlatTemplate, Padding = new Thickness(16, 7, 16, 7), Margin = new Thickness(0, 18, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center, Background = TorPurpleTint, Visibility = Visibility.Collapsed, Focusable = false,
        };
        torRetryBtn.SetResourceReference(Control.ForegroundProperty, "Text");
        torRetryBtn.Click += (s, e) => TorRetry();
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        stack.Children.Add(OnionImage(72, new Thickness(0)));
        stack.Children.Add(torOverlayTitle);
        stack.Children.Add(torOverlayText);
        stack.Children.Add(torRetryBtn);
        torOverlay = new Border { Child = stack, Visibility = Visibility.Collapsed, Padding = new Thickness(24) };
        torOverlay.SetResourceReference(Border.BackgroundProperty, "Bg");
        Panel.SetZIndex(torOverlay, 100);
        content.Children.Add(torOverlay);
    }

    Border BuildTorPill()
    {
        torDot = new System.Windows.Shapes.Ellipse { Width = 8, Height = 8, Margin = new Thickness(0, 0, 6, 0), Fill = DotAmber };
        torLabel = new TextBlock { Text = "Tor…", FontSize = 12, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        torLabel.SetResourceReference(TextBlock.ForegroundProperty, "Text");
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(OnionImage(18, new Thickness(0, 0, 6, 0)));
        sp.Children.Add(torDot);
        sp.Children.Add(torLabel);
        var b = new Border
        {
            Child = sp, CornerRadius = new CornerRadius(13), Padding = new Thickness(9, 0, 10, 0), Margin = new Thickness(2, 0, 4, 0), Height = 26,
            Background = TorPurpleTint, BorderBrush = TorPurple, BorderThickness = new Thickness(1), Cursor = Cursors.Hand, VerticalAlignment = VerticalAlignment.Center,
        };
        b.MouseLeftButtonUp += (s, e) => ShowTorStatusMenu();
        return b;
    }

    string TorStatusText()
    {
        if (torFailed) return "Not connected: " + torFailText;
        if (!torReady) return torVerifying ? "Verifying that this window uses Tor…" : "Connecting to Tor…";
        var m = TorManager.Instance;
        return m.State == TorState.Connected ? "Connected to Tor (verified)" : "Not connected: " + m.Detail;
    }

    void UpdateTorPill()
    {
        if (torPill == null) return;
        Brush dot; string label;
        if (torFailed) { dot = DotRed; label = "Tor: error"; }
        else if (!torReady) { dot = DotAmber; label = torVerifying ? "Tor: checking" : "Tor…"; }
        else if (TorManager.Instance.State == TorState.Connected) { dot = DotGreen; label = "Tor"; }
        else { dot = DotRed; label = "Tor: offline"; }
        torDot.Fill = dot;
        torLabel.Text = label;
        torPill.ToolTip = TorStatusText();
    }

    void ShowTorOverlay(string title, string text, bool retry)
    {
        if (torOverlay == null) return;
        torOverlayTitle.Text = title;
        torOverlayText.Text = text;
        torRetryBtn.Visibility = retry ? Visibility.Visible : Visibility.Collapsed;
        torOverlay.Visibility = Visibility.Visible;
        // WebView2 is a native child window and would draw on top of WPF content, so hide the pages while the notice is up.
        foreach (var t in tabs) if (t.Host != null) t.Host.Visibility = Visibility.Collapsed;
        UpdateTorPill();
    }

    void HideTorOverlay()
    {
        if (torOverlay == null) return;
        torOverlay.Visibility = Visibility.Collapsed;
        if (active != null) Activate(active);
    }

    void ApplyTorChrome()
    {
        // Nothing that persists or that points at the normal profile: no bookmark star, ad-block allow-list shield or downloads list.
        starB.Visibility = shieldB.Visibility = dlB.Visibility = Visibility.Collapsed;
        bookmarksWrap.Visibility = Visibility.Collapsed;
        UpdateTorPill();
    }

    void ShowTorStatusMenu()
    {
        VeilMenu.Show(torPill, new[]
        {
            MenuEntry.Item(TorStatusText(), () => { }, "", false),
            MenuEntry.Sep(),
            MenuEntry.Item("Check Tor connection", () => NewTab("https://check.torproject.org/"), "", TorUsable),
            MenuEntry.Item("Try again", () => TorRetry(), "", torFailed || (torReady && TorManager.Instance.State != TorState.Connected)),
        }, rightAlign: true);
    }

    void ShowTorMenu()
    {
        VeilMenu.Show(menuB, new[]
        {
            MenuEntry.Item("New tab", () => NewTab(), "Ctrl+T"),
            MenuEntry.Item("New Tor window", () => OpenTorWindow(), "Alt+Shift+N"),
            MenuEntry.Sep(),
            MenuEntry.Item("Check Tor connection", () => NewTab("https://check.torproject.org/"), "", TorUsable),
            MenuEntry.Item("Full screen", () => SetFullscreen(!fullscreen), "F11"),
            MenuEntry.Sep(),
            MenuEntry.Item("Close Tor window", () => Close()),
        }, rightAlign: true);
    }
}
