using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Veil.Tor;

/// Minimal client for Tor's control protocol (https://spec.torproject.org/control-spec/).
/// Only what Veil needs: cookie authentication, GETINFO and SIGNAL. Commands are serialised.
public sealed class TorControl : IDisposable
{
    readonly TcpClient tcp = new();
    readonly SemaphoreSlim gate = new(1, 1);
    StreamReader reader;
    StreamWriter writer;

    /// Connects to 127.0.0.1:port and authenticates with the cookie file Tor writes into its data directory.
    public static async Task<TorControl> ConnectAsync(int port, string cookieFile, Func<bool> processExited, CancellationToken ct)
    {
        var deadline = DateTime.UtcNow.AddSeconds(30);
        Exception last = null;
        while (DateTime.UtcNow < deadline)
        {
            ct.ThrowIfCancellationRequested();
            if (processExited()) throw new IOException("Tor exited before it could be controlled.");
            TorControl c = null;
            try
            {
                if (!File.Exists(cookieFile)) throw new FileNotFoundException("Tor has not written its control cookie yet.");
                var cookie = File.ReadAllBytes(cookieFile);
                if (cookie.Length != 32) throw new IOException("Control cookie is incomplete.");
                c = new TorControl();
                await c.tcp.ConnectAsync(IPAddress.Loopback, port, ct);
                var ns = c.tcp.GetStream();
                c.reader = new StreamReader(ns, new UTF8Encoding(false));
                c.writer = new StreamWriter(ns, new UTF8Encoding(false)) { NewLine = "\r\n", AutoFlush = true };
                await c.SendAsync("AUTHENTICATE " + Convert.ToHexString(cookie), ct);
                return c;
            }
            catch (OperationCanceledException) { c?.Dispose(); throw; }
            catch (Exception ex)
            {
                last = ex;
                c?.Dispose();
                await Task.Delay(300, ct);
            }
        }
        throw new IOException("Could not connect to Tor's control port: " + last?.Message);
    }

    /// Sends one command and returns the reply lines (without the status codes and without the final "OK").
    /// Throws if Tor answers with an error status.
    public async Task<List<string>> SendAsync(string command, CancellationToken ct = default)
    {
        await gate.WaitAsync(ct);
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(15));
            await writer.WriteLineAsync(command);
            var lines = new List<string>();
            while (true)
            {
                var line = await reader.ReadLineAsync(cts.Token) ?? throw new IOException("Tor's control connection was closed.");
                if (line.Length < 4) continue;
                var code = line.Substring(0, 3);
                var sep = line[3];
                var body = line.Substring(4);
                if (sep == '+')
                {
                    // multi-line data reply, terminated by a line containing a single "."
                    var sb = new StringBuilder(body).Append('\n');
                    while (true)
                    {
                        var d = await reader.ReadLineAsync(cts.Token) ?? throw new IOException("Tor's control connection was closed.");
                        if (d == ".") break;
                        sb.Append(d).Append('\n');
                    }
                    lines.Add(sb.ToString());
                    continue;
                }
                if (code[0] == '6') continue;                 // asynchronous event: we never subscribe, ignore defensively
                if (sep == '-') { lines.Add(body); continue; }
                if (code != "250") throw new IOException("Tor control error " + code + ": " + body);
                return lines;                                  // "250 OK"
            }
        }
        finally { gate.Release(); }
    }

    public async Task<string> GetInfoAsync(string key, CancellationToken ct = default)
    {
        var lines = await SendAsync("GETINFO " + key, ct);
        var prefix = key + "=";
        foreach (var l in lines)
            if (l.StartsWith(prefix, StringComparison.Ordinal)) return l.Substring(prefix.Length);
        throw new IOException("Tor did not answer GETINFO " + key + ".");
    }

    public void Dispose()
    {
        try { tcp.Dispose(); } catch { }
    }
}
