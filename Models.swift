import Foundation

public struct Shortcut: Codable, Equatable {
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

public struct Todo: Codable, Equatable {
    public var id: String
    public var text: String
    public var done: Bool
    public init(id: String, text: String, done: Bool = false) { self.id = id; self.text = text; self.done = done }
}

public struct NewTabConfig: Codable, Equatable {
    public var shortcuts: [Shortcut]
    public var showClock: Bool
    public var showSearch: Bool
    public var greeting: String
    public var background: String        // poster | plain | grain | glow | dusk | forest | ember | midnight | paper
    public var name: String
    public var use24Hour: Bool
    public var animated: Bool
    public var funLines: Bool
    public var clockSize: String          // small | medium | large
    public var tileStyle: String          // rounded | circle | minimal
    public var tileSize: String           // small | medium | large
    public var showLabels: Bool
    public var dim: Int                   // 0...70, darkens the background
    public var font: String               // modern | rounded | serif
    public var customImage: Bool          // use the picture saved in Settings
    public var showFocus: Bool            // focus timer on the start page
    public var showTodos: Bool            // to-do list on the start page
    public var showNotes: Bool            // quick notes on the start page
    public var focusMinutes: Int
    public var focusEnd: Double           // when the running focus session ends (ms since 1970), 0 = not running
    public var todos: [Todo]
    public var notes: String
    public var ntVersion: Int             // used to move old saved start pages to the current default once

    public init() {
        shortcuts = [
            Shortcut(title: "YouTube", url: "https://www.youtube.com"),
            Shortcut(title: "Reddit", url: "https://www.reddit.com"),
            Shortcut(title: "Discord", url: "https://discord.com/app"),
            Shortcut(title: "Gmail", url: "https://mail.google.com"),
        ]
        showClock = true; showSearch = true; greeting = ""
        background = "aurora"; name = ""; use24Hour = false; animated = true; funLines = true
        clockSize = "large"; tileStyle = "rounded"; tileSize = "medium"; showLabels = true; dim = 0; font = "modern"; customImage = false
        showFocus = false; showTodos = false; showNotes = false; focusMinutes = 25; focusEnd = 0; todos = []; notes = ""; ntVersion = 3
    }

    enum CodingKeys: String, CodingKey {
        case shortcuts, showClock, showSearch, greeting, background, name, use24Hour, animated, funLines
        case clockSize, tileStyle, tileSize, showLabels, dim, font, customImage
        case showFocus, showTodos, showNotes, focusMinutes, focusEnd, todos, notes, ntVersion
    }
    public init(from decoder: Decoder) throws {
        let d = NewTabConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<V: Decodable>(_ k: CodingKeys, _ fallback: V) -> V { (try? c.decodeIfPresent(V.self, forKey: k)) ?? fallback }
        shortcuts = get(.shortcuts, d.shortcuts)
        showClock = get(.showClock, d.showClock)
        showSearch = get(.showSearch, d.showSearch)
        greeting = get(.greeting, d.greeting)
        background = get(.background, d.background)
        name = get(.name, d.name)
        use24Hour = get(.use24Hour, d.use24Hour)
        animated = get(.animated, d.animated)
        funLines = get(.funLines, d.funLines)
        clockSize = get(.clockSize, d.clockSize)
        tileStyle = get(.tileStyle, d.tileStyle)
        tileSize = get(.tileSize, d.tileSize)
        showLabels = get(.showLabels, d.showLabels)
        dim = get(.dim, d.dim)
        font = get(.font, d.font)
        customImage = get(.customImage, d.customImage)
        showFocus = get(.showFocus, d.showFocus)
        showTodos = get(.showTodos, d.showTodos)
        showNotes = get(.showNotes, d.showNotes)
        focusMinutes = get(.focusMinutes, d.focusMinutes)
        focusEnd = get(.focusEnd, d.focusEnd)
        todos = get(.todos, d.todos)
        notes = get(.notes, d.notes)
        ntVersion = get(.ntVersion, 0)
        if ntVersion < 3 {                       // one-time: back to the original Aurora start page
            background = d.background
            showFocus = false
            showTodos = false
            ntVersion = 3
        }
    }
}

public struct Settings: Codable, Equatable {
    public var verticalTabs = false
    public var theme = "dark"                       // dark | light | system
    public var accent = "mist"                      // mist | coral | mint | violet | amber
    public var browserTheme = "default"             // default | midnight | forest | rose | sunset | grape | ocean | mocha | mint | graphite
    public var hideShieldButton = false
    public var hideDownloadsButton = false
    public var hideBookmarkButton = false
    public var newTabNextToCurrent = false
    public var rememberWindow = false
    public var confirmCloseWindow = false
    public var searchEngine = "duckduckgo"
    public var adBlocking = true
    public var cookieMode = "third-party"           // off | third-party | all
    public var cookieExceptions = ["google.com", "youtube.com", "discord.com", "reddit.com"]   // keep cookies here in "all" mode
    public var mouseNavButtons = true               // mouse back/forward buttons navigate
    public var showBookmarksBar = true
    public var tabWidth = "normal"                  // compact | normal | wide
    public var defaultZoom = 100                    // percent
    public var developerTools = true                // "Inspect Element" in the right-click menu
    public var blockPopups = true
    public var sendGPC = true                       // Global Privacy Control signal
    public var clearHistoryOnQuit = false
    public var askDownloadLocation = false
    public var downloadFolder = ""                  // empty = ~/Downloads
    public var openDownloadsOnStart = true
    public var httpsUpgrade = true
    public var fingerprintProtection = false        // optional: can break canvas-heavy sites
    public var restoreSession = true
    public var keepSessionCookies = true            // keeps "session" logins across restarts
    public var discardIdleTabsMinutes = 30          // 0 = never
    public var autoUpdateLists = false
    public var didOfferLists = false
    public var enabledLists: [String: Bool] = [:]
    public var customRules = ""
    public var newTab = NewTabConfig()
    // Fun settings
    public var windowOpacity = 100                  // 60...100, see-through window
    public var alwaysOnTop = false
    public var pageFilter = "none"
    public var pageFont = "default"
    public var linkStyle = "default"
    public var selectionColor = "default"
    public var smoothScroll = false
    public var hideScrollbars = false
    public var roundImages = false
    public var blurImages = false
    public var dimPages = 0
    public var dockTabCount = false
    public var confirmQuit = false
    public var downloadSound = false
    public var reduceMotion = false
    public var forceSelect = false
    public var readableText = false
    public var grayImages = false
    // Privacy hardening
    public var stripTracking = true
    public var opsecWebRTC = true
    public var opsecBeacons = true
    public var opsecReferrer = true
    public var opsecHardware = true
    public var hideFromCapture = false
    public var denyMedia = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case verticalTabs, theme, accent, searchEngine, adBlocking, cookieMode, cookieExceptions, httpsUpgrade
        case mouseNavButtons, showBookmarksBar, tabWidth, defaultZoom, developerTools, blockPopups, sendGPC
        case clearHistoryOnQuit, askDownloadLocation, downloadFolder, openDownloadsOnStart
        case fingerprintProtection, restoreSession, keepSessionCookies, discardIdleTabsMinutes
        case autoUpdateLists, didOfferLists, enabledLists, customRules, newTab
        case browserTheme
        case hideShieldButton, hideDownloadsButton, hideBookmarkButton, newTabNextToCurrent, rememberWindow, confirmCloseWindow
        case stripTracking, opsecWebRTC, opsecBeacons, opsecReferrer, opsecHardware, hideFromCapture, denyMedia
        case dockTabCount, confirmQuit, downloadSound, reduceMotion, forceSelect, readableText, grayImages
        case windowOpacity, alwaysOnTop, pageFilter, pageFont, linkStyle, selectionColor, smoothScroll, hideScrollbars, roundImages, blurImages, dimPages
    }

    public init(from decoder: Decoder) throws {
        let d = Settings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<V: Decodable>(_ k: CodingKeys, _ fallback: V) -> V {
            (try? c.decodeIfPresent(V.self, forKey: k)) ?? fallback
        }
        verticalTabs = get(.verticalTabs, d.verticalTabs)
        theme = get(.theme, d.theme)
        accent = get(.accent, d.accent)
        browserTheme = get(.browserTheme, d.browserTheme)
        hideShieldButton = get(.hideShieldButton, d.hideShieldButton)
        hideDownloadsButton = get(.hideDownloadsButton, d.hideDownloadsButton)
        hideBookmarkButton = get(.hideBookmarkButton, d.hideBookmarkButton)
        newTabNextToCurrent = get(.newTabNextToCurrent, d.newTabNextToCurrent)
        rememberWindow = get(.rememberWindow, d.rememberWindow)
        confirmCloseWindow = get(.confirmCloseWindow, d.confirmCloseWindow)
        searchEngine = get(.searchEngine, d.searchEngine)
        adBlocking = get(.adBlocking, d.adBlocking)
        cookieMode = get(.cookieMode, d.cookieMode)
        cookieExceptions = get(.cookieExceptions, d.cookieExceptions)
        mouseNavButtons = get(.mouseNavButtons, d.mouseNavButtons)
        showBookmarksBar = get(.showBookmarksBar, d.showBookmarksBar)
        tabWidth = get(.tabWidth, d.tabWidth)
        defaultZoom = get(.defaultZoom, d.defaultZoom)
        developerTools = get(.developerTools, d.developerTools)
        blockPopups = get(.blockPopups, d.blockPopups)
        sendGPC = get(.sendGPC, d.sendGPC)
        clearHistoryOnQuit = get(.clearHistoryOnQuit, d.clearHistoryOnQuit)
        askDownloadLocation = get(.askDownloadLocation, d.askDownloadLocation)
        downloadFolder = get(.downloadFolder, d.downloadFolder)
        openDownloadsOnStart = get(.openDownloadsOnStart, d.openDownloadsOnStart)
        httpsUpgrade = get(.httpsUpgrade, d.httpsUpgrade)
        fingerprintProtection = get(.fingerprintProtection, d.fingerprintProtection)
        restoreSession = get(.restoreSession, d.restoreSession)
        keepSessionCookies = get(.keepSessionCookies, d.keepSessionCookies)
        discardIdleTabsMinutes = get(.discardIdleTabsMinutes, d.discardIdleTabsMinutes)
        autoUpdateLists = get(.autoUpdateLists, d.autoUpdateLists)
        didOfferLists = get(.didOfferLists, d.didOfferLists)
        enabledLists = get(.enabledLists, d.enabledLists)
        customRules = get(.customRules, d.customRules)
        newTab = get(.newTab, d.newTab)
        windowOpacity = get(.windowOpacity, d.windowOpacity)
        alwaysOnTop = get(.alwaysOnTop, d.alwaysOnTop)
        pageFilter = get(.pageFilter, d.pageFilter)
        pageFont = get(.pageFont, d.pageFont)
        linkStyle = get(.linkStyle, d.linkStyle)
        selectionColor = get(.selectionColor, d.selectionColor)
        smoothScroll = get(.smoothScroll, d.smoothScroll)
        hideScrollbars = get(.hideScrollbars, d.hideScrollbars)
        roundImages = get(.roundImages, d.roundImages)
        blurImages = get(.blurImages, d.blurImages)
        dimPages = get(.dimPages, d.dimPages)
        dockTabCount = get(.dockTabCount, d.dockTabCount)
        confirmQuit = get(.confirmQuit, d.confirmQuit)
        downloadSound = get(.downloadSound, d.downloadSound)
        reduceMotion = get(.reduceMotion, d.reduceMotion)
        forceSelect = get(.forceSelect, d.forceSelect)
        readableText = get(.readableText, d.readableText)
        grayImages = get(.grayImages, d.grayImages)
        stripTracking = get(.stripTracking, d.stripTracking)
        opsecWebRTC = get(.opsecWebRTC, d.opsecWebRTC)
        opsecBeacons = get(.opsecBeacons, d.opsecBeacons)
        opsecReferrer = get(.opsecReferrer, d.opsecReferrer)
        opsecHardware = get(.opsecHardware, d.opsecHardware)
        hideFromCapture = get(.hideFromCapture, d.hideFromCapture)
        denyMedia = get(.denyMedia, d.denyMedia)
    }

    /// Set one setting by its JSON key (used by the settings page). Returns false if the key/value is invalid.
    @discardableResult
    public mutating func set(key: String, value: Any) -> Bool {
        guard let encoded = try? JSONEncoder().encode(self),
              var dict = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any],
              dict[key] != nil,
              JSONSerialization.isValidJSONObject([key: value]) else { return false }
        dict[key] = value
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else { return false }
        self = decoded
        return true
    }
}

public struct HistoryEntry: Codable, Equatable {
    public var id: UUID
    public var url: String
    public var title: String
    public var date: Date
    public init(id: UUID = UUID(), url: String, title: String, date: Date = Date()) {
        self.id = id; self.url = url; self.title = title; self.date = date
    }
}

public struct Bookmark: Codable, Equatable {
    public var id: UUID
    public var url: String
    public var title: String
    public var date: Date
    public init(id: UUID = UUID(), url: String, title: String, date: Date = Date()) {
        self.id = id; self.url = url; self.title = title; self.date = date
    }
}

public struct DownloadRecord: Codable, Equatable {
    public var id: UUID
    public var name: String
    public var source: String
    public var path: String
    public var date: Date
    public var state: String            // running | done | failed
    public init(id: UUID = UUID(), name: String, source: String, path: String, date: Date = Date(), state: String) {
        self.id = id; self.name = name; self.source = source; self.path = path; self.date = date; self.state = state
    }
}

public struct SavedTab: Codable, Equatable {
    public var url: String
    public var title: String
    public init(url: String, title: String) { self.url = url; self.title = title }
}

public struct SessionState: Codable, Equatable {
    public var tabs: [SavedTab] = []
    public var active: Int = 0
    public init() {}
}

public struct BlockerMeta: Codable, Equatable {
    public var networkRules = 0
    public var cosmeticRules = 0
    public var skippedRules = 0
    public var failedChunks = 0
    public var updated: [String: Date] = [:]     // list id -> last download time
    public init() {}
}
