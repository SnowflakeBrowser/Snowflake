namespace Veil.Core;

/// Address-bar helpers: popular sites and the suggestion list shown while typing (same logic as the Mac version).
public static class Autocomplete
{
    public static readonly string[] PopularHosts =
    {
        "youtube.com", "google.com", "github.com", "reddit.com", "wikipedia.org", "amazon.com", "netflix.com", "twitch.tv",
        "twitter.com", "x.com", "facebook.com", "instagram.com", "linkedin.com", "whatsapp.com", "discord.com", "spotify.com",
        "stackoverflow.com", "microsoft.com", "apple.com", "duckduckgo.com", "bing.com", "yahoo.com", "ebay.com", "imdb.com",
        "pinterest.com", "tiktok.com", "paypal.com", "openai.com", "claude.ai", "chatgpt.com", "gmail.com", "outlook.com",
        "drive.google.com", "maps.google.com", "translate.google.com", "docs.google.com", "news.ycombinator.com", "medium.com",
        "bbc.com", "cnn.com", "nytimes.com", "theguardian.com", "steampowered.com", "roblox.com", "epicgames.com", "wikihow.com",
        "dropbox.com", "notion.so", "figma.com", "canva.com", "zoom.us", "slack.com", "adobe.com", "cloudflare.com",
    };

    public static string BareHost(string host)
    {
        var h = (host ?? "").ToLowerInvariant();
        return h.StartsWith("www.") ? h.Substring(4) : h;
    }
}

public enum SuggestionKind { Search, Site, Bookmark, History }

public sealed class Suggestion
{
    public SuggestionKind Kind;
    public string Title = "", Detail = "", Target = "";
}

public static class Suggestions
{
    static string Key(string url)
    {
        var k = (url ?? "").ToLowerInvariant();
        foreach (var p in new[] { "https://", "http://" })
            if (k.StartsWith(p)) { k = k.Substring(p.Length); break; }
        if (k.StartsWith("www.")) k = k.Substring(4);
        return k.TrimEnd('/');
    }

    public static List<Suggestion> Build(string query, List<HistoryEntry> history, List<Bookmark> bookmarks, IList<string> hosts, bool includePopular = true, int limit = 8)
    {
        var result = new List<Suggestion>();
        var q = (query ?? "").Trim();
        if (q.Length == 0 || limit <= 1) return result;
        var lower = q.ToLowerInvariant();
        var seen = new HashSet<string>();

        // 1. What pressing Return would do.
        bool isAddress = UrlResolver.IsExplicitUrl(q) || UrlResolver.LooksLikeHost(q);
        if (isAddress)
        {
            var u = UrlResolver.Resolve(q, "https://search.invalid/?q=%s");
            result.Add(new Suggestion { Kind = SuggestionKind.Site, Title = q, Detail = "Open", Target = u });
            seen.Add(Key(u));
        }
        else result.Add(new Suggestion { Kind = SuggestionKind.Search, Title = q, Detail = "Search", Target = q });

        // 2. Bookmarks that match.
        int n = 0;
        foreach (var b in bookmarks)
        {
            if (n >= 2) break;
            if (!((b.Title ?? "").ToLowerInvariant().Contains(lower) || (b.Url ?? "").ToLowerInvariant().Contains(lower))) continue;
            if (seen.Add(Key(b.Url)))
            {
                result.Add(new Suggestion { Kind = SuggestionKind.Bookmark, Title = b.Title, Detail = UrlResolver.Display(b.Url), Target = b.Url });
                n++;
            }
        }

        // 3. Sites you visit often (and well-known ones).
        var prefix = lower.StartsWith("www.") ? lower.Substring(4) : lower;
        n = 0;
        if (!prefix.Contains(' '))
        {
            IEnumerable<string> pool = includePopular ? hosts.Concat(Autocomplete.PopularHosts) : hosts;
            foreach (var host in pool)
            {
                if (n >= 3) break;
                if (!host.StartsWith(prefix, StringComparison.Ordinal)) continue;
                var url = "https://" + host;
                if (seen.Add(Key(url)))
                {
                    result.Add(new Suggestion { Kind = SuggestionKind.Site, Title = host, Detail = "", Target = url });
                    n++;
                }
            }
        }

        // 4. Pages from history.
        n = 0;
        foreach (var e in history)
        {
            if (n >= 3 || result.Count >= limit - 1) break;
            if (seen.Add(Key(e.Url)))
            {
                result.Add(new Suggestion { Kind = SuggestionKind.History, Title = string.IsNullOrEmpty(e.Title) ? e.Url : e.Title, Detail = UrlResolver.Display(e.Url), Target = e.Url });
                n++;
            }
        }

        // 5. Always end with "search for ...".
        if (result[0].Kind != SuggestionKind.Search)
        {
            result = result.Take(limit - 1).ToList();
            result.Add(new Suggestion { Kind = SuggestionKind.Search, Title = q, Detail = "Search", Target = q });
        }
        return result.Take(limit).ToList();
    }
}
