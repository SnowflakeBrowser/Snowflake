import XCTest
@testable import VeilCore

final class FilterCompilerTests: XCTestCase {
    private func rules(_ json: String) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] ?? []
    }
    private func action(_ r: [String: Any]) -> String { (r["action"] as? [String: Any])?["type"] as? String ?? "" }
    private func trigger(_ r: [String: Any]) -> [String: Any] { r["trigger"] as? [String: Any] ?? [:] }

    func testDomainBlockRule() {
        let out = FilterCompiler.compile(lists: ["||ads.example.com^"])
        let r = rules(out.network)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(action(r[0]), "block")
        XCTAssertEqual(trigger(r[0])["url-filter"] as? String, "^[^:/?#]+://([^/?#]*\\.)?ads\\.example\\.com[/:?#&=]")
    }

    func testExceptionsComeLastAndIgnorePrevious() {
        let out = FilterCompiler.compile(lists: ["@@||good.example.com^", "||example.com^"])
        let r = rules(out.network)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(action(r[0]), "block")
        XCTAssertEqual(action(r[1]), "ignore-previous-rules")
    }

    func testOptions() {
        let out = FilterCompiler.compile(lists: ["||t.example.net^$third-party,script,domain=a.com|b.com"])
        let t = trigger(rules(out.network)[0])
        XCTAssertEqual(t["load-type"] as? [String], ["third-party"])
        XCTAssertEqual(t["resource-type"] as? [String], ["script"])
        XCTAssertEqual(t["if-domain"] as? [String], ["*a.com", "*b.com"])
    }

    func testUnsupportedRulesAreSkippedNotMangled() {
        let out = FilterCompiler.compile(lists: [
            "||x.com^$redirect=noop.js", "/banner\\d+/", "example.com##+js(abort-on-property-read, foo)",
            "example.com##div:has-text(Ad)", "example.com#@#.ad",
        ])
        XCTAssertEqual(out.networkRuleCount, 0)
        XCTAssertEqual(out.cosmeticRuleCount, 0)
        XCTAssertEqual(out.skipped, 5)
    }

    func testCosmeticRules() {
        let out = FilterCompiler.compile(lists: ["##.ad-banner", "news.example.com##.promo"])
        XCTAssertEqual(out.cosmeticRuleCount, 2)
        let all = out.cosmeticChunks.flatMap { rules($0) }
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { (trigger($0)["if-domain"] as? [String]) == ["*news.example.com"] })
    }

    func testCommentsAndDuplicatesIgnored() {
        let out = FilterCompiler.compile(lists: ["! comment\n[Adblock Plus 2.0]\n||a.com^\n||a.com^"])
        XCTAssertEqual(out.networkRuleCount, 1)
    }

    func testSeedListCompiles() {
        let out = FilterCompiler.compile(lists: [SeedFilters.text])
        XCTAssertGreaterThan(out.networkRuleCount, 20)
        XCTAssertGreaterThan(out.cosmeticRuleCount, 0)
    }
}

final class CookieRuleTests: XCTestCase {
    func testModes() {
        XCTAssertNil(FilterCompiler.cookieRules(mode: "off", exceptions: []))
        XCTAssertEqual(FilterCompiler.cookieRules(mode: "third-party", exceptions: []), FilterCompiler.thirdPartyCookieRules)
        let all = FilterCompiler.cookieRules(mode: "all", exceptions: ["Google.com", " "]) ?? ""
        XCTAssertTrue(all.contains("block-cookies"))
        XCTAssertTrue(all.contains("ignore-previous-rules"))
        XCTAssertTrue(all.contains("*google.com"))
    }
}

final class URLResolverTests: XCTestCase {
    private let t = "https://duckduckgo.com/?q=%s"
    private func r(_ s: String) -> String { URLResolver.resolve(s, searchTemplate: t).absoluteString }

    func testBareHostGetsHTTPS() { XCTAssertEqual(r("example.com"), "https://example.com") }
    func testPathKept() { XCTAssertEqual(r("example.com/a?b=1"), "https://example.com/a?b=1") }
    func testExplicitURLUntouched() { XCTAssertEqual(r("https://a.b/c"), "https://a.b/c") }
    func testLocalhostIsHTTP() { XCTAssertEqual(r("localhost:3000"), "http://localhost:3000") }
    func testIPIsHTTP() { XCTAssertEqual(r("192.168.1.1"), "http://192.168.1.1") }
    func testSearch() { XCTAssertEqual(r("hello world"), "https://duckduckgo.com/?q=hello%20world") }
    func testSpaceBeatsDot() { XCTAssertTrue(r("foo.bar baz").hasPrefix("https://duckduckgo.com/")) }
    func testEmptyIsNewTab() { XCTAssertEqual(r("  "), "veil://newtab") }
    func testDisplayString() {
        XCTAssertEqual(URLResolver.displayString(for: URL(string: "https://www.example.com/")!), "example.com")
    }
}

final class StoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testJSONStorePersistsAcrossInstances() {
        let d = tempDir()
        let a = JSONStore<[String]>(name: "x", directory: d, defaultValue: [])
        a.value = ["one", "two"]
        a.flush()
        let b = JSONStore<[String]>(name: "x", directory: d, defaultValue: [])
        XCTAssertEqual(b.value, ["one", "two"])
    }

    func testAllowlistMatchesSubdomains() {
        let a = AllowlistStore(directory: tempDir())
        a.add("www.Example.com")
        XCTAssertTrue(a.contains("example.com"))
        XCTAssertTrue(a.contains("news.example.com"))
        XCTAssertFalse(a.contains("notexample.com"))
        a.remove("example.com")
        XCTAssertFalse(a.contains("example.com"))
    }

    func testSettingsSetAndMissingKeysDecode() {
        var s = Settings()
        XCTAssertTrue(s.set(key: "verticalTabs", value: true))
        XCTAssertTrue(s.verticalTabs)
        XCTAssertFalse(s.set(key: "nope", value: 1))
        let old = try? JSONDecoder().decode(Settings.self, from: Data("{\"theme\":\"light\"}".utf8))
        XCTAssertEqual(old?.theme, "light")
        XCTAssertEqual(old?.cookieMode, "third-party")     // defaults fill in
        XCTAssertEqual(old?.mouseNavButtons, true)
    }

    func testHistoryDedupesConsecutiveVisits() {
        let h = HistoryStore(directory: tempDir())
        h.add(url: "https://a.com", title: "A"); h.add(url: "https://a.com", title: "A2")
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h.search("a2").count, 1)
    }
}
