import AppKit
import WebKit
import VeilCore

extension Notification.Name {
    static let veilSettingsChanged = Notification.Name("VeilSettingsChanged")
}

/// Process-wide state. Everything persists locally under ~/Library/Application Support/Veil.
final class Services {
    static let shared = Services()

    /// Looks like Safari to websites; Google and others reject sign-in from "embedded" WebViews
    /// whose user agent lacks the Safari token.
    static let userAgentSuffix = "Version/17.4 Safari/605.1.15"

    let settingsStore = JSONStore<Settings>(name: "settings", defaultValue: Settings())
    let history = HistoryStore()
    let bookmarks = BookmarkStore()
    let allowlist = AllowlistStore()
    let permissions = PermissionStore()
    let sessionStore = JSONStore<SessionState>(name: "session", defaultValue: SessionState())
    let blocker = BlockerManager()
    let downloads = DownloadManager()
    let cookies = CookieKeeper()
    /// Optional start-page picture (stored locally as a data URL; fetched only by the start page).
    let startBackground = JSONStore<String>(name: "start-background", defaultValue: "")

    /// Shared by all private tabs; lives only in memory and is dropped when the last private tab closes.
    private var privateStore: WKWebsiteDataStore?

    var settings: Settings { settingsStore.value }

    func updateSettings(_ body: (inout Settings) -> Void) {
        settingsStore.mutate(body)
        applyAppearance()
        notifyChanged()
    }

    func notifyChanged() {
        NotificationCenter.default.post(name: .veilSettingsChanged, object: nil)
    }

    func applyAppearance() {
        switch settings.theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "system": NSApp.appearance = nil
        default: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        Theme.current = settings.browserTheme
        for w in NSApp.windows { w.contentView?.refreshAllChrome() }
    }

    func privateDataStore() -> WKWebsiteDataStore {
        if let s = privateStore { return s }
        let s = WKWebsiteDataStore.nonPersistent()
        privateStore = s
        return s
    }
    func dropPrivateStore() { privateStore = nil }

    /// Normal tabs share the default (PERSISTENT) data store: cookies, localStorage and IndexedDB
    /// survive quitting the app. Nothing in Veil ever clears it automatically.
    func makeConfiguration(isPrivate: Bool = false) -> WKWebViewConfiguration {
        prepare(WKWebViewConfiguration(), store: isPrivate ? privateDataStore() : WKWebsiteDataStore.default())
    }

    /// `store == nil` keeps whatever store WebKit already gave the configuration (popups inherit the opener's).
    @discardableResult
    func prepare(_ c: WKWebViewConfiguration, store: WKWebsiteDataStore?) -> WKWebViewConfiguration {
        if let store = store { c.websiteDataStore = store }
        c.applicationNameForUserAgent = Services.userAgentSuffix
        c.preferences.javaScriptCanOpenWindowsAutomatically = !settings.blockPopups   // blocks script popups without a click
        c.preferences.isFraudulentWebsiteWarningEnabled = true
        // Must be set on the configuration BEFORE the web view exists, or "Inspect Element" never appears.
        c.preferences.setValue(settings.developerTools, forKey: "developerExtrasEnabled")
        if c.urlSchemeHandler(forURLScheme: "veil") == nil {
            c.setURLSchemeHandler(SchemeHandler.shared, forURLScheme: "veil")
        }
        configure(c.userContentController, muted: false)
        return c
    }

    func configure(_ ucc: WKUserContentController, muted: Bool) {
        ucc.removeAllUserScripts()
        if muted {
            ucc.addUserScript(WKUserScript(source: "window.__veilStartMuted = true;", injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false))
        }
        ucc.addUserScript(WKUserScript(source: MuteScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if settings.fingerprintProtection {
            ucc.addUserScript(WKUserScript(source: Fingerprint.script, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false))
        }
        if settings.sendGPC {
            ucc.addUserScript(WKUserScript(source: "try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:()=>true,configurable:true});}catch(e){}",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if let ops = OpSec.script(for: settings) {
            ucc.addUserScript(WKUserScript(source: ops, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if let fun = FunPage.script(for: settings) {
            ucc.addUserScript(WKUserScript(source: fun, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        ucc.removeScriptMessageHandler(forName: "veil", contentWorld: .page)
        ucc.addScriptMessageHandler(Bridge.shared, contentWorld: .page, name: "veil")
    }

    func flushAll() {
        settingsStore.flush(); history.flush(); bookmarks.flush(); allowlist.flush()
        permissions.flush(); sessionStore.flush(); blocker.meta.flush(); downloads.flush()
    }
}

/// Runs in every page and frame. Lets a tab be muted (silences <video>/<audio>, including ones added later)
/// and tells Veil when something is actually audible, so the tab can show a speaker icon.
enum MuteScript {
    static let source = #"""
    (() => {
      if (window.__veilSetMuted) return;
      const fid = Math.random().toString(36).slice(2);
      let muted = !!window.__veilStartMuted;
      let last = null;
      const media = () => document.querySelectorAll('video,audio');
      const silence = () => media().forEach(m => { if (!m.dataset.veilWas) m.dataset.veilWas = m.muted ? '1' : '0'; if (!m.muted) m.muted = true; });
      const audible = m => !m.paused && !m.ended && m.readyState > 2 && m.volume > 0 && (m.dataset.veilWas ? m.dataset.veilWas === '0' : !m.muted);
      const report = () => {
        const playing = Array.prototype.some.call(media(), audible);
        if (playing === last) return;
        last = playing;
        try { window.webkit.messageHandlers.veilMedia.postMessage({ id: fid, playing: playing }); } catch (e) {}
      };
      window.__veilSetMuted = v => {
        muted = v;
        if (v) silence();
        else media().forEach(m => { m.muted = m.dataset.veilWas === '1'; delete m.dataset.veilWas; });
        report();
      };
      ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange', 'loadeddata'].forEach(t => document.addEventListener(t, e => {
        const el = e.target;
        if (muted && el && el.tagName && /^(VIDEO|AUDIO)$/.test(el.tagName) && !el.muted) silence();
        report();
      }, true));
      new MutationObserver(() => { if (muted) silence(); }).observe(document, { childList: true, subtree: true });
      if (muted) silence();
      setTimeout(report, 800);
    })();
    """#
}

enum Fingerprint {
    /// Best-effort, optional protection: perturbs canvas readback and fixes core count.
    static let script = #"""
    (() => {
      try {
        const noisy = (src) => {
          const c = document.createElement('canvas');
          c.width = src.width; c.height = src.height;
          const x = c.getContext('2d');
          x.drawImage(src, 0, 0);
          const id = origGet.call(x, 0, 0, Math.max(1, c.width), Math.max(1, c.height));
          for (let i = 0; i < id.data.length; i += 211) id.data[i] = (id.data[i] + 1) & 255;
          x.putImageData(id, 0, 0);
          return c;
        };
        const origGet = CanvasRenderingContext2D.prototype.getImageData;
        CanvasRenderingContext2D.prototype.getImageData = function (...a) {
          const d = origGet.apply(this, a);
          for (let i = 0; i < d.data.length; i += 211) d.data[i] = (d.data[i] + 1) & 255;
          return d;
        };
        const origURL = HTMLCanvasElement.prototype.toDataURL;
        HTMLCanvasElement.prototype.toDataURL = function (...a) {
          try { if (this.width && this.height) return origURL.apply(noisy(this), a); } catch (e) {}
          return origURL.apply(this, a);
        };
        Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 4 });
      } catch (e) {}
    })();
    """#
}
