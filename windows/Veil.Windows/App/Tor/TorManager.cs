using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Veil.Tor;

public enum TorState { Stopped, Starting, Connected, Disconnected, Failed }

/// Owns the one tor.exe process shared by all Tor windows (reference counted: started with the first Tor window,
/// stopped when the last one closes). Tor itself is the unmodified, official binary from the Tor Expert Bundle.
///
/// "Connected" is only ever reported after:
///   1. Tor reports bootstrap 100% and an established circuit (control port), and
///   2. check.torproject.org, reached *through Tor's SOCKS port*, says IsTor = true.
public sealed class TorManager
{
    public static readonly TorManager Instance = new();
    TorManager() { }

    public const string CheckApi = "https://check.torproject.org/api/ip";

    readonly object sync = new();
    readonly SemaphoreSlim gate = new(1, 1);
    readonly CancellationTokenSource lifetime = new();
    TorState state = TorState.Stopped;
    int progress, socksPort, leases;
    string detail = "";
    bool stopping;
    Process proc;
    readonly System.Collections.Concurrent.ConcurrentQueue<string> torOut = new();
    TorControl ctl;
    CancellationTokenSource monitorCts;

    /// Raised on a background thread. Subscribers must marshal to the UI thread themselves.
    public event Action Changed;

    public TorState State { get { lock (sync) return state; } }
    public int Progress { get { lock (sync) return progress; } }
    public string Detail { get { lock (sync) return detail; } }
    public int SocksPort { get { lock (sync) return socksPort; } }

    // ---------- locations ----------
    static string BaseDir => System.IO.Path.GetDirectoryName(Environment.ProcessPath ?? "") ?? AppContext.BaseDirectory;

    static string foundRoot;

    public static string FindTorExe()
    {
        foreach (var root in new[] { System.IO.Path.Combine(AppContext.BaseDirectory, "tor"), System.IO.Path.Combine(BaseDir, "tor") })
        {
            try
            {
                if (!Directory.Exists(root)) continue;
                var exe = Directory.EnumerateFiles(root, "tor.exe", SearchOption.AllDirectories).FirstOrDefault();
                if (exe != null) { foundRoot = root; return exe; }
            }
            catch { }
        }
        return null;
    }

    public static bool IsInstalled => FindTorExe() != null;

    static string TorRoot
    {
        get
        {
            var d = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Veil", "Tor");
            Directory.CreateDirectory(d);
            return d;
        }
    }

    void Pump(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        torOut.Enqueue(line);
        while (torOut.Count > 40 && torOut.TryDequeue(out _)) { }
        Log("tor: " + line);
    }

    string Why(Exception ex)
    {
        var p = proc;
        string exit = "";
        try { if (p != null && p.HasExited) exit = " (tor.exe exit code " + p.ExitCode + ")"; } catch { }
        var tail = string.Join(" | ", torOut.TakeLast(12));
        return ex.Message + exit + (tail.Length > 0 ? "  Tor said: " + tail : "  Tor printed nothing.");
    }

    static string Log(string msg)
    {
        try { File.AppendAllText(System.IO.Path.Combine(TorRoot, "veil-tor.log"), DateTime.Now.ToString("HH:mm:ss ") + msg + "\n"); } catch { }
        return msg;
    }

    // ---------- public API ----------

    /// Starts Tor if needed, waits until it is bootstrapped AND verified, and takes a lease. Returns the SOCKS port.
    /// Every successful call must be paired with Release().
    public async Task<int> AcquireAsync(CancellationToken ct)
    {
        await gate.WaitAsync(ct);
        try
        {
            bool join;
            lock (sync) join = leases > 0 && state != TorState.Failed;
            if (!join)
            {
                try { await StartLockedAsync(ct); }
                catch
                {
                    bool unused; lock (sync) unused = leases == 0;
                    if (unused) await StopLockedAsync();
                    throw;
                }
                if (ct.IsCancellationRequested)
                {
                    bool unused; lock (sync) unused = leases == 0;
                    if (unused) await StopLockedAsync();
                    ct.ThrowIfCancellationRequested();
                }
            }
            lock (sync) { leases++; return socksPort; }
        }
        finally { gate.Release(); }
    }

    /// Waits until the state is Connected (used by windows that joined an already running Tor).
    public async Task WaitConnectedAsync(CancellationToken ct)
    {
        var deadline = DateTime.UtcNow.AddSeconds(150);
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var s = State;
            if (s == TorState.Connected) return;
            if (s == TorState.Failed || s == TorState.Stopped) throw new IOException(Detail.Length > 0 ? Detail : "Tor is not running.");
            if (DateTime.UtcNow > deadline) throw new TimeoutException("Timed out waiting for Tor.");
            await Task.Delay(400, ct);
        }
    }

    /// Gives a lease back; the last one stops Tor.
    public void Release()
    {
        bool last;
        lock (sync) { if (leases > 0) leases--; last = leases == 0; }
        if (last) _ = Task.Run(async () =>
        {
            await gate.WaitAsync();
            try
            {
                bool still; lock (sync) still = leases > 0;
                if (!still) await StopLockedAsync();
            }
            finally { gate.Release(); }
        });
    }

    /// "Retry" button: restart Tor after a failure.
    public async Task RetryAsync()
    {
        await gate.WaitAsync();
        try { await StartLockedAsync(lifetime.Token); }
        catch (Exception ex) { Log("Retry failed: " + ex.Message); }
        finally { gate.Release(); }
    }

    /// Synchronous hard stop used when Veil exits.
    public void Shutdown()
    {
        stopping = true;
        try { lifetime.Cancel(); } catch { }
        try { monitorCts?.Cancel(); } catch { }
        try { if (proc != null && !proc.HasExited) proc.Kill(true); } catch { }
        try { ctl?.Dispose(); } catch { }
    }

    // ---------- start / stop ----------

    void Set(TorState s, int pct, string text)
    {
        lock (sync) { state = s; progress = pct; detail = text ?? ""; }
        try { Changed?.Invoke(); } catch { }
    }

    static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    static string Q(string path) => "\"" + path.Replace('\\', '/') + "\"";

    async Task StartLockedAsync(CancellationToken ct)
    {
        var exe = FindTorExe() ?? throw new FileNotFoundException(
            "tor.exe was not found next to Veil. Run windows\\scripts\\fetch_tor.ps1 and rebuild (see windows\\README.md).");
        Set(TorState.Starting, 0, "Starting Tor…");
        try
        {
            try { monitorCts?.Cancel(); } catch { }
            KillProcess();
            stopping = false;

            var root = TorRoot;
            var dataDir = System.IO.Path.Combine(root, "data");
            var runDir = System.IO.Path.Combine(root, "run");
            Directory.CreateDirectory(dataDir);
            Directory.CreateDirectory(runDir);

            int port;
            lock (sync) { if (leases == 0 || socksPort == 0) socksPort = FreePort(); port = socksPort; }
            int ctlPort; do { ctlPort = FreePort(); } while (ctlPort == port);

            var cookie = System.IO.Path.Combine(runDir, "control_auth_cookie");
            try { File.Delete(cookie); } catch { }
            var torLog = System.IO.Path.Combine(runDir, "tor.log");
            try { File.Delete(torLog); } catch { }
            var torrc = System.IO.Path.Combine(runDir, "torrc");

            var rc = new StringBuilder();
            rc.AppendLine("DataDirectory " + Q(dataDir));
            rc.AppendLine("SocksPort 127.0.0.1:" + port);            // loopback only
            rc.AppendLine("ControlPort 127.0.0.1:" + ctlPort);        // loopback only
            rc.AppendLine("CookieAuthentication 1");
            rc.AppendLine("CookieAuthFile " + Q(cookie));
            rc.AppendLine("ClientOnly 1");
            rc.AppendLine("AvoidDiskWrites 1");
            rc.AppendLine("SafeLogging 1");
            rc.AppendLine("Log notice stdout");                       // read by Veil and shown in error messages
            rc.AppendLine("__OwningControllerProcess " + Environment.ProcessId);   // Tor exits by itself if Veil dies
            var torDir = System.IO.Path.GetDirectoryName(exe);
            // geoip data is optional for a client; use it if the bundle ships it (somewhere below the "tor" folder).
            if (foundRoot != null)
            {
                foreach (var geo in new[] { "geoip", "geoip6" })
                {
                    var f = Directory.EnumerateFiles(foundRoot, geo, SearchOption.AllDirectories).FirstOrDefault();
                    if (f != null) rc.AppendLine((geo == "geoip" ? "GeoIPFile " : "GeoIPv6File ") + Q(f));
                }
            }
            File.WriteAllText(torrc, rc.ToString());

            while (torOut.TryDequeue(out _)) { }
            var psi = new ProcessStartInfo(exe)
            {
                UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = torDir,
                RedirectStandardOutput = true, RedirectStandardError = true,
            };
            psi.ArgumentList.Add("-f");
            psi.ArgumentList.Add(torrc);
            var p = Process.Start(psi) ?? throw new IOException("Could not start tor.exe.");
            p.EnableRaisingEvents = true;
            p.Exited += (s, e) => Log("tor.exe exited with code " + SafeExit(p));
            p.OutputDataReceived += (s, e) => Pump(e.Data);
            p.ErrorDataReceived += (s, e) => Pump(e.Data);
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            proc = p;
            Log("tor.exe started, pid " + p.Id + ", socks " + port);

            ctl?.Dispose();
            ctl = await TorControl.ConnectAsync(ctlPort, cookie, () => p.HasExited, ct);

            // 1. wait for bootstrap = 100%
            var deadline = DateTime.UtcNow.AddSeconds(120);
            while (true)
            {
                ct.ThrowIfCancellationRequested();
                if (p.HasExited) throw new IOException("Tor stopped while connecting (see " + torLog + ").");
                var phase = await ctl.GetInfoAsync("status/bootstrap-phase", ct);
                var m = Regex.Match(phase, @"PROGRESS=(\d+)");
                int pct = m.Success ? int.Parse(m.Groups[1].Value) : 0;
                var sm = Regex.Match(phase, "SUMMARY=\"([^\"]*)\"");
                Set(TorState.Starting, pct, "Connecting to the Tor network… " + pct + "%" + (sm.Success ? " (" + sm.Groups[1].Value + ")" : ""));
                if (pct >= 100) break;
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Tor did not finish connecting within two minutes. Your network may be blocking Tor.");
                await Task.Delay(500, ct);
            }

            // 2. a circuit must actually exist
            for (int i = 0; ; i++)
            {
                ct.ThrowIfCancellationRequested();
                if ((await ctl.GetInfoAsync("status/circuit-established", ct)).Trim() == "1") break;
                if (i > 60) throw new TimeoutException("Tor could not build a circuit.");
                await Task.Delay(500, ct);
            }

            // 3. independent end-to-end check through the SOCKS port
            Set(TorState.Starting, 100, "Verifying the Tor connection…");
            var (isTor, _) = await VerifyAsync(port, ct);
            if (!isTor) throw new IOException("check.torproject.org says traffic through Tor's SOCKS port is NOT using Tor. Refusing to continue.");

            Set(TorState.Connected, 100, "Connected to Tor");
            StartMonitor();
        }
        catch (OperationCanceledException)
        {
            KillProcess();
            Set(TorState.Stopped, 0, "");
            throw;
        }
        catch (Exception ex)
        {
            var why = Why(ex);
            Log("start failed: " + why);
            KillProcess();
            Set(TorState.Failed, 0, why);
            throw new IOException(why, ex);
        }
    }

    static string SafeExit(Process p) { try { return p.ExitCode.ToString(); } catch { return "?"; } }

    void KillProcess()
    {
        try { ctl?.Dispose(); } catch { }
        ctl = null;
        var p = proc;
        proc = null;
        if (p == null) return;
        stopping = true;
        try { if (!p.HasExited) p.Kill(true); } catch { }
        try { p.WaitForExit(2000); } catch { }
        try { p.Dispose(); } catch { }
    }

    async Task StopLockedAsync()
    {
        stopping = true;
        try { monitorCts?.Cancel(); } catch { }
        try { if (ctl != null) await ctl.SendAsync("SIGNAL HALT"); } catch { }
        try { if (proc != null) await Task.Run(() => proc.WaitForExit(1500)); } catch { }
        KillProcess();
        lock (sync) { socksPort = 0; }
        Set(TorState.Stopped, 0, "");
    }

    // ---------- verification ----------

    /// Asks the Tor Project's own check service, through the given SOCKS port, whether the request arrived via Tor.
    /// .NET's SOCKS5 support sends the host name to the proxy (no local DNS lookup).
    public static async Task<(bool isTor, string ip)> VerifyAsync(int port, CancellationToken ct)
    {
        Exception last = null;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                using var handler = new SocketsHttpHandler
                {
                    Proxy = new WebProxy(new Uri("socks5://127.0.0.1:" + port)),
                    UseProxy = true, UseCookies = false, AllowAutoRedirect = false,
                    ConnectTimeout = TimeSpan.FromSeconds(30),
                };
                using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(45) };
                var json = await http.GetStringAsync(CheckApi, ct);
                using var doc = JsonDocument.Parse(json);
                bool isTor = doc.RootElement.TryGetProperty("IsTor", out var t) && t.ValueKind == JsonValueKind.True;
                string ip = doc.RootElement.TryGetProperty("IP", out var i) ? i.GetString() : "";
                return (isTor, ip);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex) { last = ex; await Task.Delay(1500, ct); }
        }
        throw new IOException("Could not reach check.torproject.org through Tor: " + last?.Message);
    }

    // ---------- monitoring / recovery ----------

    void StartMonitor()
    {
        try { monitorCts?.Cancel(); } catch { }
        var cts = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        monitorCts = cts;
        _ = Task.Run(() => MonitorAsync(cts.Token));
    }

    async Task MonitorAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try { await Task.Delay(3000, ct); } catch { return; }
            try
            {
                if (proc == null || proc.HasExited) throw new IOException("The Tor process stopped.");
                bool up = (await ctl.GetInfoAsync("status/circuit-established", ct)).Trim() == "1";
                var s = State;
                if (!up)
                {
                    if (s == TorState.Connected) Set(TorState.Disconnected, 0, "Tor lost its connection to the network. Browsing is blocked until it comes back.");
                    continue;
                }
                if (s == TorState.Disconnected)
                {
                    // Network is back: do not unblock until the end-to-end check passes again.
                    var (isTor, _) = await VerifyAsync(SocksPort, ct);
                    if (isTor) Set(TorState.Connected, 100, "Connected to Tor");
                }
            }
            catch (OperationCanceledException) { return; }
            catch (Exception ex)
            {
                if (stopping || ct.IsCancellationRequested) return;
                Log("monitor: " + ex.Message);
                Set(TorState.Disconnected, 0, "Tor stopped unexpectedly. Browsing is blocked while Veil restarts it…");
                await RecoverAsync();
                return;                       // a successful restart starts a fresh monitor
            }
        }
    }

    async Task RecoverAsync()
    {
        int[] delays = { 1000, 4000, 10000 };
        foreach (var d in delays)
        {
            try { await Task.Delay(d, lifetime.Token); } catch { return; }
            bool wanted; lock (sync) wanted = leases > 0;
            if (!wanted || stopping && State == TorState.Stopped) return;
            await gate.WaitAsync();
            try
            {
                lock (sync) wanted = leases > 0;
                if (!wanted) return;
                await StartLockedAsync(lifetime.Token);
                return;
            }
            catch (OperationCanceledException) { return; }
            catch { /* StartLockedAsync already set Failed; try again after the next delay */ }
            finally { gate.Release(); }
        }
        // still failing after three tries: stay in Failed until the user presses Retry
        if (State != TorState.Stopped) Set(TorState.Failed, 0, "Tor could not be restarted. Browsing stays blocked. " + Detail);
    }
}
