using Microsoft.Web.WebView2.Core;

namespace Veil.Tor;

/// The WebView2 environment used by every Tor window. It is completely separate from Services.Env:
///  - its own throw-away user-data folder (deleted when the last Tor window closes, and swept at the next start),
///  - its own browser process, launched with Chromium switches that force ALL of its network traffic through Tor.
/// Reference counted; one environment is shared by all open Tor windows, each window has its own in-private profile.
public static class TorBrowserEnv
{
    static readonly SemaphoreSlim gate = new(1, 1);
    static CoreWebView2Environment env;
    static string folder;
    static int refs, port;

    public static string Root
    {
        get
        {
            var d = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Veil", "TorSession");
            Directory.CreateDirectory(d);
            return d;
        }
    }

    /// Chromium switches for the Tor browser process. Each one is a layer of the "no leaks" design:
    ///  --proxy-server            every request goes to Tor's SOCKS5 port; if it is down the request FAILS (no DIRECT fallback)
    ///  --proxy-bypass-list       "<-loopback>" removes Chromium's implicit "localhost goes direct" rule
    ///  --host-resolver-rules     any lookup Chromium would do itself fails; with socks5:// the proxy resolves names (via Tor)
    ///  --disable-quic            QUIC/HTTP3 is UDP and cannot be proxied
    ///  --force-webrtc-ip-handling-policy  WebRTC may not use UDP outside the proxy (no local/public IP leak)
    public static string BuildArguments(int socksPort) => string.Join(" ", new[]
    {
        "--proxy-server=\"socks5://127.0.0.1:" + socksPort + "\"",
        "--proxy-bypass-list=<-loopback>",
        "--host-resolver-rules=\"MAP * ~NOTFOUND , EXCLUDE 127.0.0.1\"",
        "--disable-quic",
        "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
        "--no-pings",
        "--disable-background-networking",
    });

    public static async Task<CoreWebView2Environment> AcquireAsync(int socksPort)
    {
        await gate.WaitAsync();
        try
        {
            if (env != null)
            {
                if (port != socksPort) throw new InvalidOperationException("Tor's SOCKS port changed while Tor windows were open.");
                refs++;
                return env;
            }
            CleanStale(null);
            var dir = System.IO.Path.Combine(Root, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            var opts = new CoreWebView2EnvironmentOptions { AdditionalBrowserArguments = BuildArguments(socksPort) };
            var reg = new CoreWebView2CustomSchemeRegistration("veil") { TreatAsSecure = true, HasAuthorityComponent = true };
            if (opts.CustomSchemeRegistrations != null) opts.CustomSchemeRegistrations.Add(reg);
            else
            {
                var prop = typeof(CoreWebView2EnvironmentOptions).GetProperty("CustomSchemeRegistrations");
                if (prop != null && prop.CanWrite) prop.SetValue(opts, new List<CoreWebView2CustomSchemeRegistration> { reg });
            }
            env = await CoreWebView2Environment.CreateAsync(null, dir, opts);
            folder = dir; port = socksPort; refs = 1;
            return env;
        }
        finally { gate.Release(); }
    }

    /// Called when a Tor window has closed its tabs. The last release drops the environment and deletes the folder.
    public static async Task ReleaseAsync()
    {
        string toDelete;
        await gate.WaitAsync();
        try
        {
            if (env == null) return;
            if (--refs > 0) return;
            toDelete = folder;
            env = null; folder = null; port = 0;
        }
        finally { gate.Release(); }

        // The browser process exits once every WebView2 object is released; its files stay locked until then.
        GC.Collect(); GC.WaitForPendingFinalizers();
        _ = Task.Run(async () =>
        {
            for (int i = 0; i < 40; i++)
            {
                try { if (!Directory.Exists(toDelete)) return; Directory.Delete(toDelete, true); return; }
                catch { await Task.Delay(1500); if (i % 5 == 4) { GC.Collect(); GC.WaitForPendingFinalizers(); } }
            }
        });
    }

    /// Deletes leftover session folders (crash, forced quit). Called at startup and before a new environment is made.
    public static void CleanStale(string keep)
    {
        try
        {
            foreach (var d in Directory.EnumerateDirectories(Root))
            {
                if (keep != null && string.Equals(d, keep, StringComparison.OrdinalIgnoreCase)) continue;
                if (string.Equals(d, folder, StringComparison.OrdinalIgnoreCase)) continue;
                try { Directory.Delete(d, true); } catch { }
            }
        }
        catch { }
    }

    /// Synchronous best effort at application exit.
    public static void DeleteAllNow()
    {
        for (int i = 0; i < 6; i++)
        {
            try
            {
                foreach (var d in Directory.EnumerateDirectories(Root)) Directory.Delete(d, true);
                return;
            }
            catch { Thread.Sleep(500); }
        }
    }
}
