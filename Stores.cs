namespace Veil.Core;

public sealed class HistoryStore
{
    readonly JsonStore<List<HistoryEntry>> store = new("history", () => new());
    public int Count => store.Value.Count;

    public void Add(string url, string title)
    {
        store.Mutate(list =>
        {
            if (list.Count > 0 && list[^1].Url == url)
            {
                if (!string.IsNullOrEmpty(title)) list[^1].Title = title;
                list[^1].Date = DateTime.UtcNow;
                return;
            }
            list.Add(new HistoryEntry { Url = url, Title = string.IsNullOrEmpty(title) ? url : title });
            if (list.Count > 20000) list.RemoveRange(0, list.Count - 20000);
        });
    }

    public List<HistoryEntry> Search(string q, int limit = 500)
    {
        q = (q ?? "").ToLowerInvariant();
        var all = store.Value;
        var outp = new List<HistoryEntry>();
        for (int i = all.Count - 1; i >= 0 && outp.Count < limit; i--)
        {
            var e = all[i];
            if (q.Length == 0 || e.Title.ToLowerInvariant().Contains(q) || e.Url.ToLowerInvariant().Contains(q)) outp.Add(e);
        }
        return outp;
    }
    public void Remove(Guid id) => store.Mutate(l => l.RemoveAll(e => e.Id == id));
    public void Clear() => store.Mutate(l => l.Clear());
    public void Flush() => store.Flush();
}

public sealed class BookmarkStore
{
    readonly JsonStore<List<Bookmark>> store = new("bookmarks", () => new());
    public List<Bookmark> All => store.Value.ToList();
    public bool Contains(string url) => store.Value.Any(b => b.Url == url);
    public void Add(string url, string title)
    {
        if (Contains(url)) return;
        store.Mutate(l => l.Insert(0, new Bookmark { Url = url, Title = string.IsNullOrEmpty(title) ? url : title }));
    }
    public void Remove(string url) => store.Mutate(l => l.RemoveAll(b => b.Url == url));
    public void Flush() => store.Flush();
}

/// Sites where blocking is off. Matches the host and all of its subdomains.
public sealed class AllowlistStore
{
    readonly JsonStore<List<string>> store = new("allowlist", () => new());
    public List<string> All => store.Value.OrderBy(x => x).ToList();
    public static string Normalize(string host)
    {
        var h = (host ?? "").ToLowerInvariant().Trim();
        return h.StartsWith("www.") ? h.Substring(4) : h;
    }
    public bool Contains(string host)
    {
        var h = Normalize(host);
        if (h.Length == 0) return false;
        return store.Value.Any(x => h == x || h.EndsWith("." + x));
    }
    public void Add(string host)
    {
        var h = Normalize(host);
        if (h.Length == 0) return;
        store.Mutate(l => { if (!l.Contains(h)) l.Add(h); });
    }
    public void Remove(string host) { var h = Normalize(host); store.Mutate(l => l.RemoveAll(x => x == h)); }
    public void Flush() => store.Flush();
}

/// Remembered camera / microphone decisions per site.
public sealed class PermissionStore
{
    readonly JsonStore<Dictionary<string, Dictionary<string, bool>>> store = new("permissions", () => new());
    public Dictionary<string, Dictionary<string, bool>> All => store.Value;
    public bool? Get(string host, string kind) =>
        store.Value.TryGetValue(host, out var k) && k.TryGetValue(kind, out var b) ? b : null;
    public void Set(string host, string kind, bool allowed) =>
        store.Mutate(d => { if (!d.TryGetValue(host, out var k)) d[host] = k = new(); k[kind] = allowed; });
    public void Remove(string host, string kind) =>
        store.Mutate(d => { if (d.TryGetValue(host, out var k)) { k.Remove(kind); if (k.Count == 0) d.Remove(host); } });
    public void Flush() => store.Flush();
}
