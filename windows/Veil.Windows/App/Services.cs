using Microsoft.Web.WebView2.Core;
using Veil.Core;

namespace Veil;

/// Process-wide state. Everything persists under %APPDATA%\Veil plus WebView2's own profile folder.
public static class Services
{
    public static SettingsStore Settings;
    public static HistoryStore History;
    public static BookmarkStore Bookmarks;
    public static AllowlistStore Allowlist;
    public static PermissionStore Permissions;
    public static JsonStore<SessionState> Session;
    public static JsonStore<WindowBounds> Window;
    public static JsonStore<string> StartBackground;
    public static Blocker Blocker;
    public static DownloadManager Downloads;
    public static CoreWebView2Environment Env;
    public static readonly HashSet<string> InsecureOk = new();
    public static event Action Changed;

    public static void Init()
    {
        Settings = new SettingsStore();
        History = new HistoryStore();
        Bookmarks = new BookmarkStore();
        Allowlist = new AllowlistStore();
        Permissions = new PermissionStore();
        Session = new JsonStore<SessionState>("session", () => new());
        Window = new JsonStore<WindowBounds>("window", () => new());
        StartBackground = new JsonStore<string>("start-background", () => "");
        Blocker = new Blocker();
        Downloads = new DownloadManager();
    }

    public static async Task InitEnvAsync()
    {
        try
        {
            var reg = new CoreWebView2CustomSchemeRegistration("veil")
            {
                TreatAsSecure = true,
                HasAuthorityComponent = true,
            };
            var opts = new CoreWebView2EnvironmentOptions();
            if (opts.CustomSchemeRegistrations != null)
                opts.CustomSchemeRegistrations.Add(reg);
            else
            {
                var p = typeof(CoreWebView2EnvironmentOptions).GetProperty("CustomSchemeRegistrations");
                if (p != null && p.CanWrite)
                    p.SetValue(opts, new List<CoreWebView2CustomSchemeRegistration> { reg });
            }
            Directory.CreateDirectory(Paths.WebViewDir);
            Env = await CoreWebView2Environment.CreateAsync(null, Paths.WebViewDir, opts);
        }
        catch (Exception ex)
        {
            // Rethrow with the full detail so the error box shows exactly where it failed.
            throw new Exception(ex.ToString());
        }
    }

    public static void Notify() => Changed?.Invoke();

    public static void FlushAll()
    {
        Settings.Flush(); History.Flush(); Bookmarks.Flush(); Allowlist.Flush(); Permissions.Flush();
        Session.Flush(); Window.Flush(); StartBackground.Flush(); Blocker.Meta.Flush(); Downloads.Flush();
    }

    // ---- favicon cache (start-page shortcuts show icons before the sites are opened) ----
    static string FavDir { get { var d = System.IO.Path.Combine(Paths.DataDir, "favicons"); Directory.CreateDirectory(d); return d; } }
    static string FavFile(string host) => System.IO.Path.Combine(FavDir, new string(host.Where(c => char.IsLetterOrDigit(c) || c == '.' || c == '-').ToArray()) + ".png");
    public static void SaveFavicon(string host, byte[] png)
    {
        if (string.IsNullOrEmpty(host) || png == null || png.Length == 0) return;
        try { File.WriteAllBytes(FavFile(host), png); } catch { }
    }
    public static byte[] LoadFavicon(string host)
    {
        try { var f = FavFile(host); return File.Exists(f) ? File.ReadAllBytes(f) : null; } catch { return null; }
    }
}
