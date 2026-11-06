using System.Diagnostics;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Veil.Core;

namespace Veil;

public sealed class DownloadManager
{
    readonly JsonStore<List<DownloadRecord>> records = new("downloads", () => new());
    readonly Dictionary<Guid, CoreWebView2DownloadOperation> live = new();
    public event Action Changed;
    public event Action Started;
    public bool HasActive => live.Count > 0;
    public void Flush() => records.Flush();

    public string Directory_()
    {
        var custom = Services.Settings.Str("downloadFolder");
        if (!string.IsNullOrEmpty(custom) && Directory.Exists(custom)) return custom;
        var d = Paths.DefaultDownloads;
        Directory.CreateDirectory(d);
        return d;
    }

    public static string UniquePath(string dir, string name)
    {
        foreach (var c in System.IO.Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        if (name.Length == 0) name = "download";
        var path = System.IO.Path.Combine(dir, name);
        var stem = System.IO.Path.GetFileNameWithoutExtension(name);
        var ext = System.IO.Path.GetExtension(name);
        for (int i = 1; File.Exists(path); i++) path = System.IO.Path.Combine(dir, $"{stem} ({i}){ext}");
        return path;
    }

    /// Called from CoreWebView2.DownloadStarting.
    public void Attach(CoreWebView2DownloadStartingEventArgs e)
    {
        var op = e.DownloadOperation;
        string suggested = System.IO.Path.GetFileName(e.ResultFilePath);
        string path;
        if (Services.Settings.Bool("askDownloadLocation"))
        {
            var dlg = new Microsoft.Win32.SaveFileDialog { FileName = suggested, InitialDirectory = Directory_() };
            if (dlg.ShowDialog() != true) { e.Cancel = true; return; }
            path = dlg.FileName;
        }
        else path = UniquePath(Directory_(), suggested);

        e.ResultFilePath = path;
        e.Handled = true;      // hide WebView2's own download flyout; Veil shows its Downloads page instead
        var rec = new DownloadRecord { Name = System.IO.Path.GetFileName(path), Source = op.Uri ?? "", Path = path, State = "running" };
        live[rec.Id] = op;
        records.Mutate(l => l.Insert(0, rec));
        op.StateChanged += (s, a) =>
        {
            if (op.State == CoreWebView2DownloadState.InProgress) return;
            live.Remove(rec.Id);
            bool ok = op.State == CoreWebView2DownloadState.Completed;
            records.Mutate(l => { var r = l.FirstOrDefault(x => x.Id == rec.Id); if (r != null) r.State = ok ? "done" : "failed"; });
            if (ok && Services.Settings.Bool("downloadSound")) System.Media.SystemSounds.Asterisk.Play();
            Changed?.Invoke();
        };
        Changed?.Invoke();
        Started?.Invoke();
    }

    public JsonArray List()
    {
        var arr = new JsonArray();
        foreach (var r in records.Value.ToList())
        {
            var o = new JsonObject
            {
                ["id"] = r.Id.ToString(), ["name"] = r.Name, ["source"] = r.Source,
                ["state"] = r.State, ["date"] = Util.Epoch(r.Date), ["path"] = r.Path,
            };
            if (r.State == "running" && live.TryGetValue(r.Id, out var op))
            {
                double total = Convert.ToDouble((object)op.TotalBytesToReceive);
                o["progress"] = total > 0 ? Convert.ToDouble((object)op.BytesReceived) / total : 0.0;
            }
            arr.Add(o);
        }
        return arr;
    }

    DownloadRecord Find(string id) => records.Value.FirstOrDefault(r => r.Id.ToString() == id);

    public void Reveal(string id)
    {
        var r = Find(id);
        if (r == null || string.IsNullOrEmpty(r.Path) || !File.Exists(r.Path)) return;
        Process.Start("explorer.exe", "/select,\"" + r.Path + "\"");
    }
    public void Open(string id)
    {
        var r = Find(id);
        if (r == null || r.State != "done" || !File.Exists(r.Path)) return;
        Process.Start(new ProcessStartInfo(r.Path) { UseShellExecute = true });
    }
    public void ClearFinished() => records.Mutate(l => l.RemoveAll(r => r.State != "running"));

    /// Saves bytes we already have (for example an image embedded as a data: URL).
    public void SaveData(byte[] data, string suggestedName)
    {
        var dest = UniquePath(Directory_(), suggestedName);
        try { File.WriteAllBytes(dest, data); } catch { return; }
        records.Mutate(l => l.Insert(0, new DownloadRecord { Name = System.IO.Path.GetFileName(dest), Source = "Embedded in page", Path = dest, State = "done" }));
        Changed?.Invoke();
        Started?.Invoke();
    }
}
