# New Tor window

Menu ▸ **New Tor window**, or **Alt+Shift+N** (`Ctrl+Shift+N` was already "New private tab").
A Tor window is a separate top-level window with its own address bar, navigation buttons and tab strip, in your
normal theme, plus a purple address bar and a **Tor status pill** (green = verified and connected, amber = working,
red = offline/error; click it for details and "Try again"). You can open as many Tor windows as you like.

## Architecture

Veil is a WPF shell around Edge **WebView2**, not a Chromium fork, so Tor is wired in at the WebView2 level.

| Piece | File | Job |
|---|---|---|
| Tor daemon | `tor\` next to `Veil.exe` | Unmodified `tor.exe` from the official Tor Expert Bundle (`scripts\fetch_tor.ps1`) |
| `TorManager` | `App/Tor/TorManager.cs` | One shared tor.exe, reference-counted by Tor windows. Generated torrc, loopback-only SOCKS + control ports, cookie auth, `__OwningControllerProcess` (Tor exits if Veil dies). Monitors the circuit, restarts Tor (3 tries), verifies again before unblocking |
| `TorControl` | `App/Tor/TorControl.cs` | Tiny control-port client (AUTHENTICATE / GETINFO / SIGNAL) |
| `TorBrowserEnv` | `App/Tor/TorBrowserEnv.cs` | A **separate WebView2 environment** (own browser process, own throw-away user-data folder under `%LOCALAPPDATA%\Veil\TorSession`) launched with the proxy switches below |
| Tor mode | `App/MainWindow.Tor.cs`, small guarded edits in `MainWindow.cs` / `BrowserTab.cs` | Same toolbar/tabs/theme; status pill; fail-closed gate; cleanup |

### Why traffic cannot silently go direct
1. `--proxy-server=socks5://127.0.0.1:<port>`: Chromium has **no DIRECT fallback** for a single explicit proxy; if Tor is down, requests fail.
2. `--proxy-bypass-list=<-loopback>`: even localhost goes through the proxy (Tor refuses it).
3. `--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"`: Chromium cannot resolve names itself, so a would-be DNS leak fails. With `socks5://` the host name is sent to Tor and resolved there.
4. `--disable-quic`, `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`: no UDP side channels. SmartScreen reputation checks are off in Tor tabs.
5. In-app kill switch: Tor tabs may only navigate to http(s) while `TorUsable` (verified **and** Tor reports Connected). Subresource requests get a 503 otherwise. `file:`, `edge:`, `ftp:` are blocked.
6. Startup gate: no tab loads until (a) Tor says bootstrap 100% with a circuit, (b) `check.torproject.org/api/ip` fetched **through the SOCKS port** says `IsTor:true`, and (c) the same API loaded **inside the Tor window's own browser engine** says `IsTor:true`. Failure locks the window; there is no "continue anyway".

### Session isolation
- Own WebView2 environment + a per-window **in-private** profile: cookies, cache and storage are in memory and separate from normal windows and from other Tor windows.
- Tor tabs never write history, favicons, permissions, bookmarks, allow-list entries, download records, session/bounds files or debug-log lines. No bridge (`veil://settings` etc. shows "Not available"). All permission prompts are denied.
- On close: cookies deleted, WebView2 views closed, the environment released and its folder deleted (retried for ~60 s while the browser process exits); leftovers from a crash are swept at the next launch. Closing the main window closes all Tor windows first and stops tor.exe.
- Persisting on disk by design: Tor's own data directory `%LOCALAPPDATA%\Veil\Tor\data` (cached consensus, guard state) and `run\tor.log` (notice level, SafeLogging). Delete that folder to forget that Tor was ever used.

## Building
```
.\windows\scripts\build_windows.ps1 -FetchTor        # downloads + verifies the official bundle, then builds
```
`fetch_tor.ps1` checks the SHA-256 from `sha256sums-signed-build.txt` and the OpenPGP signature (key
`EF6E 286D DA85 EA2A 4BA7 DE68 4E2C 6E87 9329 8290`, "Tor Browser Developers"; needs `gpg`). Licenses: see
`ThirdParty/NOTICE-tor.txt`; **add the full license texts of the exact Tor release before you distribute**.
The GitHub workflows still build without Tor (the menu item then explains how to add it); add `-FetchTor` to their build step and make `gpg` available (Git for Windows ships one in `C:\Program Files\Git\usr\bin`) when you want Tor in CI builds.

## Known limits (be honest with users)
- **Not Tor Browser.** Edge's fingerprint (UA, fonts, screen size, WebGL) is not uniform, there is no first-party circuit isolation (Chromium cannot send SOCKS credentials), so all tabs/windows share circuits. It hides your IP and DNS from sites and your ISP, nothing more. The Tor start page says so.
- If Tor dies, the SOCKS port briefly has no listener; the kill switch blocks the pages, and re-opening is gated on a fresh `IsTor` verification, so a different local program taking that port cannot be mistaken for Tor.
- No bridges / pluggable transports UI yet (obfs4 is in the bundle if you want to add it); networks that block Tor will show "could not connect".
- Downloads in Tor tabs use WebView2's built-in prompt and go to your normal Downloads folder.

## Test plan
Needs a Windows machine with the bundle installed. `scripts\check_tor_traffic.ps1` automates the socket check.

| # | Test | How | Expect |
|---|---|---|---|
| 1 | Normal windows unaffected | Browse normally; open `https://check.torproject.org` | "Sorry. You are not using Tor"; your real IP |
| 2 | Tor window opens | Menu ▸ New Tor window / Alt+Shift+N | Separate window, purple bar; overlay "Connecting to Tor 0-100%", tab with Tor start page, green pill |
| 3 | Loads through Tor | Menu ▸ Check Tor connection | "Congratulations. This browser is configured to use Tor", exit IP ≠ yours. Run `check_tor_traffic.ps1`: PASS |
| 4 | Multiple tabs | Ctrl+T ×3, load different sites, Ctrl+W, drag/switch | All work, all show a Tor exit IP |
| 5 | Normal windows don't use Tor | While a Tor window is open, check a normal tab | Still your real IP |
| 6 | Disconnect = no fallback | Kill `tor.exe` in Task Manager (or disable the network adapter) while browsing | Overlay "Tor is not connected"; pages blocked; `check_tor_traffic.ps1` shows no direct sockets; Veil restarts Tor; pill returns to green only after re-verification. Also test: Tor missing → menu message |
| 7 | Cleanup on close | Log in to a site / set a cookie in the Tor window, close it, check `%LOCALAPPDATA%\Veil\TorSession` (empty within ~1 min), open a new Tor window | Site shows you logged out; no new entries in History/Downloads of the normal window |
| 8 | Second Tor window | Alt+Shift+N twice | Both work, cookies not shared between them; closing one leaves the other connected; closing the last stops `tor.exe` |

Also check: closing the main window with Tor windows open exits cleanly and leaves no `tor.exe`.
Packet-level proof (optional): `pktmon filter add -i 1.1.1.1` is not needed; simply capture with Wireshark on your
physical adapter and confirm the only traffic from the Tor window is to Tor relays (via `tor.exe`), never to site IPs.
