using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Veil.Core;

namespace Veil;

/// Page and tab commands: find, zoom, print, PDF, screenshot, reader view, tab tools, menus.
public sealed partial class MainWindow
{
    // ---------------- find in page ----------------
    Border findBar;
    TextBox findBox;
    TextBlock findStatus;

    Border BuildFindBar()
    {
        findBox = new TextBox { Width = 250, Height = 28, Padding = new Thickness(8, 3, 8, 3), VerticalContentAlignment = VerticalAlignment.Center, BorderThickness = new Thickness(1) };
        findBox.SetResourceReference(Control.BackgroundProperty, "Field");
        findBox.SetResourceReference(Control.ForegroundProperty, "Text");
        findBox.SetResourceReference(Control.BorderBrushProperty, "Line");
        findBox.TextChanged += (s, e) => RunFind(false, true);
        findBox.PreviewKeyDown += (s, e) =>
        {
            if (e.Key == Key.Enter) { RunFind((Keyboard.Modifiers & ModifierKeys.Shift) != 0, false); e.Handled = true; }
            else if (e.Key == Key.Escape) { HideFind(); e.Handled = true; }
        };
        findStatus = new TextBlock { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, FontSize = 12 };
        findStatus.SetResourceReference(TextBlock.ForegroundProperty, "Mute");
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        panel.Children.Add(findBox);
        panel.Children.Add(Btn("\uE70E", "Previous match (Shift+Enter)", () => RunFind(true, false)));
        panel.Children.Add(Btn("\uE70D", "Next match (Enter)", () => RunFind(false, false)));
        panel.Children.Add(Btn("\uE711", "Close (Esc)", () => HideFind()));
        panel.Children.Add(findStatus);
        findBar = new Border { Child = panel, Padding = new Thickness(12, 4, 12, 6), Visibility = Visibility.Collapsed };
        findBar.SetResourceReference(Border.BackgroundProperty, "Bar");
        return findBar;
    }

    void ShowFind()
    {
        if (findBar == null) return;
        findBar.Visibility = Visibility.Visible;
        findBox.Focus();
        findBox.SelectAll();
        if (findBox.Text.Length > 0) RunFind(false, true);
    }

    void HideFind()
    {
        if (findBar == null) return;
        findBar.Visibility = Visibility.Collapsed;
        try { active?.Core?.ExecuteScriptAsync("window.getSelection().removeAllRanges()"); } catch { }
        active?.FocusPage();
    }

    async void RunFind(bool backwards, bool fresh)
    {
        var core = active?.Core;
        if (core == null || findBox == null) return;
        var term = findBox.Text;
        try
        {
            if (term.Length == 0)
            {
                await core.ExecuteScriptAsync("window.getSelection().removeAllRanges()");
                findStatus.Text = "";
                return;
            }
            if (fresh) await core.ExecuteScriptAsync("window.getSelection().removeAllRanges()");
            var found = await core.ExecuteScriptAsync("window.find(" + JsonSerializer.Serialize(term) + ", false, " + (backwards ? "true" : "false") + ", true, false, true, false)");
            findStatus.Text = found == "true" ? "" : "No matches";
        }
        catch { }
    }

    // ---------------- zoom, print, save ----------------
    void Zoom(double factor, bool reset)
    {
        var c = active?.Host?.Controller;
        if (c == null) return;
        try { c.ZoomFactor = reset ? 1.0 : Math.Max(0.25, Math.Min(5.0, c.ZoomFactor * factor)); } catch { }
    }

    void PrintPage()
    {
        try { active?.Core?.ShowPrintUI(CoreWebView2PrintDialogKind.Browser); } catch { }
    }

    static string SafeName(string name)
    {
        var bad = System.IO.Path.GetInvalidFileNameChars();
        var s = new string((name ?? "page").Select(c => bad.Contains(c) ? '_' : c).ToArray()).Trim();
        return s.Length == 0 ? "page" : (s.Length > 80 ? s.Substring(0, 80) : s);
    }

    async void SavePdf()
    {
        var core = active?.Core;
        if (core == null) return;
        var dlg = new Microsoft.Win32.SaveFileDialog { Filter = "PDF document (*.pdf)|*.pdf", FileName = SafeName(active.Title) + ".pdf" };
        if (dlg.ShowDialog(this) != true) return;
        try { await core.PrintToPdfAsync(dlg.FileName); }
        catch (Exception ex) { MessageBox.Show("Could not save the PDF:\n" + ex.Message, "Veil"); }
    }

    async void CopyScreenshot()
    {
        var core = active?.Core;
        if (core == null) return;
        try
        {
            using var ms = new MemoryStream();
            await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
            ms.Position = 0;
            var bi = new System.Windows.Media.Imaging.BitmapImage();
            bi.BeginInit();
            bi.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            bi.StreamSource = ms;
            bi.EndInit();
            bi.Freeze();
            Clipboard.SetImage(bi);
        }
        catch { }
    }

    async void ToggleReader()
    {
        var core = active?.Core;
        if (core == null || active.Url.StartsWith("veil://")) return;
        try { await core.ExecuteScriptAsync(Res.Text("readerview.js")); } catch { }
    }

    void ViewSource()
    {
        if (active != null && active.Url.StartsWith("http")) NewTab("view-source:" + active.Url, active.IsPrivate, true, active);
    }

    async void HardReload()
    {
        var core = active?.Core;
        if (core == null) return;
        try { await core.CallDevToolsProtocolMethodAsync("Page.reload", "{\"ignoreCache\":true}"); }
        catch { active?.Reload(); }
    }

    // ---------------- tab tools ----------------
    void ToggleSetting(string key)
    {
        Services.Settings.Set(key, System.Text.Json.Nodes.JsonValue.Create(!Services.Settings.Bool(key)));
        Services.Notify();
    }

    void DuplicateTab()
    {
        if (active != null) NewTab(active.Url, active.IsPrivate, true, active);
    }

    void CopyPageAddress()
    {
        try { if (active != null) Clipboard.SetText(active.DisplayUrl); } catch { }
    }

    void CopyAllAddresses()
    {
        var urls = tabs.Select(t => t.Url).Where(u => u.StartsWith("http")).ToList();
        if (urls.Count == 0) return;
        try { Clipboard.SetText(string.Join("\n", urls)); } catch { }
    }

    void OpenLinksFromClipboard()
    {
        string text;
        try { text = Clipboard.GetText(); } catch { return; }
        var links = text.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Where(w => w.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || w.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            .Distinct().Take(30).ToList();
        for (int i = 0; i < links.Count; i++) NewTab(links[i], false, i == 0);
    }

    void ReloadAllTabs()
    {
        foreach (var t in tabs.Where(x => x.Core != null).ToList()) t.Reload();
    }

    void ReorderStrip()
    {
        foreach (var t in tabs) tabStrip.Children.Remove(t.Header);
        for (int k = 0; k < tabs.Count; k++) tabStrip.Children.Insert(k, tabs[k].Header);
        FitTabs();
        SaveSession();
    }

    void MoveActiveTab(int delta)
    {
        if (active == null) return;
        int i = tabs.IndexOf(active), j = i + delta;
        if (i < 0 || j < 0 || j >= tabs.Count) return;
        tabs.RemoveAt(i);
        tabs.Insert(j, active);
        ReorderStrip();
    }

    void SortTabsBySite()
    {
        var sorted = tabs.OrderBy(t => UrlResolver.HostOf(t.Url), StringComparer.Ordinal).ToList();
        tabs.Clear();
        tabs.AddRange(sorted);
        ReorderStrip();
    }

    void CloseDuplicateTabs()
    {
        var seen = new HashSet<string>();
        foreach (var t in tabs.ToList())
        {
            if (t.Url.StartsWith("veil://") || t.Url.Length == 0) continue;
            if (!seen.Add(t.Url)) CloseTab(t);
        }
    }

    void SearchTabs()
    {
        var items = new List<MenuEntry>();
        foreach (var t in tabs.Take(18))
        {
            var tab = t;
            var name = tab.DisplayTitle;
            if (name.Length > 42) name = name.Substring(0, 41) + "…";
            items.Add(MenuEntry.Item((tab == active ? "● " : "") + name, () => Activate(tab), UrlResolver.HostOf(tab.Url)));
        }
        if (items.Count == 0) return;
        VeilMenu.Show(addressBox, items);
    }

    void ResetAllSettings()
    {
        if (MessageBox.Show("Reset every setting to its default?\n\nBookmarks, history and downloads are kept.", "Veil", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try
        {
            var defaults = System.Text.Json.Nodes.JsonNode.Parse(Res.Text("settings-defaults.json")).AsObject();
            foreach (var kv in defaults)
            {
                if (kv.Key == "newTab") continue;
                try { Services.Settings.Set(kv.Key, System.Text.Json.Nodes.JsonNode.Parse(kv.Value.ToJsonString())); } catch { }
            }
        }
        catch { }
        Services.Notify();
    }

    void ShowAbout()
    {
        MessageBox.Show("Veil for Windows\n\nA private-by-default browser, built on Microsoft Edge WebView2.\nThe same features as Veil for Mac.", "About Veil");
    }

    // ---------------- menus ----------------
    void ShowMainMenu()
    {
        VeilMenu.Show(menuB, new[]
        {
            MenuEntry.Item("New tab", () => NewTab(), "Ctrl+T"),
            MenuEntry.Item("New private tab", () => NewTab(null, true), "Ctrl+Shift+N"),
            MenuEntry.Sep(),
            MenuEntry.Item("History", () => OpenInternal("veil://history"), "Ctrl+H"),
            MenuEntry.Item("Bookmarks", () => OpenInternal("veil://bookmarks")),
            MenuEntry.Item("Downloads", () => OpenInternal("veil://downloads"), "Ctrl+J"),
            MenuEntry.Sep(),
            MenuEntry.Item("Find in page", () => ShowFind(), "Ctrl+F"),
            MenuEntry.Item("Page tools", () => ShowPageToolsMenu(), "›"),
            MenuEntry.Item("Tab tools", () => ShowTabToolsMenu(), "›"),
            MenuEntry.Sep(),
            MenuEntry.Item("Privacy", () => OpenInternal("veil://privacy")),
            MenuEntry.Item("Settings", () => OpenInternal("veil://settings"), "Ctrl+,"),
            MenuEntry.Sep(),
            MenuEntry.Item("Vertical tabs", () => ToggleVertical(), "Ctrl+Shift+\\"),
            MenuEntry.Item("Bookmarks bar", () => ToggleSetting("showBookmarksBar"), "Ctrl+Shift+B"),
            MenuEntry.Item("Keep window on top", () => ToggleSetting("alwaysOnTop")),
            MenuEntry.Item("Full screen", () => SetFullscreen(!fullscreen), "F11"),
            MenuEntry.Sep(),
            MenuEntry.Item("Hide and mute everything", () => Panic(), "Ctrl+Alt+H"),
            MenuEntry.Item("Reset all settings…", () => ResetAllSettings()),
            MenuEntry.Item("About Veil", () => ShowAbout()),
            MenuEntry.Item("Exit", () => Close()),
        }, rightAlign: true);
    }

    void ShowPageToolsMenu()
    {
        VeilMenu.Show(menuB, new[]
        {
            MenuEntry.Item("Reader view", () => ToggleReader(), "Ctrl+Alt+R"),
            MenuEntry.Item(IsSplit ? "Close split view" : "Split view with a new tab", () => ToggleSplit(), "Ctrl+Alt+S"),
            MenuEntry.Sep(),
            MenuEntry.Item("Print…", () => PrintPage(), "Ctrl+P"),
            MenuEntry.Item("Save as PDF…", () => SavePdf()),
            MenuEntry.Item("Copy screenshot of page", () => CopyScreenshot()),
            MenuEntry.Sep(),
            MenuEntry.Item("Zoom in", () => Zoom(1.1, false), "Ctrl++"),
            MenuEntry.Item("Zoom out", () => Zoom(1 / 1.1, false), "Ctrl+-"),
            MenuEntry.Item("Actual size", () => Zoom(1, true), "Ctrl+0"),
            MenuEntry.Sep(),
            MenuEntry.Item("Reload", () => active?.Reload(), "Ctrl+R"),
            MenuEntry.Item("Reload without cache", () => HardReload(), "Ctrl+Shift+R"),
            MenuEntry.Item("Stop loading", () => active?.Stop()),
            MenuEntry.Item("View page source", () => ViewSource(), "Ctrl+U"),
            MenuEntry.Item("Developer tools", () => { try { active?.Core?.OpenDevToolsWindow(); } catch { } }, "F12"),
        }, rightAlign: true);
    }

    void ShowTabToolsMenu()
    {
        VeilMenu.Show(menuB, new[]
        {
            MenuEntry.Item("Search tabs", () => SearchTabs(), "Ctrl+Shift+A"),
            MenuEntry.Item("Duplicate tab", () => DuplicateTab(), "Ctrl+Alt+D"),
            MenuEntry.Item(active != null && active.Muted ? "Unmute tab" : "Mute tab", () => active?.ToggleMute(), "Ctrl+Alt+M"),
            MenuEntry.Sep(),
            MenuEntry.Item("Move tab left", () => MoveActiveTab(-1), "Ctrl+Alt+Left"),
            MenuEntry.Item("Move tab right", () => MoveActiveTab(1), "Ctrl+Alt+Right"),
            MenuEntry.Item("Sort tabs by site", () => SortTabsBySite()),
            MenuEntry.Item("Close duplicate tabs", () => CloseDuplicateTabs()),
            MenuEntry.Item("Close other tabs", () => { if (active != null) CloseOthers(active); }),
            MenuEntry.Sep(),
            MenuEntry.Item("Copy page address", () => CopyPageAddress()),
            MenuEntry.Item("Copy all tab addresses", () => CopyAllAddresses()),
            MenuEntry.Item("Open links from clipboard", () => OpenLinksFromClipboard()),
            MenuEntry.Item("Reload all tabs", () => ReloadAllTabs()),
        }, rightAlign: true);
    }

    void ShowDownloadsMenu()
    {
        var entries = new List<MenuEntry>();
        try
        {
            var recent = Services.Downloads.List().Cast<System.Text.Json.Nodes.JsonNode>().Reverse().Take(8).ToList();
            foreach (var it in recent)
            {
                var name = it["name"]?.GetValue<string>() ?? "download";
                var state = it["state"]?.GetValue<string>() ?? "";
                var path = it["path"]?.GetValue<string>() ?? "";
                string hint = state == "done" ? "Open" : state == "running" ? "Downloading…" : state;
                if (state == "running" && it["progress"] != null) hint = (int)(it["progress"].GetValue<double>() * 100) + "%";
                if (name.Length > 36) name = name.Substring(0, 35) + "…";
                entries.Add(MenuEntry.Item(name, () =>
                {
                    try
                    {
                        if (state == "done" && File.Exists(path)) System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
                        else OpenInternal("veil://downloads");
                    }
                    catch { }
                }, hint));
            }
        }
        catch { }
        if (entries.Count == 0) entries.Add(MenuEntry.Item("No downloads yet", null, "", false));
        entries.Add(MenuEntry.Sep());
        entries.Add(MenuEntry.Item("Show all downloads", () => OpenInternal("veil://downloads"), "Ctrl+J"));
        VeilMenu.Show(dlB, entries, rightAlign: true);
    }

    // ---------------- extra keyboard shortcuts (called first by HandleShortcut) ----------------
    bool HandleExtraShortcut(Key key, bool ctrl, bool shift, bool alt)
    {
        if (ctrl && alt && !shift)
        {
            switch (key)
            {
                case Key.R: ToggleReader(); return true;
                case Key.D: DuplicateTab(); return true;
                case Key.S: ToggleSplit(); return true;
                case Key.M: active?.ToggleMute(); return true;
                case Key.Left: MoveActiveTab(-1); return true;
                case Key.Right: MoveActiveTab(1); return true;
            }
            return false;
        }
        if (ctrl && !alt)
        {
            switch (key)
            {
                case Key.F: ShowFind(); return true;
                case Key.G: RunFind(shift, false); return true;
                case Key.P: PrintPage(); return true;
                case Key.U: ViewSource(); return true;
                case Key.OemPlus: Zoom(1.1, false); return true;
                case Key.Add: Zoom(1.1, false); return true;
                case Key.OemMinus: Zoom(1 / 1.1, false); return true;
                case Key.Subtract: Zoom(1 / 1.1, false); return true;
                case Key.D0: Zoom(1, true); return true;
                case Key.NumPad0: Zoom(1, true); return true;
                case Key.A when shift: SearchTabs(); return true;
                case Key.B when shift: ToggleSetting("showBookmarksBar"); return true;
                case Key.R when shift: HardReload(); return true;
            }
            return false;
        }
        if (!ctrl && !alt && key == Key.F3) { RunFind(shift, false); return true; }
        return false;
    }
}
