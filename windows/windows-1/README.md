# Veil for Windows

Same idea as the Mac app: a small, private browser with no bundled Chromium, no telemetry and no third-party
code apart from Microsoft's WebView2 wrapper. On Windows the system web engine is **Microsoft Edge WebView2**
(preinstalled on Windows 11 and current Windows 10), the UI is **WPF / .NET 8**.

The Mac sources in `Sources/` are untouched. This folder is a separate port that reuses the start page,
Settings, Privacy, History, Bookmarks and Downloads pages (`Veil.Windows/Assets/pages.*`) straight from the Mac code.

## Build and run

Install the .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`), then, in PowerShell from the repo root:

    dotnet run --project windows\Veil.Windows                 # quick start
    .\windows\scripts\build_windows.ps1 -Version 1.0.0         # -> windows\dist\Veil-1.0.0-win-x64.zip

Or push a tag (`git tag v1.0.0 && git push origin v1.0.0`): `.github/workflows/release-windows.yml` builds the zip on
GitHub and attaches it to the release, next to the Mac installer.

To use it as your default browser, run `register_default_browser.ps1` (in the zip, or `windows\scripts\`) and pick Veil in
Settings > Default apps. Links you click then open as a new tab in the running Veil.

## Status - read this first

**This port was written without a compiler or a Windows machine available, so it has not been built or run yet.**
Expect to fix a few compile errors on the first `dotnet build` (the GitHub workflow will show them). Please test with the
checklist in the main README plus: tabs in the background, `window.open` popups (Google sign-in), downloads, and ad blocking.

## Tor window

Menu ▸ **New Tor window** (Alt+Shift+N) opens a separate window whose traffic goes through the official Tor daemon. Needs `tor.exe`
in a `tor` folder next to `Veil.exe`: run `scripts\build_windows.ps1 -FetchTor`. Design, limits and test plan: [TOR-WINDOW.md](TOR-WINDOW.md).
**Like the rest of this port, the Tor code has not been compiled or run yet.**

## What differs from the Mac version

| Area | Windows behaviour |
|---|---|
| Engine | WebView2 (Chromium) instead of WKWebView |
| Ad blocking | Same lists (EasyList, EasyPrivacy, uBlock Origin lists), matched by an in-app engine on each request; element hiding injected as CSS. Same limits as on Mac (no scriptlets/redirects/regex/procedural filters). |
| Cookies | WebView2 has no per-request cookie rules. "Block third-party" = WebView2 Tracking Prevention (Strict). "Block all except listed" also deletes non-listed cookies at launch. |
| Private tabs | One shared in-memory WebView2 profile (not saved to disk). |
| Mute / sound icon | WebView2's built-in audio detection and mute. |
| Window | Standard Windows title bar (tabs sit below it). |
| Data | `%APPDATA%\Veil` (settings, history, bookmarks, lists) and `%APPDATA%\Veil\WebView2` (cookies, site data). |

Not ported yet: "unload idle tabs", window opacity, taskbar tab-count badge, the Mac Downloads popover (the Downloads
button opens the Downloads page instead), browser-theme colour presets (only Dark/Light/System + accent), custom
right-click menu (WebView2's own menu is used, including Inspect when developer tools are on).

## Layout

- `Veil.Windows/Core` - filter engine, blocker/list downloader, JSON stores, URL resolver (ports of `VeilCore`).
- `Veil.Windows/App` - WPF window, tabs, WebView2 hosting, bridge for the `veil://` pages, downloads.
- `Veil.Windows/Assets` - pages and injected scripts, generated from the Mac sources (fonts changed to Segoe UI).
