using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Web.WebView2.Core;
using Veil.Core;

namespace Veil;

static class Native
{
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    public static bool Ctrl => (GetAsyncKeyState(0x11) & 0x8000) != 0;
    public static bool Shift => (GetAsyncKeyState(0x10) & 0x8000) != 0;
    public static bool Alt => (GetAsyncKeyState(0x12) & 0x8000) != 0;
    [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
}

public sealed class BrowserTab
{
    public readonly bool IsPrivate;
    public WebViewHost Host;
    public CoreWebView2 Core;
    public string Url = "";
    public string Title = "";
    public string ErrorUrl;                 // shown in the address bar while a custom error page is displayed
    public ImageSource Favicon;
    public bool Loading, Audible, Muted;
    public string PendingUrl;
    public bool IsPopup;                    // created for window.open: the engine navigates it, we must not
    public Border Header;                   // tab strip item (built by MainWindow)
    public event Action Changed;

    readonly MainWindow win;
    readonly List<string> scriptIds = new();
    Task creating;
    Task applyChain = Task.CompletedTask;
    (string http, string https)? pendingUpgrade;

    public BrowserTab(MainWindow w, bool isPrivate) { win = w; IsPrivate = isPrivate; }

    public string DisplayUrl => ErrorUrl ?? Url;
    public string DisplayTitle
    {
        get
        {
            if (Url.StartsWith("veil://"))
            {
                var h = UrlResolver.HostOf(Url);
                return h == "newtab" ? "New Tab" : char.ToUpper(h[0]) + h.Substring(1);
            }
            return string.IsNullOrEmpty(Title) ? (string.IsNullOrEmpty(Url) ? "New Tab" : UrlResolver.Display(Url)) : Title;
        }
    }
    public bool CanGoBack => Core != null && Core.CanGoBack;
    public bool CanGoForward => Core != null && Core.CanGoForward;
    void Raise() => Changed?.Invoke();

    /// Small trace file (%APPDATA%\Veil\debug.log) so problems loading Veil's own pages can be found.
    public static void Dbg(string msg)
    {
        try
        {
            var dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Veil");
            Directory.CreateDirectory(dir);
            var f = System.IO.Path.Combine(dir, "debug.log");
            if (File.Exists(f) && new FileInfo(f).Length > 200000) File.Delete(f);
            File.AppendAllText(f, DateTime.Now.ToString("HH:mm:ss.fff") + " " + msg + "\n");
        }
        catch { }
    }
    static void Later(Action a) => Application.Current.Dispatcher.BeginInvoke(a);

    public void Navigate(string url)
    {
        Url = url;
        if (Core == null) { PendingUrl = url; Raise(); }
        else { PendingUrl = null; Core.Navigate(url); }
    }
    public void Reload() => Core?.Reload();
    public void Stop() => Core?.Stop();
    public void GoBack() { if (CanGoBack) Core.GoBack(); }
    public void GoForward() { if (CanGoForward) Core.GoForward(); }
    public void ToggleMute() { if (Core != null) { Core.IsMuted = !Core.IsMuted; Muted = Core.IsMuted; Raise(); } }
    public void SetMuted(bool m) { if (Core != null) { Core.IsMuted = m; Muted = m; Raise(); } }
    public void FocusPage() { try { Host?.Controller?.MoveFocus(CoreWebView2MoveFocusReason.Programmatic); } catch { } }

    public Task EnsureCreatedAsync(Grid content) => creating ??= CreateAsync(content);

    async Task CreateAsync(Grid content)
    {
        Host = new WebViewHost();
        content.Children.Add(Host);
        Host.UpdateLayout();
        var hwnd = await Host.HandleReady;
        await Services.Blocker.Ready;
        var opts = Services.Env.CreateCoreWebView2ControllerOptions();
        opts.ProfileName = IsPrivate ? "VeilPrivate" : "Default";
        opts.IsInPrivateModeEnabled = IsPrivate;
        var controller = await Services.Env.CreateCoreWebView2ControllerAsync(hwnd, opts);
        Host.Controller = controller;
        Core = controller.CoreWebView2;
        var dpi = VisualTreeHelper.GetDpi(Host);
        controller.Bounds = new System.Drawing.Rectangle(0, 0,
            Math.Max(1, (int)(Host.ActualWidth * dpi.DpiScaleX)), Math.Max(1, (int)(Host.ActualHeight * dpi.DpiScaleY)));
        controller.IsVisible = Host.IsVisible;
        controller.ZoomFactor = Math.Max(0.25, Services.Settings.Int("defaultZoom") / 100.0);

        var st = Core.Settings;
        st.IsStatusBarEnabled = false;
        st.IsGeneralAutofillEnabled = false;
        st.IsPasswordAutosaveEnabled = false;
        st.AreDevToolsEnabled = Services.Settings.Bool("developerTools");
        ApplyCookieMode();
        Core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        try { Core.AddWebResourceRequestedFilter("veil://*", CoreWebView2WebResourceContext.All); } catch (Exception ex) { Dbg("veil filter: " + ex.Message); }
        Dbg("tab created, scheme filter added");
        Wire(controller);
        await ApplyScriptsAsync();

        if (!IsPopup) Core.Navigate(PendingUrl ?? UrlResolver.NewTab);
        PendingUrl = null;
    }

    public void ApplyCookieMode()
    {
        if (Core == null) return;
        try
        {
            // Windows/WebView2 has no per-request cookie rules; third-party blocking maps to Tracking Prevention.
            Core.Profile.PreferredTrackingPreventionLevel = Services.Settings.Str("cookieMode") == "off"
                ? CoreWebView2TrackingPreventionLevel.None : CoreWebView2TrackingPreventionLevel.Strict;
            // Veil's own pages and websites follow Veil's light / dark setting instead of always following Windows.
            var th = Services.Settings.Str("theme");
            Core.Profile.PreferredColorScheme = th == "light" ? CoreWebView2PreferredColorScheme.Light
                : th == "system" ? CoreWebView2PreferredColorScheme.Auto : CoreWebView2PreferredColorScheme.Dark;
        }
        catch { }
    }

    // ---------- injected scripts ----------
    public Task ApplyScriptsAsync()
    {
        var t = applyChain.ContinueWith(_ => DoApplyAsync(), TaskScheduler.FromCurrentSynchronizationContext()).Unwrap();
        applyChain = t.ContinueWith(_ => { });
        return t;
    }

    async Task DoApplyAsync()
    {
        if (Core == null) return;
        try
        {
            foreach (var id in scriptIds) { try { Core.RemoveScriptToExecuteOnDocumentCreated(id); } catch { } }
            scriptIds.Clear();
            async Task Add(string js) { if (!string.IsNullOrEmpty(js)) scriptIds.Add(await Core.AddScriptToExecuteOnDocumentCreatedAsync(js)); }
            var S = Services.Settings;
            var j = JsonNode.Parse(S.Json());

            await Add("(()=>{if(location.protocol==='veil:')return;" +
                      (S.Bool("sendGPC") ? "try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:()=>true,configurable:true});}catch(e){}" : "") +
                      "})();");
            if (S.Bool("fingerprintProtection")) await Add(Res.Text("fingerprint.js"));

            if (S.Bool("opsecWebRTC") || S.Bool("opsecBeacons") || S.Bool("opsecReferrer") || S.Bool("opsecHardware"))
            {
                var cfg = new JsonObject { ["webrtc"] = S.Bool("opsecWebRTC"), ["beacons"] = S.Bool("opsecBeacons"), ["referrer"] = S.Bool("opsecReferrer"), ["hardware"] = S.Bool("opsecHardware") };
                await Add(Res.Text("opsec.js").Replace("__CONFIG__", cfg.ToJsonString()));
            }

            bool fun = S.Str("pageFilter") != "none" || S.Str("pageFont") != "default" || S.Str("linkStyle") != "default"
                || S.Str("selectionColor") != "default" || S.Bool("smoothScroll") || S.Bool("hideScrollbars") || S.Bool("roundImages")
                || S.Bool("blurImages") || S.Int("dimPages") > 0 || S.Bool("reduceMotion") || S.Bool("forceSelect")
                || S.Bool("readableText") || S.Bool("grayImages");
            if (fun)
            {
                var cfg = new JsonObject();
                foreach (var k in new[] { "pageFilter", "pageFont", "linkStyle", "selectionColor", "smoothScroll", "hideScrollbars", "roundImages", "blurImages", "reduceMotion", "forceSelect", "readableText", "grayImages" })
                    cfg[k] = JsonNode.Parse(j[k].ToJsonString());
                cfg["dimPages"] = Math.Max(0, Math.Min(60, S.Int("dimPages")));
                await Add(Res.Text("fun.js").Replace("__CONFIG__", cfg.ToJsonString()));
            }

            var eng = Services.Blocker.Engine;
            if (eng != null && S.Bool("adBlocking"))
            {
                var css = eng.GenericCss();
                if (css.Length > 0)
                {
                    var allow = JsonSerializer.Serialize(Services.Allowlist.All);
                    await Add("(()=>{try{if(location.protocol==='veil:')return;const A=" + allow + ";const h=location.hostname.replace(/^www\\./,'');" +
                              "if(A.some(d=>h===d||h.endsWith('.'+d)))return;const add=()=>{const s=document.createElement('style');s.textContent=" +
                              JsonSerializer.Serialize(css) + ";document.documentElement.appendChild(s)};" +
                              "if(document.documentElement)add();else new MutationObserver((_,o)=>{if(document.documentElement){o.disconnect();add()}}).observe(document,{childList:true});}catch(e){}})();");
                }
            }
            Core.Settings.AreDevToolsEnabled = S.Bool("developerTools");
            ApplyCookieMode();
        }
        catch { }
    }

    // ---------- events ----------
    static RT MapType(CoreWebView2WebResourceContext c) => c switch
    {
        CoreWebView2WebResourceContext.Script => RT.Script,
        CoreWebView2WebResourceContext.Image => RT.Image,
        CoreWebView2WebResourceContext.Stylesheet => RT.Style,
        CoreWebView2WebResourceContext.XmlHttpRequest => RT.Xhr,
        CoreWebView2WebResourceContext.Fetch => RT.Xhr,
        CoreWebView2WebResourceContext.Media => RT.Media,
        CoreWebView2WebResourceContext.Font => RT.Font,
        CoreWebView2WebResourceContext.Document => RT.Doc,
        _ => RT.Other,
    };

    static string QueryParam(string url, string name)
    {
        int q = url.IndexOf('?');
        if (q < 0) return null;
        foreach (var part in url.Substring(q + 1).Split('&'))
        {
            var kv = part.Split('=', 2);
            if (kv[0] == name && kv.Length == 2) return Uri.UnescapeDataString(kv[1]);
        }
        return null;
    }

    void Wire(CoreWebView2Controller controller)
    {
        Core.WebResourceRequested += OnRequest;

        Core.NavigationStarting += (s, e) =>
        {
            var uri = e.Uri;
            Dbg("NavigationStarting " + uri);
            if (uri.TrimEnd('/').Equals("veil://newtab", StringComparison.OrdinalIgnoreCase))
            {
                // Veil's start page is drawn directly (no veil:// scheme needed), so it always shows up.
                e.Cancel = true;
                Url = UrlResolver.NewTab;
                var page = Pages.NewTabHtml();
                Later(() => Core.NavigateToString(page));
                Raise();
                return;
            }
            if (uri.StartsWith("veil://insecure", StringComparison.OrdinalIgnoreCase))
            {
                e.Cancel = true;
                var u = QueryParam(uri, "u");
                if (u != null && Uri.TryCreate(u, UriKind.Absolute, out var uu)) { Services.InsecureOk.Add(uu.Host); Later(() => Core.Navigate(u)); }
                return;
            }
            bool web = uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
            if (web && Services.Settings.Bool("stripTracking"))
            {
                var cleaned = TrackingParams.Cleaned(uri);
                if (cleaned != null) { e.Cancel = true; Later(() => Core.Navigate(cleaned)); return; }
            }
            if (uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && Services.Settings.Bool("httpsUpgrade")
                && Uri.TryCreate(uri, UriKind.Absolute, out var hu) && !UrlResolver.IsLocalHost(hu.Host) && !Services.InsecureOk.Contains(hu.Host))
            {
                var https = "https://" + uri.Substring(7);
                e.Cancel = true;
                pendingUpgrade = (uri, https);
                Later(() => Core.Navigate(https));
                return;
            }
            if (!uri.StartsWith("data:")) ErrorUrl = null;
            Loading = true; Raise();
        };

        Core.SourceChanged += (s, e) =>
        {
            var src = Core.Source;
            if (src.StartsWith("veil://") && src.EndsWith("/")) src = src.TrimEnd('/');   // veil://newtab/ -> veil://newtab
            if (!src.StartsWith("data:")) Url = src;
            Raise();
        };
        Core.DocumentTitleChanged += (s, e) =>
        {
            Title = Core.DocumentTitle ?? "";
            if (!IsPrivate && Url.StartsWith("http") && Title.Length > 0 && ErrorUrl == null) Services.History.Add(Url, Title);
            Raise();
        };
        Core.NavigationCompleted += (s, e) =>
        {
            Loading = false;
            Dbg("NavigationCompleted ok=" + e.IsSuccess + " status=" + e.WebErrorStatus + " source=" + Core.Source);
            if (!e.IsSuccess)
            {
                if (pendingUpgrade is { } up && e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
                {
                    pendingUpgrade = null;
                    ErrorUrl = up.http;
                    Core.NavigateToString(Pages.ErrorHtml("This site doesn’t support a secure connection",
                        "Veil tried https:// first and it didn’t work. You can continue over http, but anything you send can be read by others on the network.",
                        up.http, up.http));
                }
            }
            else
            {
                pendingUpgrade = null;
                if (!IsPrivate && Url.StartsWith("http")) Services.History.Add(Url, Core.DocumentTitle ?? "");
            }
            Raise();
        };
        Core.DOMContentLoaded += async (s, e) =>
        {
            try
            {
                var eng = Services.Blocker.Engine;
                var host = UrlResolver.HostOf(Url);
                if (eng == null || !Services.Settings.Bool("adBlocking") || !Url.StartsWith("http") || Services.Allowlist.Contains(host)) return;
                var css = eng.CssForHost(host);
                if (css.Length == 0) return;
                await Core.ExecuteScriptAsync("(()=>{const s=document.createElement('style');s.textContent=" + JsonSerializer.Serialize(css) +
                                              ";(document.head||document.documentElement).appendChild(s)})()");
            }
            catch { }
        };
        Core.FaviconChanged += async (s, e) =>
        {
            try
            {
                using var st = await Core.GetFaviconAsync(CoreWebView2FaviconImageFormat.Png);
                if (st == null) { Favicon = null; Raise(); return; }
                var ms = new MemoryStream();
                await st.CopyToAsync(ms);
                var bytes = ms.ToArray();
                var bi = new BitmapImage();
                bi.BeginInit(); bi.CacheOption = BitmapCacheOption.OnLoad; bi.StreamSource = new MemoryStream(bytes); bi.EndInit(); bi.Freeze();
                Favicon = bi;
                if (!IsPrivate) Services.SaveFavicon(UrlResolver.HostOf(Url), bytes);
                Raise();
            }
            catch { }
        };
        Core.IsDocumentPlayingAudioChanged += (s, e) => { Audible = Core.IsDocumentPlayingAudio; Raise(); };
        Core.ContainsFullScreenElementChanged += (s, e) => win.SetFullscreen(Core.ContainsFullScreenElement);
        Core.WindowCloseRequested += (s, e) => win.CloseTab(this);
        Core.DownloadStarting += (s, e) => Services.Downloads.Attach(e);
        Core.ProcessFailed += (s, e) => Dbg("ProcessFailed " + e.ProcessFailedKind + " " + e.Reason);

        Core.NewWindowRequested += async (s, e) =>
        {
            if (Services.Settings.Bool("blockPopups") && !e.IsUserInitiated) { e.Handled = true; return; }
            var d = e.GetDeferral();
            try
            {
                var t = await win.CreatePopupTabAsync(IsPrivate);
                e.NewWindow = t.Core;
                e.Handled = true;
            }
            catch { e.Handled = true; }
            finally { d.Complete(); }
        };

        Core.PermissionRequested += (s, e) =>
        {
            string k = e.PermissionKind == CoreWebView2PermissionKind.Microphone ? "microphone"
                     : e.PermissionKind == CoreWebView2PermissionKind.Camera ? "camera" : null;
            if (k == null) return;
            if (Services.Settings.Bool("denyMedia")) { e.State = CoreWebView2PermissionState.Deny; return; }
            var host = UrlResolver.HostOf(e.Uri);
            var prev = Services.Permissions.Get(host, k);
            if (prev.HasValue) { e.State = prev.Value ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny; return; }
            bool ok = MessageBox.Show($"Allow {host} to use your {k}?", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes;
            if (!IsPrivate) Services.Permissions.Set(host, k, ok);
            e.State = ok ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
        };

        Core.WebMessageReceived += async (s, e) =>
        {
            Dbg("WebMessage from " + e.Source);
            if (!(e.Source ?? "").StartsWith("veil://", StringComparison.OrdinalIgnoreCase)) return;   // web pages can never use the bridge
            try
            {
                using var doc = JsonDocument.Parse(e.WebMessageAsJson);
                var root = doc.RootElement;
                var id = root.GetProperty("id").GetInt32();
                var cmd = root.GetProperty("cmd").GetString();
                var args = root.TryGetProperty("args", out var a) ? a : default;
                JsonNode result = null;
                try { result = await Bridge.Handle(this, cmd, args); } catch (Exception bex) { Dbg("Bridge " + cmd + " failed: " + bex); }
                Core.PostWebMessageAsJson(new JsonObject { ["id"] = id, ["result"] = result }.ToJsonString());
            }
            catch { }
        };

        controller.AcceleratorKeyPressed += (s, e) =>
        {
            if (e.KeyEventKind != CoreWebView2KeyEventKind.KeyDown && e.KeyEventKind != CoreWebView2KeyEventKind.SystemKeyDown) return;
            var key = KeyInterop.KeyFromVirtualKey((int)e.VirtualKey);
            if (win.HandleShortcut(key, Native.Ctrl, Native.Shift, Native.Alt)) e.Handled = true;
        };
    }

    void OnRequest(object sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        var uri = e.Request.Uri;
        if (uri.StartsWith("veil://", StringComparison.OrdinalIgnoreCase))
        {
            Dbg("Request " + uri);
            string html;
            try { html = Uri.TryCreate(uri, UriKind.Absolute, out var u) ? Pages.Html(u.Host) : null; }
            catch (Exception ex)
            {
                // Show the problem instead of a blank page.
                html = "<!doctype html><meta charset=utf-8><body style=\"font:14px Segoe UI,sans-serif;padding:24px;color:#ddd;background:#17171a\"><h2>Veil page error</h2><pre style=\"white-space:pre-wrap\">"
                       + Pages.Escape(ex.ToString()) + "</pre>";
            }
            Dbg("Serving " + uri + " bytes=" + (html == null ? -1 : html.Length));
            if (html == null) { e.Response = Services.Env.CreateWebResourceResponse(null, 404, "Not Found", ""); return; }
            e.Response = Services.Env.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)), 200, "OK",
                "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: " + Pages.Csp);
            return;
        }
        if (!(uri.StartsWith("http://") || uri.StartsWith("https://") || uri.StartsWith("ws://") || uri.StartsWith("wss://"))) return;
        if (Services.Settings.Bool("sendGPC")) e.Request.Headers.SetHeader("Sec-GPC", "1");
        var ctx = e.ResourceContext;
        if (ctx == CoreWebView2WebResourceContext.Document) return;
        if (Services.Blocker.ShouldBlock(uri, UrlResolver.HostOf(Url), MapType(ctx)))
            e.Response = Services.Env.CreateWebResourceResponse(null, 403, "Blocked", "");
    }

    public void Dispose(Grid content)
    {
        try { content.Children.Remove(Host); Host?.Dispose(); } catch { }
        Host = null; Core = null;
    }
}
