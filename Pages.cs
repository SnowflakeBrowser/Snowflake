using Veil.Core;

namespace Veil;

/// veil://newtab, settings, privacy, history, bookmarks, downloads: the HTML/CSS/JS is shared with the macOS build.
public static class Pages
{
    public static readonly string[] Names = { "newtab", "settings", "privacy", "history", "bookmarks", "downloads" };
    static string css, script;
    static string Css => css ??= Res.Text("pages.css");
    static string Script => script ??= Res.Text("pages.js");

    public const string Csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; form-action 'none'";

    public static string Html(string name)
    {
        if (!Names.Contains(name)) return null;
        return $@"<!doctype html><html><head><meta charset=""utf-8"">
<meta name=""viewport"" content=""width=device-width,initial-scale=1"">
<meta name=""color-scheme"" content=""dark light""><title>Veil</title>
<style>{Css}</style></head>
<body data-page=""{name}""><div id=""app""></div><script>{Script}</script></body></html>";
    }

    public static string Escape(string s) =>
        (s ?? "").Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");

    public static string ErrorHtml(string heading, string detail, string failingUrl, string insecureUrl)
    {
        string button = insecureUrl == null ? "" :
            $"<p><a class=\"btn\" href=\"veil://insecure?u={Uri.EscapeDataString(insecureUrl)}\">Continue over http</a></p>";
        return $@"<!doctype html><html><head><meta charset=""utf-8""><meta name=""color-scheme"" content=""dark light"">
<style>{Css}</style></head><body data-page=""error""><div id=""app""><main class=""err"">
<h1>{Escape(heading)}</h1><p class=""mute"">{Escape(detail)}</p>
<p class=""mute url"">{Escape(failingUrl)}</p>{button}</main></div></body></html>";
    }
}
