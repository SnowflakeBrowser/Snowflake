import Foundation
import WebKit
import VeilCore

struct FilterListSource {
    let id: String
    let name: String
    let blurb: String
    let url: URL?
    let defaultOn: Bool
}

/// Compiles filter lists into WKContentRuleLists (WebKit's native, in-engine blocker) and
/// hands the right lists to each tab. Compiled lists are cached by WebKit so startup is instant.
final class BlockerManager {
    static let sources: [FilterListSource] = [
        .init(id: "builtin", name: "Veil essentials", blurb: "Built-in ad and tracker domains. Works offline.", url: nil, defaultOn: true),
        .init(id: "easylist", name: "EasyList", blurb: "Ads on most websites.", url: URL(string: "https://easylist.to/easylist/easylist.txt"), defaultOn: true),
        .init(id: "easyprivacy", name: "EasyPrivacy", blurb: "Trackers and analytics.", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt"), defaultOn: true),
        .init(id: "ubo-filters", name: "uBlock Origin filters", blurb: "uBlock Origin's own ad rules (network and element-hiding parts).", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/filters.txt"), defaultOn: true),
        .init(id: "ubo-privacy", name: "uBlock Origin privacy", blurb: "uBlock Origin's tracker rules.", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/privacy.txt"), defaultOn: true),
        .init(id: "ubo-badware", name: "uBlock Origin badware", blurb: "Malicious and scam domains.", url: URL(string: "https://ublockorigin.github.io/uAssets/filters/badware.txt"), defaultOn: true),
        .init(id: "annoyances", name: "Cookie banners and annoyances", blurb: "Hides cookie banners, popups and newsletter nags. May hide parts of some pages.", url: URL(string: "https://easylist.to/easylist/fanboy-annoyance.txt"), defaultOn: true),
    ]

    let meta = JSONStore<BlockerMeta>(name: "blocker-meta", defaultValue: BlockerMeta())
    private(set) var networkLists: [WKContentRuleList] = []
    private(set) var cookieList: WKContentRuleList?
    private(set) var generation = 0
    private var isReady = false
    private var waiting: [() -> Void] = []

    private var listsDir: URL {
        let d = Paths.dataDirectory.appendingPathComponent("lists", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func file(_ id: String) -> URL { listsDir.appendingPathComponent(id + ".txt") }
    func isEnabled(_ s: FilterListSource) -> Bool { Services.shared.settings.enabledLists[s.id] ?? s.defaultOn }

    // MARK: Readiness (tabs wait so the first page load is never unblocked)

    func whenReady(_ block: @escaping () -> Void) {
        if isReady { block() } else { waiting.append(block) }
    }
    private func markReady() {
        generation += 1
        isReady = true
        let pending = waiting; waiting = []
        pending.forEach { $0() }
        Services.shared.notifyChanged()
    }

    // MARK: Startup

    /// Fast path: reuse lists WebKit compiled on a previous run. Falls back to compiling.
    func loadCached() {
        let store = WKContentRuleListStore.default()!
        store.getAvailableContentRuleListIdentifiers { [weak self] ids in
            guard let self = self else { return }
            let wanted = (ids ?? []).filter { $0.hasPrefix("veil-") }
            guard wanted.contains("veil-net") else { self.rebuild(); return }
            var found: [String: WKContentRuleList] = [:]
            let group = DispatchGroup()
            for id in wanted {
                group.enter()
                store.lookUpContentRuleList(forIdentifier: id) { list, _ in
                    if let list = list { found[id] = list }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.networkLists = found.keys.filter { $0 == "veil-net" || $0.hasPrefix("veil-cos-") }
                    .sorted().compactMap { found[$0] }
                self.cookieList = found["veil-cookies"]
                if self.networkLists.isEmpty { self.rebuild() } else { self.markReady() }
            }
        }
    }

    // MARK: Compile

    func rebuild(completion: (() -> Void)? = nil) {
        let settings = Services.shared.settings
        let enabled = BlockerManager.sources.filter { isEnabled($0) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var texts: [String] = []
            for s in enabled {
                if s.id == "builtin" { texts.append(SeedFilters.text) }
                else if let t = try? String(contentsOf: self.file(s.id), encoding: .utf8) { texts.append(t) }
            }
            texts.append(settings.customRules)
            let compiled = FilterCompiler.compile(lists: texts)
            DispatchQueue.main.async { self.install(compiled, completion) }
        }
    }

    private func install(_ c: CompiledFilters, _ done: (() -> Void)?) {
        let store = WKContentRuleListStore.default()!
        var jobs: [(String, String)] = [("veil-net", c.network)]
        if let cookieJSON = cookieRulesJSON() { jobs.append(("veil-cookies", cookieJSON)) }
        for (i, chunk) in c.cosmeticChunks.enumerated() { jobs.append(("veil-cos-\(i)", chunk)) }

        var compiled: [String: WKContentRuleList] = [:]
        var failures = 0
        func finish() {
            self.networkLists = compiled.keys.filter { $0 == "veil-net" || $0.hasPrefix("veil-cos-") }
                .sorted().compactMap { compiled[$0] }
            self.cookieList = compiled["veil-cookies"]
            self.meta.mutate {
                $0.networkRules = c.networkRuleCount; $0.cosmeticRules = c.cosmeticRuleCount
                $0.skippedRules = c.skipped; $0.failedChunks = failures
            }
            // Drop compiled lists from older runs that no longer exist.
            store.getAvailableContentRuleListIdentifiers { ids in
                for id in ids ?? [] where id.hasPrefix("veil-") && compiled[id] == nil {
                    store.removeContentRuleList(forIdentifier: id) { _ in }
                }
            }
            self.markReady()
            done?()
        }
        func next(_ i: Int) {
            guard i < jobs.count else { return finish() }
            store.compileContentRuleList(forIdentifier: jobs[i].0, encodedContentRuleList: jobs[i].1) { list, error in
                if let list = list { compiled[jobs[i].0] = list }
                else { failures += 1; NSLog("Veil: rule chunk \(jobs[i].0) failed: \(String(describing: error))") }
                next(i + 1)
            }
        }
        next(0)
    }

    // MARK: Cookie rules

    func cookieRulesJSON() -> String? {
        let s = Services.shared.settings
        return FilterCompiler.cookieRules(mode: s.cookieMode, exceptions: s.cookieExceptions)
    }

    /// Recompile only the cookie list (used when the cookie mode or exceptions change).
    func recompileCookies() {
        guard let json = cookieRulesJSON() else {
            cookieList = nil
            generation += 1
            Services.shared.notifyChanged()
            return
        }
        WKContentRuleListStore.default()!.compileContentRuleList(forIdentifier: "veil-cookies", encodedContentRuleList: json) { [weak self] list, error in
            guard let self = self else { return }
            if let error = error { NSLog("Veil: cookie rules failed: \(error)") }
            self.cookieList = list
            self.generation += 1
            Services.shared.notifyChanged()
        }
    }

    // MARK: Per-tab state

    func state(forHost host: String?) -> (key: String, lists: [WKContentRuleList]) {
        let s = Services.shared.settings
        let allowed = host.map { Services.shared.allowlist.contains($0) } ?? false
        let key = "\(generation)|\(s.adBlocking)|\(s.cookieMode)|\(allowed)"
        if allowed { return (key, []) }
        var lists: [WKContentRuleList] = []
        if s.adBlocking { lists += networkLists }
        if s.cookieMode != "off", let c = cookieList { lists.append(c) }
        return (key, lists)
    }

    // MARK: Downloading lists (user-initiated; the only third-party network requests Veil makes)

    func downloadLists(completion: @escaping (_ updated: [String], _ failed: [String]) -> Void) {
        let session = URLSession(configuration: .ephemeral)   // no cookies, no cache, no identifiers
        let targets = BlockerManager.sources.filter { isEnabled($0) && $0.url != nil }
        var updated: [String] = [], failed: [String] = []
        let group = DispatchGroup()
        for s in targets {
            group.enter()
            var req = URLRequest(url: s.url!)
            req.timeoutInterval = 30
            session.dataTask(with: req) { data, resp, _ in
                defer { group.leave() }
                guard let data = data, (resp as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8), text.contains("!") else {
                    DispatchQueue.main.async { failed.append(s.name) }; return
                }
                try? text.write(to: self.file(s.id), atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    updated.append(s.name)
                    self.meta.mutate { $0.updated[s.id] = Date() }
                }
            }.resume()
        }
        group.notify(queue: .main) {
            if updated.isEmpty { completion(updated, failed) }
            else { self.rebuild { completion(updated, failed) } }
        }
    }

    func updateIfStale() {
        guard Services.shared.settings.autoUpdateLists else { return }
        let oldest = BlockerManager.sources.filter { $0.url != nil && isEnabled($0) }
            .map { meta.value.updated[$0.id] ?? .distantPast }.min() ?? .distantPast
        if Date().timeIntervalSince(oldest) > 7 * 86_400 { downloadLists { _, _ in } }
    }
}
