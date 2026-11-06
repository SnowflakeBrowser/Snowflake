namespace Veil.Core;

public sealed record FilterListSource(string Id, string Name, string Blurb, string Url, bool DefaultOn);

public sealed class Blocker
{
    public static readonly FilterListSource[] Sources =
    {
        new("builtin", "Veil essentials", "Built-in ad and tracker domains. Works offline.", null, true),
        new("easylist", "EasyList", "Ads on most websites.", "https://easylist.to/easylist/easylist.txt", true),
        new("easyprivacy", "EasyPrivacy", "Trackers and analytics.", "https://easylist.to/easylist/easyprivacy.txt", true),
        new("ubo-filters", "uBlock Origin filters", "uBlock Origin's own ad rules (network and element-hiding parts).", "https://ublockorigin.github.io/uAssets/filters/filters.txt", true),
        new("ubo-privacy", "uBlock Origin privacy", "uBlock Origin's tracker rules.", "https://ublockorigin.github.io/uAssets/filters/privacy.txt", true),
        new("ubo-badware", "uBlock Origin badware", "Malicious and scam domains.", "https://ublockorigin.github.io/uAssets/filters/badware.txt", true),
        new("annoyances", "Cookie banners and annoyances", "Hides cookie banners, popups and newsletter nags. May hide parts of some pages.", "https://easylist.to/easylist/fanboy-annoyance.txt", true),
    };

    public readonly JsonStore<BlockerMeta> Meta = new("blocker-meta", () => new());
    volatile FilterEngine engine;
    TaskCompletionSource ready = new();
    public Task Ready => ready.Task;
    public FilterEngine Engine => engine;
    public int Generation { get; private set; }

    static string File_(string id) => System.IO.Path.Combine(Paths.ListsDir, id + ".txt");
    public bool IsEnabled(FilterListSource s) => Services.Settings.ListEnabled(s.Id, s.DefaultOn);

    const string Seed = @"
||doubleclick.net^
||googlesyndication.com^
||googleadservices.com^
||adservice.google.com^
||google-analytics.com^
||analytics.google.com^
||amazon-adsystem.com^
||adnxs.com^
||criteo.com^
||criteo.net^
||taboola.com^
||outbrain.com^
||pubmatic.com^
||rubiconproject.com^
||openx.net^
||scorecardresearch.com^
||quantserve.com^
||hotjar.com^
||mixpanel.com^$third-party
||connect.facebook.net/*/fbevents.js
||facebook.com/tr^
||ads.twitter.com^
||analytics.twitter.com^
||ads.linkedin.com^
||analytics.tiktok.com^
||bat.bing.com^
||adsrvr.org^
||moatads.com^
||zedo.com^
||popads.net^
||popcash.net^
||propellerads.com^
||exoclick.com^
||trafficjunky.net^
##.adsbygoogle
##ins.adsbygoogle
##[id^=""google_ads_iframe""]
";

    /// Parses all enabled lists on a background thread. Tabs wait on Ready so the first load is never unblocked.
    public Task RebuildAsync()
    {
        var wantLists = Sources.Where(IsEnabled).Select(s => s.Id).ToList();
        var custom = Services.Settings.Str("customRules");
        return Task.Run(() =>
        {
            var e = new FilterEngine();
            foreach (var id in wantLists)
            {
                if (id == "builtin") e.AddList(Seed);
                else if (File.Exists(File_(id))) { try { e.AddList(File.ReadAllText(File_(id))); } catch { } }
            }
            e.AddList(custom ?? "");
            engine = e;
            Meta.Mutate(m => { m.NetworkRules = e.NetworkRules; m.CosmeticRules = e.CosmeticRules; m.SkippedRules = e.Skipped; });
            Generation++;
            ready.TrySetResult();
        }).ContinueWith(_ => Services.Notify(), TaskScheduler.FromCurrentSynchronizationContext());
    }

    public async Task<(List<string> updated, List<string> failed)> DownloadListsAsync()
    {
        var updated = new List<string>(); var failed = new List<string>();
        using var http = new HttpClient(new HttpClientHandler { UseCookies = false }) { Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Veil/0.1");
        foreach (var s in Sources.Where(x => x.Url != null && IsEnabled(x)))
        {
            try
            {
                var text = await http.GetStringAsync(s.Url);
                if (text.Length < 200) throw new Exception("too short");
                await File.WriteAllTextAsync(File_(s.Id), text);
                Meta.Mutate(m => m.Updated[s.Id] = DateTime.UtcNow);
                updated.Add(s.Name);
            }
            catch { failed.Add(s.Name); }
        }
        await RebuildAsync();
        return (updated, failed);
    }

    public void MaybeAutoUpdate()
    {
        if (!Services.Settings.Bool("autoUpdateLists")) return;
        var u = Meta.Value.Updated;
        var oldest = u.Count == 0 ? DateTime.MinValue : u.Values.Min();
        if ((DateTime.UtcNow - oldest).TotalDays > 7) _ = DownloadListsAsync();
    }

    /// Called for each sub-resource request.
    public bool ShouldBlock(string url, string pageHost, RT type)
    {
        var e = engine;
        if (e == null || !Services.Settings.Bool("adBlocking")) return false;
        if (Services.Allowlist.Contains(pageHost)) return false;
        return e.ShouldBlock(url, pageHost, type);
    }
}
