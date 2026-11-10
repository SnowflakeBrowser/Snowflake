namespace Veil.Tor;

/// The only pages a Tor window shows itself. They are plain HTML drawn with NavigateToString:
/// no veil:// bridge, no access to history, bookmarks, settings or downloads of the normal windows.
public static class TorPages
{
    const string Shell = @"<!doctype html><html><head><meta charset='utf-8'><title>__TITLE__</title>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<meta http-equiv='Content-Security-Policy' content=""default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:"">
<meta name='color-scheme' content='dark light'>
<style>
:root{--bg:#f6f4f9;--panel:#fff;--line:#0002;--text:#1b1b1f;--mute:#66666f;--tor:#7d4698}
@media (prefers-color-scheme:dark){:root{--bg:#17131c;--panel:#221b2b;--line:#fff2;--text:#ececf0;--mute:#9a9aa6;--tor:#b98ad4}}
*{box-sizing:border-box}html,body{height:100%;margin:0}
body{background:radial-gradient(900px 520px at 50% -10%,#7d469833,transparent 70%),var(--bg);color:var(--text);
font:14px/1.55 'Segoe UI Variable Text','Segoe UI',system-ui,sans-serif;display:flex;align-items:center;justify-content:center}
main{width:min(640px,90vw);display:flex;flex-direction:column;align-items:center;margin-top:-5vh;text-align:center}
.onion{font-size:54px;line-height:1}h1{font-weight:600;font-size:26px;margin:12px 0 4px}
.ok{color:var(--tor);font-weight:600}.mute{color:var(--mute)}
form{width:100%;margin:26px 0 22px}
input{width:100%;height:50px;border-radius:25px;border:1px solid var(--line);background:var(--panel);color:var(--text);font:inherit;font-size:16px;padding:0 22px;outline:none}
input:focus{border-color:var(--tor)}
.note{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px 18px;text-align:left;font-size:13px;color:var(--mute)}
.note b{color:var(--text)}
</style></head><body><main>__BODY__</main></body></html>";

    static string Wrap(string title, string body) => Shell.Replace("__TITLE__", title).Replace("__BODY__", body);

    /// Start page of a Tor tab. Only ever shown after the connection has been verified.
    public static string NewTab() => Wrap("New Tor tab", @"
<div class='onion'>🧅</div><h1>Tor window</h1>
<div class='ok'>Connected to Tor · verified</div>
<form id='f'><input id='q' type='text' placeholder='Search DuckDuckGo or enter address' autocomplete='off' spellcheck='false' autofocus></form>
<div class='note'><b>What this does:</b> sites and your network see Tor, not your IP address, and this window keeps its cookies and history to itself
and deletes them when it closes.<br><br>
<b>What it does not do:</b> this is not Tor Browser. Your browser fingerprint (fonts, screen, engine version) can still make you recognisable,
and anything you sign in to identifies you. Don’t use it where anonymity is a matter of safety.</div>
<script>
function go(v){v=v.trim();if(!v)return;var u;
 if(/^[a-z][a-z0-9+.-]*:\/\//i.test(v))u=v;
 else if(!/\s/.test(v)&&/^[^\s\/]+\.[a-z0-9-]{2,}(\/.*)?$/i.test(v))u=(/\.onion(\/|$)/i.test(v)?'http://':'https://')+v;
 else u='https://duckduckgo.com/?q='+encodeURIComponent(v);
 location.href=u;}
document.getElementById('f').addEventListener('submit',function(e){e.preventDefault();go(document.getElementById('q').value);});
</script>");

    /// Shown instead of Veil's normal internal pages (history, settings, …), which must not be reachable from a Tor window.
    public static string Unavailable() => Wrap("Not available", @"
<div class='onion'>🧅</div><h1>Not available in a Tor window</h1>
<p class='mute'>History, bookmarks, downloads and settings belong to your normal windows and are kept out of Tor windows on purpose.</p>");
}
