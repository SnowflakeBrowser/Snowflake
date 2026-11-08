using System.Text;
using System.Text.RegularExpressions;

namespace Veil.Core;

[Flags]
public enum RT : uint { None = 0, Script = 1, Image = 2, Style = 4, Xhr = 8, Media = 16, Font = 32, Doc = 64, Other = 128 }

sealed class Rule
{
    public string Pattern;
    public bool MatchCase;
    public sbyte Party;                 // 0 any, 1 third-party only, 2 first-party only
    public RT Types;                    // None = any (except documents)
    public string[] IfDomains, UnlessDomains;
    Regex rx; bool broken;
    int plain = -1;                     // -1 unknown, 1 = plain text (substring check), 0 = needs a regex

    public bool Matches(string url, string pageHost, string reqHost, RT type)
    {
        if (Types != RT.None && (Types & type) == 0) return false;
        if (Types == RT.None && type == RT.Doc) return false;
        if (Party != 0)
        {
            bool third = FilterEngine.IsThirdParty(pageHost, reqHost);
            if ((Party == 1) != third) return false;
        }
        if (IfDomains != null && !IfDomains.Any(d => FilterEngine.HostIn(pageHost, d))) return false;
        if (UnlessDomains != null && UnlessDomains.Any(d => FilterEngine.HostIn(pageHost, d))) return false;
        if (broken) return false;
        if (plain < 0) plain = Pattern.IndexOfAny(new[] { '*', '^', '|' }) < 0 ? 1 : 0;
        if (plain == 1) return url.IndexOf(Pattern, MatchCase ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase) >= 0;   // much faster than a regex
        if (rx == null)
        {
            try
            {
                rx = new Regex(FilterEngine.ToRegex(Pattern), RegexOptions.CultureInvariant | (MatchCase ? RegexOptions.None : RegexOptions.IgnoreCase),
                               TimeSpan.FromMilliseconds(30));
            }
            catch { broken = true; return false; }
        }
        try { return rx.IsMatch(url); } catch (RegexMatchTimeoutException) { return false; }
    }
}

sealed class RuleSet
{
    public readonly Dictionary<string, List<Rule>> Hosts = new();
    public readonly Dictionary<string, List<Rule>> Tokens = new();
    public readonly List<Rule> Generic = new();
    public int Count;

    public void Add(Rule r, string hostKey, string token)
    {
        Count++;
        var d = hostKey != null ? Hosts : token != null ? Tokens : null;
        var key = hostKey ?? token;
        if (d == null) { Generic.Add(r); return; }
        if (!d.TryGetValue(key, out var l)) d[key] = l = new List<Rule>();
        l.Add(r);
    }

    public bool Match(string url, string urlLower, string pageHost, string reqHost, RT type, List<string> toks)
    {
        // host-anchored rules: ||example.com^
        var h = reqHost;
        while (h.Length > 0)
        {
            if (Hosts.TryGetValue(h, out var hl))
                foreach (var r in hl) if (r.Matches(url, pageHost, reqHost, type)) return true;
            int dot = h.IndexOf('.');
            if (dot < 0) break;
            h = h.Substring(dot + 1);
        }
        foreach (var t in toks)
            if (Tokens.TryGetValue(t, out var l))
                foreach (var r in l) if (r.Matches(url, pageHost, reqHost, type)) return true;
        foreach (var r in Generic) if (r.Matches(url, pageHost, reqHost, type)) return true;
        return false;
    }
}

/// Adblock-Plus-syntax filter engine (EasyList, EasyPrivacy, uBlock Origin lists).
/// Supported: ||host^, |anchors, wildcards, @@ exceptions, $third-party, $script/image/stylesheet/xhr/media/font,
/// $domain=, and ##selector element hiding. Skipped (counted): regex filters, $redirect, $removeparam, scriptlets,
/// procedural cosmetics, #@# exceptions.
public sealed class FilterEngine
{
    readonly RuleSet block = new(), allow = new();
    readonly List<string> genericCss = new();
    readonly Dictionary<string, List<string>> domainCss = new();
    readonly HashSet<string> seen = new();
    public int NetworkRules => block.Count + allow.Count;
    public int CosmeticRules { get; private set; }
    public int Skipped { get; private set; }
    const int MaxGenericSelectors = 12000;

    // ---------- parsing ----------
    public void AddList(string text)
    {
        using var rd = new StringReader(text);
        string raw;
        while ((raw = rd.ReadLine()) != null)
        {
            var line = raw.Trim();
            if (line.Length == 0 || line[0] == '!' || line[0] == '[') continue;
            try { Parse(line); } catch { Skipped++; }
        }
    }

    static readonly string[] BadCosmeticMarkers = { "#@#", "#?#", "#$#", "#%#", "#@$#", "#@?#" };
    static readonly string[] BadSelectorTokens =
    {
        ":has-text(", ":xpath(", ":matches-css", ":-abp-", ":min-text-length", ":nth-ancestor", ":upward(", ":watch-attr",
        ":others(", ":remove(", ":style(", ":contains(", ":matches-path", ":matches-media", "+js(", "::", "{", "}",
    };

    void Parse(string line)
    {
        foreach (var m in BadCosmeticMarkers) if (line.Contains(m)) { Skipped++; return; }
        int idx = line.IndexOf("##", StringComparison.Ordinal);
        if (idx >= 0)
        {
            var domPart = line.Substring(0, idx);
            var sel = line.Substring(idx + 2);
            if (sel.Length == 0 || sel[0] == '+' || sel[0] == '^' || BadSelectorTokens.Any(sel.Contains)) { Skipped++; return; }
            var doms = domPart.Length == 0 ? new string[0] : domPart.Split(',');
            if (doms.Any(d => d.StartsWith("~") || d.Contains('*') || d.Contains('/'))) { Skipped++; return; }
            if (doms.Length == 0)
            {
                if (seen.Add("##" + sel) && genericCss.Count < MaxGenericSelectors) { genericCss.Add(sel); CosmeticRules++; }
            }
            else foreach (var d0 in doms)
            {
                var d = d0.ToLowerInvariant();
                if (!seen.Add(d + "##" + sel)) continue;
                if (!domainCss.TryGetValue(d, out var l)) domainCss[d] = l = new List<string>();
                l.Add(sel); CosmeticRules++;
            }
            return;
        }
        ParseNetwork(line);
    }

    static readonly Dictionary<string, RT> TypeMap = new()
    {
        ["script"] = RT.Script, ["image"] = RT.Image, ["stylesheet"] = RT.Style, ["css"] = RT.Style,
        ["xmlhttprequest"] = RT.Xhr, ["xhr"] = RT.Xhr, ["media"] = RT.Media, ["font"] = RT.Font,
        ["ping"] = RT.Other, ["websocket"] = RT.Other, ["other"] = RT.Other,
    };

    void ParseNetwork(string line)
    {
        var pattern = line;
        bool isAllow = false;
        if (pattern.StartsWith("@@")) { isAllow = true; pattern = pattern.Substring(2); }
        string[] options = new string[0];
        int d = pattern.LastIndexOf('$');
        if (d >= 0)
        {
            var tail = pattern.Substring(d + 1);
            if (tail.Length > 0 && !tail.Contains('/')) { options = tail.Split(','); pattern = pattern.Substring(0, d); }
        }
        if (pattern.Length == 0 || (pattern.Length > 2 && pattern.StartsWith("/") && pattern.EndsWith("/"))) { Skipped++; return; }
        if (pattern.Any(c => c > 127)) { Skipped++; return; }

        var r = new Rule { Pattern = pattern };
        RT types = RT.None;
        List<string> ifd = new(), unless = new();
        foreach (var opt in options)
        {
            var name = opt.ToLowerInvariant();
            bool neg = name.StartsWith("~");
            if (neg) name = name.Substring(1);
            if (name.StartsWith("domain="))
            {
                foreach (var dom in name.Substring(7).Split('|'))
                {
                    if (dom.Contains('*') || dom.Contains('/')) { Skipped++; return; }
                    if (dom.StartsWith("~")) unless.Add(dom.Substring(1)); else ifd.Add(dom);
                }
                continue;
            }
            switch (name)
            {
                case "third-party": case "3p": r.Party = (sbyte)(neg ? 2 : 1); break;
                case "first-party": case "1p": r.Party = (sbyte)(neg ? 1 : 2); break;
                case "important": case "all": break;
                case "match-case": r.MatchCase = true; break;
                default:
                    if (neg || !TypeMap.TryGetValue(name, out var t)) { Skipped++; return; }
                    types |= t; break;
            }
        }
        if (ifd.Count > 0 && unless.Count > 0) { Skipped++; return; }
        r.Types = types;
        if (ifd.Count > 0) r.IfDomains = ifd.ToArray();
        if (unless.Count > 0) r.UnlessDomains = unless.ToArray();

        var key = (isAllow ? "@@" : "") + line;
        if (!seen.Add(key)) return;
        var set = isAllow ? allow : block;
        string hostKey = PlainHost(pattern);
        set.Add(r, hostKey, hostKey == null ? PickToken(pattern) : null);
    }

    /// "||example.com^" (nothing else) -> "example.com", else null.
    static string PlainHost(string p)
    {
        if (!p.StartsWith("||")) return null;
        var h = p.Substring(2);
        if (h.EndsWith("^")) h = h.Substring(0, h.Length - 1);
        if (h.Length < 3 || !h.Contains('.')) return null;
        foreach (var c in h) if (!(char.IsAsciiLetterOrDigit(c) || c == '.' || c == '-')) return null;
        return h.ToLowerInvariant();
    }

    static bool IsTok(char c) => char.IsAsciiLetterOrDigit(c);

    static string PickToken(string p)
    {
        string best = null;
        int n = p.Length, i = 0;
        while (i < n)
        {
            if (!IsTok(p[i])) { i++; continue; }
            int s = i;
            while (i < n && IsTok(p[i])) i++;
            int e = i;
            bool leftOk = s > 0 && p[s - 1] != '*';
            bool rightOk = e < n && p[e] != '*';
            if (leftOk && rightOk && e - s >= 3 && (best == null || e - s > best.Length))
            {
                var tok = p.Substring(s, e - s).ToLowerInvariant();
                if (tok != "http" && tok != "https" && tok != "www" && tok != "com") best = tok;   // too common to be a useful index key
            }
        }
        return best;
    }

    internal static string ToRegex(string pattern)
    {
        var p = pattern;
        string pre = "";
        if (p.StartsWith("||")) { p = p.Substring(2); pre = @"^[a-z][a-z0-9+.\-]*://([^/?#]*\.)?"; }
        else if (p.StartsWith("|")) { p = p.Substring(1); pre = "^"; }
        string suf = "";
        if (p.EndsWith("|")) { p = p.Substring(0, p.Length - 1); suf = "$"; }
        var sb = new StringBuilder(pre);
        foreach (var c in p)
        {
            if (c == '*') sb.Append(".*");
            else if (c == '^') sb.Append(@"(?:[^\w.%\-]|$)");
            else sb.Append(Regex.Escape(c.ToString()));
        }
        return sb + suf;
    }

    // ---------- matching ----------
    static readonly HashSet<string> SecondLevel = new() { "co", "com", "org", "net", "gov", "edu", "ac", "or", "ne", "go" };

    public static string RegDomain(string host)
    {
        if (string.IsNullOrEmpty(host) || UrlResolver.IsIPv4(host)) return host ?? "";
        var l = host.Split('.');
        if (l.Length <= 2) return host;
        int take = (l[^1].Length == 2 && SecondLevel.Contains(l[^2]) && l.Length >= 3) ? 3 : 2;
        return string.Join('.', l.Skip(l.Length - take));
    }
    public static bool IsThirdParty(string pageHost, string reqHost) =>
        !string.IsNullOrEmpty(pageHost) && RegDomain(pageHost) != RegDomain(reqHost);
    public static bool HostIn(string host, string domain) => host == domain || host.EndsWith("." + domain);

    public bool ShouldBlock(string url, string pageHost, RT type)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var u)) return false;
        var reqHost = u.Host.ToLowerInvariant();
        var lower = url.ToLowerInvariant();
        var toks = new List<string>();
        var set = new HashSet<string>();
        int i = 0;
        while (i < lower.Length && toks.Count < 250)
        {
            if (!IsTok(lower[i])) { i++; continue; }
            int s = i;
            while (i < lower.Length && IsTok(lower[i])) i++;
            if (i - s >= 3) { var t = lower.Substring(s, i - s); if (set.Add(t)) toks.Add(t); }
        }
        pageHost = (pageHost ?? "").ToLowerInvariant();
        if (!block.Match(url, lower, pageHost, reqHost, type, toks)) return false;
        return !allow.Match(url, lower, pageHost, reqHost, type, toks);
    }

    // ---------- cosmetic ----------
    static string Css(IEnumerable<string> sels)
    {
        var sb = new StringBuilder();
        foreach (var batch in sels.Chunk(25)) sb.Append(string.Join(",", batch)).Append("{display:none!important}\n");
        return sb.ToString();
    }
    public string GenericCss() => Css(genericCss);
    public string CssForHost(string host)
    {
        host = (host ?? "").ToLowerInvariant();
        var sels = new List<string>();
        var h = host;
        while (h.Length > 0)
        {
            if (domainCss.TryGetValue(h, out var l)) sels.AddRange(l);
            int dot = h.IndexOf('.');
            if (dot < 0) break;
            h = h.Substring(dot + 1);
        }
        return sels.Count == 0 ? "" : Css(sels);
    }
}
