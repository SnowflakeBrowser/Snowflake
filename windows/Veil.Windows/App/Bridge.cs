using System.Text.Json;
using System.Text.Json.Nodes;
using Veil.Core;

namespace Veil;

/// Receives calls from veil:// pages only (the tab checks the sender's origin before calling).
public static class Bridge
{
    static string S(JsonElement a, string k) => a.ValueKind == JsonValueKind.Object && a.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    public static async Task<JsonNode> Handle(BrowserTab tab, string cmd, JsonElement a)
    {
        switch (cmd)
        {
            case "settings.get":
            {
                var meta = Services.Blocker.Meta.Value;
                var engines = new JsonArray(SearchEngines.All.Select(e => (JsonNode)new JsonObject { ["id"] = e.Id, ["name"] = e.Name }).ToArray());
                var sources = new JsonArray(Blocker.Sources.Select(s => (JsonNode)new JsonObject
                {
                    ["id"] = s.Id, ["name"] = s.Name, ["blurb"] = s.Blurb, ["url"] = s.Url ?? "",
                    ["enabled"] = Services.Blocker.IsEnabled(s),
                    ["updated"] = meta.Updated.TryGetValue(s.Id, out var d) ? Util.Epoch(d) : 0,
                }).ToArray());
                return new JsonObject
                {
                    ["settings"] = JsonNode.Parse(Services.Settings.Json()),
                    ["engines"] = engines,
                    ["meta"] = new JsonObject { ["networkRules"] = meta.NetworkRules, ["cosmeticRules"] = meta.CosmeticRules, ["skippedRules"] = meta.SkippedRules, ["failedChunks"] = meta.FailedChunks },
                    ["sources"] = sources,
                };
            }
            case "settings.set":
            {
                var key = S(a, "key");
                if (key == null || !a.TryGetProperty("value", out var val)) return false;
                bool ok = Services.Settings.Set(key, JsonNode.Parse(val.GetRawText()));
                if (ok && (key == "enabledLists" || key == "customRules")) _ = Services.Blocker.RebuildAsync();
                if (ok) Services.Notify();
                return ok;
            }
            case "lists.update":
            {
                var (u, f) = await Services.Blocker.DownloadListsAsync();
                return new JsonObject { ["updated"] = new JsonArray(u.Select(x => (JsonNode)x).ToArray()), ["failed"] = new JsonArray(f.Select(x => (JsonNode)x).ToArray()) };
            }
            case "navigate":
            {
                var text = S(a, "text");
                if (text != null) tab.Navigate(UrlResolver.Resolve(text, SearchEngines.Template(Services.Settings.Str("searchEngine"))));
                return true;
            }
            case "history.list":
                return new JsonArray(Services.History.Search(S(a, "q") ?? "").Select(h => (JsonNode)new JsonObject
                    { ["id"] = h.Id.ToString(), ["url"] = h.Url, ["title"] = h.Title, ["date"] = Util.Epoch(h.Date) }).ToArray());
            case "history.remove":
                if (Guid.TryParse(S(a, "id"), out var hid)) Services.History.Remove(hid);
                return true;
            case "history.clear": Services.History.Clear(); return true;
            case "bookmarks.list":
                return new JsonArray(Services.Bookmarks.All.Select(b => (JsonNode)new JsonObject { ["url"] = b.Url, ["title"] = b.Title }).ToArray());
            case "bookmarks.remove":
                if (S(a, "url") is string bu) Services.Bookmarks.Remove(bu);
                Services.Notify();
                return true;
            case "background.get": return Services.StartBackground.Value;
            case "background.set":
            {
                var d = S(a, "data");
                if (d != null && d.StartsWith("data:image/") && d.Length < 6_000_000) { Services.StartBackground.Value = d; return true; }
                return false;
            }
            case "background.clear": Services.StartBackground.Value = ""; return true;
            case "newtab.icons":
            {
                var o = new JsonObject();
                if (Services.Settings.NewTab()["shortcuts"] is JsonArray sc)
                    foreach (var s in sc)
                    {
                        var url = s?["url"]?.GetValue<string>();
                        var png = url == null ? null : Services.LoadFavicon(UrlResolver.HostOf(url));
                        if (png != null) o[url] = "data:image/png;base64," + Convert.ToBase64String(png);
                    }
                return o;
            }
            case "downloads.chooseFolder":
            {
                var dlg = new Microsoft.Win32.OpenFolderDialog { Title = "Choose download folder" };
                if (dlg.ShowDialog() == true) Services.Settings.Set("downloadFolder", JsonValue.Create(dlg.FolderName));
                Services.Notify();
                return Services.Settings.Str("downloadFolder");
            }
            case "downloads.list": return Services.Downloads.List();
            case "downloads.reveal": Services.Downloads.Reveal(S(a, "id") ?? ""); return true;
            case "downloads.open": Services.Downloads.Open(S(a, "id") ?? ""); return true;
            case "downloads.clear": Services.Downloads.ClearFinished(); return true;
            case "allowlist.list": return new JsonArray(Services.Allowlist.All.Select(x => (JsonNode)x).ToArray());
            case "allowlist.add": if (S(a, "host") is string ah) Services.Allowlist.Add(ah); Services.Notify(); return true;
            case "allowlist.remove": if (S(a, "host") is string rh) Services.Allowlist.Remove(rh); Services.Notify(); return true;
            case "permissions.list":
            {
                var rows = new JsonArray();
                foreach (var hostEntry in Services.Permissions.All.OrderBy(x => x.Key))
                    foreach (var kindEntry in hostEntry.Value.OrderBy(y => y.Key))
                        rows.Add(new JsonObject { ["host"] = hostEntry.Key, ["kind"] = kindEntry.Key, ["allowed"] = kindEntry.Value });
                return rows;
            }
            case "permissions.remove":
                if (S(a, "host") is string ph && S(a, "kind") is string pk) Services.Permissions.Remove(ph, pk);
                return true;
            case "privacy.overview":
            {
                var counts = await CookieDomains();
                var m = Services.Blocker.Meta.Value;
                return new JsonObject { ["rules"] = m.NetworkRules + m.CosmeticRules, ["cookieDomains"] = counts.Count,
                                        ["history"] = Services.History.Count, ["bookmarks"] = Services.Bookmarks.All.Count };
            }
            case "cookies.list":
            {
                var counts = await CookieDomains();
                return new JsonArray(counts.OrderBy(k => k.Key).Select(k => (JsonNode)new JsonObject { ["domain"] = k.Key, ["count"] = k.Value }).ToArray());
            }
            case "cookies.clearDomain":
            {
                var d = S(a, "domain") ?? "";
                var core = MainWindow.Current?.PersistentCore();
                if (core != null)
                    foreach (var c in await core.CookieManager.GetCookiesAsync(null))
                        if (c.Domain == d || c.Domain == "." + d) core.CookieManager.DeleteCookie(c);
                return true;
            }
            case "cookies.clearAll":
                MainWindow.Current?.PersistentCore()?.CookieManager.DeleteAllCookies();
                return true;
            case "siteData.clearAll":
            {
                var core = MainWindow.Current?.PersistentCore();
                if (core != null) await core.Profile.ClearBrowsingDataAsync(Microsoft.Web.WebView2.Core.CoreWebView2BrowsingDataKinds.AllSite);
                return true;
            }
            default: return null;
        }
    }

    static async Task<Dictionary<string, int>> CookieDomains()
    {
        var counts = new Dictionary<string, int>();
        var core = MainWindow.Current?.PersistentCore();
        if (core == null) return counts;
        foreach (var c in await core.CookieManager.GetCookiesAsync(null))
        {
            var d = c.Domain.StartsWith(".") ? c.Domain.Substring(1) : c.Domain;
            counts[d] = counts.TryGetValue(d, out var n) ? n + 1 : 1;
        }
        return counts;
    }
}
