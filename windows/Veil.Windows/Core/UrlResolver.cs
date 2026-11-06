using System.Text;

namespace Veil.Core;

public sealed record SearchEngine(string Id, string Name, string Template);

public static class SearchEngines
{
    public static readonly SearchEngine[] All =
    {
        new("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        new("brave", "Brave Search", "https://search.brave.com/search?q=%s"),
        new("startpage", "Startpage", "https://www.startpage.com/do/search?q=%s"),
        new("ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s"),
        new("google", "Google", "https://www.google.com/search?q=%s"),
    };
    public static string Template(string id) => (All.FirstOrDefault(e => e.Id == id) ?? All[0]).Template;
}

public static class UrlResolver
{
    public const string NewTab = "veil://newtab";

    public static string Resolve(string raw, string template)
    {
        var input = (raw ?? "").Trim();
        if (input.Length == 0) return NewTab;
        var low = input.ToLowerInvariant();
        foreach (var p in new[] { "http://", "https://", "file://", "veil://" })
            if (low.StartsWith(p)) return input;
        if (low == "about:blank") return input;
        if (LooksLikeHost(input))
        {
            var h = HostPart(input);
            return (h != null && IsLocalHost(h) ? "http://" : "https://") + input;
        }
        return template.Replace("%s", Uri.EscapeDataString(input));
    }

    static string HostPart(string s)
    {
        var host = s;
        int i = host.IndexOfAny(new[] { '/', '?', '#' });
        if (i >= 0) host = host.Substring(0, i);
        int at = host.LastIndexOf('@');
        if (at >= 0) host = host.Substring(at + 1);
        int colon = host.LastIndexOf(':');
        if (colon >= 0 && !host.EndsWith("]"))
        {
            var port = host.Substring(colon + 1);
            if (port.All(char.IsDigit)) host = host.Substring(0, colon); else return null;
        }
        return host.Length == 0 ? null : host;
    }

    static bool LooksLikeHost(string s)
    {
        if (s.Any(char.IsWhiteSpace)) return false;
        var host = HostPart(s);
        if (host == null) return false;
        if (host.ToLowerInvariant() == "localhost") return true;
        if (IsIPv4(host)) return true;
        if (!host.Contains('.') || host.StartsWith(".") || host.EndsWith(".")) return false;
        var tld = host.Split('.').Last();
        if (tld.Length < 2 || !tld.All(char.IsLetter)) return false;
        return host.All(c => char.IsLetterOrDigit(c) || c == '.' || c == '-');
    }

    public static bool IsIPv4(string host)
    {
        var parts = host.Split('.');
        return parts.Length == 4 && parts.All(p => int.TryParse(p, out var n) && n >= 0 && n <= 255);
    }

    public static bool IsLocalHost(string host)
    {
        var h = host.ToLowerInvariant();
        return h == "localhost" || h.EndsWith(".local") || h.EndsWith(".localhost") || IsIPv4(h) || h.StartsWith("[");
    }

    public static string Display(string url)
    {
        if (string.IsNullOrEmpty(url) || url == "about:blank") return "";
        if (url.StartsWith("veil://"))
        {
            var host = url.Substring(7).Split('/', '?', '#')[0];
            return host == "newtab" ? "" : "veil://" + host;
        }
        var s = url;
        foreach (var p in new[] { "https://", "http://" }) if (s.StartsWith(p)) { s = s.Substring(p.Length); break; }
        if (s.StartsWith("www.")) s = s.Substring(4);
        if (s.EndsWith("/") && s.Count(c => c == '/') == 1) s = s.Substring(0, s.Length - 1);
        return s;
    }

    public static string HostOf(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host : "";
}

/// Removes utm_*, fbclid, gclid ... from addresses.
public static class TrackingParams
{
    static readonly HashSet<string> Exact = new()
    {
        "fbclid","gclid","gclsrc","dclid","wbraid","gbraid","msclkid","yclid","twclid","ttclid","igshid",
        "mc_eid","mc_cid","_hsenc","_hsmi","mkt_tok","vero_id","oly_enc_id","oly_anon_id","ref_src","ref_url",
    };
    static readonly string[] Prefixes = { "utm_", "pk_", "mtm_", "hsa_" };

    public static bool IsTracking(string name)
    {
        var n = Uri.UnescapeDataString(name).ToLowerInvariant();
        return Exact.Contains(n) || Prefixes.Any(p => n.StartsWith(p));
    }

    /// The cleaned address, or null when nothing needed removing.
    public static string Cleaned(string url)
    {
        int q = url.IndexOf('?');
        if (q < 0) return null;
        var rest = url.Substring(q + 1);
        var frag = "";
        int h = rest.IndexOf('#');
        if (h >= 0) { frag = rest.Substring(h); rest = rest.Substring(0, h); }
        var parts = rest.Split('&', StringSplitOptions.RemoveEmptyEntries);
        var kept = parts.Where(p => !IsTracking(p.Split('=')[0])).ToArray();
        if (kept.Length == parts.Length) return null;
        return url.Substring(0, q) + (kept.Length > 0 ? "?" + string.Join("&", kept) : "") + frag;
    }
}
