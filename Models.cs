namespace Veil.Core;

public class HistoryEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Url { get; set; } = "";
    public string Title { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.UtcNow;
}

public class Bookmark
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Url { get; set; } = "";
    public string Title { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.UtcNow;
}

public class DownloadRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Source { get; set; } = "";
    public string Path { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.UtcNow;
    public string State { get; set; } = "running";   // running | done | failed
}

public class SavedTab
{
    public string Url { get; set; } = "";
    public string Title { get; set; } = "";
}

public class SessionState
{
    public List<SavedTab> Tabs { get; set; } = new();
    public int Active { get; set; }
}

public class WindowBounds
{
    public double Left { get; set; } = double.NaN;
    public double Top { get; set; } = double.NaN;
    public double Width { get; set; } = 1280;
    public double Height { get; set; } = 800;
    public bool Maximized { get; set; }
}

public class BlockerMeta
{
    public int NetworkRules { get; set; }
    public int CosmeticRules { get; set; }
    public int SkippedRules { get; set; }
    public int FailedChunks { get; set; }
    public Dictionary<string, DateTime> Updated { get; set; } = new();
}

public static class Util
{
    public static long Epoch(DateTime d) => (long)(d.ToUniversalTime() - DateTime.UnixEpoch).TotalSeconds;
}
