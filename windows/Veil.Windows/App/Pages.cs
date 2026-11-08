using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
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
<meta http-equiv=""Content-Security-Policy"" content=""{Csp}"">
<meta name=""color-scheme"" content=""dark light""><title>Veil</title>
<style>{Css}</style></head>
<body data-page=""{name}""><div id=""app""></div><script>{Script}</script></body></html>";
    }

    // ---- Veil's start page: plain HTML drawn directly (no veil:// scheme, no bridge) ----
    const string NewTabTemplate = @"<!doctype html><html><head><meta charset='utf-8'><title>New tab</title>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<style>
:root{--bg:__BG__;--panel:__PANEL__;--line:__LINE__;--text:__TEXT__;--mute:__MUTE__;--accent:__ACCENT__;color-scheme:__SCHEME__}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:radial-gradient(900px 520px at 50% -10%,__GLOW__,transparent 70%),var(--bg);color:var(--text);font:14px/1.5 'Segoe UI Variable Text','Segoe UI',system-ui,sans-serif;display:flex;align-items:center;justify-content:center}
main{width:min(640px,90vw);display:flex;flex-direction:column;align-items:center;margin-top:-6vh}
.clock{font-size:76px;font-weight:300;letter-spacing:-.02em;line-height:1;__CLOCKDISPLAY__}
.hello{color:var(--mute);margin:10px 0 28px;font-size:16px;__CLOCKDISPLAY__}
form{width:100%;__SEARCHDISPLAY__}
input{width:100%;height:50px;border-radius:25px;border:1px solid var(--line);background:var(--panel);color:var(--text);font:inherit;font-size:16px;padding:0 22px;outline:none}
input:focus{border-color:var(--accent)}
input::placeholder{color:var(--mute)}
.tiles{display:flex;flex-wrap:wrap;justify-content:center;gap:14px;margin-top:34px}
.tile{width:92px;text-align:center;color:var(--text);text-decoration:none}
.ic img{width:30px;height:30px;border-radius:7px}
.ic{width:56px;height:56px;margin:0 auto 8px;border-radius:16px;background:var(--panel);border:1px solid var(--line);display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:600;color:var(--accent);transition:transform .15s,border-color .15s}
.tile:hover .ic{transform:translateY(-2px);border-color:var(--accent)}
.n{font-size:12px;color:var(--mute);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
</style></head><body><main>
<div class='clock' id='clock'></div><div class='hello' id='hello'></div>
<form id='f'><input id='q' type='text' placeholder='Search or enter address' autocomplete='off' spellcheck='false'></form>
<div class='tiles'>__TILES__</div></main>
<script>
const T=__TEMPLATE__, H24=__H24__, NAME=__NAME__;
function tick(){
  const d=new Date(); const h=d.getHours(); const m=String(d.getMinutes()).padStart(2,'0');
  document.getElementById('clock').textContent = H24 ? String(h).padStart(2,'0')+':'+m : ((h+11)%12+1)+':'+m;
  const g = h<5 ? 'Still up' : h<12 ? 'Good morning' : h<18 ? 'Good afternoon' : 'Good evening';
  document.getElementById('hello').textContent = NAME ? g+', '+NAME : g;
}
tick(); setInterval(tick, 10000);
function go(v){
  v=v.trim(); if(!v) return; let u;
  if(/^[a-z][a-z0-9+.-]*:\/\//i.test(v)) u=v;
  else if(!/\s/.test(v) && /^[^\s\/]+\.[a-z]{2,}(\/.*)?$/i.test(v)) u='https://'+v;
  else u=T.replace('%s', encodeURIComponent(v));
  location.href=u;
}
document.getElementById('f').addEventListener('submit', function(e){ e.preventDefault(); go(document.getElementById('q').value); });
</script></body></html>";

    static string Col(string key)
    {
        try
        {
            var c = ((System.Windows.Media.SolidColorBrush)System.Windows.Application.Current.FindResource(key)).Color;
            if (c.A == 255) return "#" + c.R.ToString("x2") + c.G.ToString("x2") + c.B.ToString("x2");
            return "rgba(" + c.R + "," + c.G + "," + c.B + "," + (c.A / 255.0).ToString("0.###", CultureInfo.InvariantCulture) + ")";
        }
        catch { return "#888888"; }
    }

    static string Glow()
    {
        try
        {
            var c = ((System.Windows.Media.SolidColorBrush)System.Windows.Application.Current.FindResource("Accent")).Color;
            return "rgba(" + c.R + "," + c.G + "," + c.B + ",0.16)";
        }
        catch { return "rgba(143,179,201,0.16)"; }
    }

    static string Js(string v) => System.Text.Json.JsonSerializer.Serialize(v ?? "");

    public static string NewTabHtml()
    {
        string template = SearchEngines.Template(Services.Settings.Str("searchEngine"));
        bool h24 = false, showClock = true, showSearch = true;
        string name = "";
        var tiles = new StringBuilder();
        try
        {
            var nt = Services.Settings.NewTab();
            h24 = nt["use24Hour"]?.GetValue<bool>() ?? false;
            showClock = nt["showClock"]?.GetValue<bool>() ?? true;
            showSearch = nt["showSearch"]?.GetValue<bool>() ?? true;
            name = nt["name"]?.GetValue<string>() ?? "";
            if (nt["shortcuts"] is JsonArray sc)
                foreach (var item in sc.Take(12))
                {
                    var url = item?["url"]?.GetValue<string>() ?? "";
                    if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) continue;
                    var title = item?["title"]?.GetValue<string>();
                    if (string.IsNullOrWhiteSpace(title)) title = UrlResolver.HostOf(url);
                    var letter = string.IsNullOrEmpty(title) ? "+" : title.Substring(0, 1).ToUpperInvariant();
                    var fav = Services.LoadFavicon(UrlResolver.HostOf(url));
                    var icon = fav != null && fav.Length > 0 ? "<img src=\"data:image/png;base64," + Convert.ToBase64String(fav) + "\">" : Escape(letter);
                    tiles.Append("<a class=\"tile\" href=\"").Append(Escape(url)).Append("\"><div class=\"ic\">").Append(icon)
                         .Append("</div><div class=\"n\">").Append(Escape(title)).Append("</div></a>");
                }
        }
        catch { }

        return NewTabTemplate
            .Replace("__BG__", Col("Bg"))
            .Replace("__PANEL__", Col("Field"))
            .Replace("__LINE__", Col("Line"))
            .Replace("__TEXT__", Col("Text"))
            .Replace("__MUTE__", Col("Mute"))
            .Replace("__ACCENT__", Col("Accent"))
            .Replace("__GLOW__", Glow())
            .Replace("__SCHEME__", Theme.IsDark() ? "dark" : "light")
            .Replace("__CLOCKDISPLAY__", showClock ? "" : "display:none")
            .Replace("__SEARCHDISPLAY__", showSearch ? "" : "display:none")
            .Replace("__TILES__", tiles.ToString())
            .Replace("__TEMPLATE__", Js(template))
            .Replace("__H24__", h24 ? "true" : "false")
            .Replace("__NAME__", Js(name));
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
