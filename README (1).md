# Veil

A small, private, native macOS browser. Swift + AppKit + WKWebView. No Electron, no third-party dependencies, no telemetry.

## Windows

A Windows port (C# + WPF + WebView2) lives in [`windows/`](windows/README.md). The Swift code below is macOS only.

## Status

Builds and runs on macOS (first version confirmed by the author). Later additions (private tabs, bookmarks bar,
favicons, tab sound/mute, native window buttons, new start page) were written without a compiler available, so
test them and report any build errors. Use the checklist at the bottom.

## What is in it

- Tabs above the address bar (outlined, site icons, speaker/mute button), vertical-tab mode, bookmarks bar.
- Downloads panel (toolbar button): drag finished files into web pages, the desktop, or any app.
- Right-click menu: open in new/private tab, save image/video, copy link, search selection, view source, Inspect Element.
- Mouse side buttons go back/forward. Private tabs (⇧⌘N). Persistent logins.
- Cookies: Allow all / Block third-party (default) / Block all except listed sites. Cookie banners hidden by the
  "Cookie banners and annoyances" list (download lists once in Settings).
- Ad/tracker blocking, HTTPS upgrade, Global Privacy Control, optional fingerprinting protection.
- Customisable start page: backgrounds, your own picture, dimming, font, clock/shortcut styles and sizes.
- Settings for downloads folder, zoom, pop-ups, developer tools, tab width, bookmarks bar, history clearing.

## Why WKWebView (vs CEF)

| | WKWebView | CEF/Chromium |
|---|---|---|
| Memory / startup | Shared system engine, tiny app (~1 MB) | 250 MB+ bundle, many helper processes |
| Updates / security | Patched by macOS | You track Chromium releases |
| Persistent logins | `WKWebsiteDataStore.default()` | Works |
| uBlock Origin itself | Not possible (no extension host) | Not possible (MV2 removed, weak CEF extension support) |
| Ad blocking | `WKContentRuleList` compiled from filter lists, in-engine | Would need a custom engine |

**Limits you should know about**
- This is *not* uBlock Origin. EasyList/EasyPrivacy/uBO lists are compiled to WebKit's blocker format. Network blocking, popups and most element hiding work; uBO scriptlets, redirects, `removeparam`, regex filters and procedural cosmetic filters are skipped (counted in Privacy dashboard).
- **YouTube ads**: they are served from YouTube's own domains, so network rules mostly can't stop them.
- WebKit gives no per-request "blocked" counter, so the dashboard shows rule counts, not blocks.
- Third-party cookie blocking uses a `block-cookies` rule; "Sign in with Google" popups are first-party and fine, but some embedded third-party login iframes may need the per-site shield toggle.

## Build

Requires macOS 13+ and Xcode or the Command Line Tools (Swift 5.9+).

    cd Veil
    ./run.sh                    # builds (first time / after changes) and opens Veil.app
    # (always rebuilds incrementally, so it is never out of date)

    swift test                  # unit tests for VeilCore
    ./scripts/build_app.sh      # just build build/Veil.app (ad-hoc signed)

For development: `swift run Veil` (runs without a bundle; camera/mic prompts and default-browser registration need the .app).

## Layout

- `Sources/VeilCore` – Foundation-only: filter compiler, URL resolver, JSON stores, models.
- `Sources/Veil` – AppKit app: window/tabs, Tab (lazy WKWebView), BlockerManager, CookieKeeper, DownloadManager, `veil://` pages + bridge.
- Data lives in `~/Library/Application Support/Veil` (0700/0600) plus WebKit's own store for cookies and site data.

## Login persistence design
- One persistent `WKWebsiteDataStore.default()` for every tab. Nothing in the code clears it automatically.
- WebKit drops *session* cookies on quit, so `CookieKeeper` saves them to `session-cookies.json` at quit and restores them (30-day expiry) at next launch. Setting: "Keep me signed in across restarts" (default on).
- Safari-style user agent so Google/Discord don't treat Veil as an unsupported embedded view.

## Privacy: the only third-party network traffic
Downloading filter lists, and only after you agree (first run prompt) or press the button in Settings. Uses an ephemeral URLSession (no cookies). Favicons, sync, suggestions, safe-browsing proxies: none. (WebKit's fraudulent-site warning is enabled; it uses Apple's service.)

## Not implemented
Address-bar suggestions dropdown, favicons, tab drag-reorder, bookmark folders, HTTP basic-auth prompts, geolocation prompts, extensions, import from other browsers, app icon.

## Verification checklist (run these on a Mac)
1. `swift test` passes.
2. Build, launch: window opens in dark mode with a New Tab page. Type `example.com`, `localhost:3000`, `cats` — https page / http / search.
3. Cmd+T/W/Shift+T, Cmd+1..9, Ctrl+Tab, Cmd+L, Cmd+[ ], Cmd+D, Cmd+Shift+\ (vertical tabs animates).
4. First-run prompt: download lists. Settings shows "Updated …" dates and rule counts. Visit an ad-heavy site; compare with the shield toggled off.
5. **Login persistence**: sign in to Google, YouTube, Reddit, Discord. Cmd+Q. Relaunch: still signed in. Also test after force-quit (`kill -9`) to see what survives.
6. Settings > Privacy toggles; Privacy page lists cookies, allowlist add/remove, Remove cookies (signs you out, confirm first).
7. Download a file (appears in ~/Downloads and the Downloads page).
8. Open Activity Monitor: compare memory with 10 tabs open; background tabs unload after the idle time.

## Install (for everyone)

1. Download `Veil-<version>.dmg` from the **Releases** page.
2. Open it and drag **Veil** onto **Applications**.
3. The first time, macOS says it can't check the app because it isn't notarized. Right-click Veil in
   Applications, choose **Open**, then **Open** again. (Or run
   `xattr -dr com.apple.quarantine /Applications/Veil.app` once in Terminal.)

## Publishing a release on GitHub

```
git init && git add . && git commit -m "Veil"
git remote add origin https://github.com/<you>/veil.git && git push -u origin main
git tag v1.0.0 && git push origin v1.0.0
```

Pushing the tag starts the **Build installer** workflow (`.github/workflows/release.yml`). It builds on a Mac in
GitHub's cloud and attaches `Veil-1.0.0.dmg` and `Veil-1.0.0.zip` to the release automatically.
To build the installer yourself on a Mac: `./scripts/make_dmg.sh 1.0.0` (files appear in `dist/`).

Removing the "unidentified developer" warning entirely needs an Apple Developer account ($99/year) so the app can be
signed and notarized.
