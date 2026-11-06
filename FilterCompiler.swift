import Foundation

/// Output of compiling Adblock-Plus-syntax filter lists (EasyList, EasyPrivacy, uBlock Origin's lists)
/// into WebKit content-blocker JSON (WKContentRuleList).
///
/// WebKit's format is far less expressive than uBlock Origin's engine, so this compiler supports the
/// large, well-defined subset that maps cleanly and counts everything else as `skipped`:
///   supported:  `||host^`, `|prefix`, `suffix|`, wildcards, `@@` exceptions, `$third-party`,
///               `$script/image/stylesheet/xmlhttprequest/media/font/subdocument/document/popup`,
///               `$domain=a.com|b.com`, and `##selector` / `domain##selector` element hiding.
///   not supported (skipped): regex filters, `$redirect`, `$removeparam`, `$csp`, `$header`, `$replace`,
///               scriptlets (`+js(...)`), procedural cosmetics (`:has-text`, `:xpath`, ...), `#@#` exceptions.
public struct CompiledFilters {
    /// One JSON array containing all network rules. Kept in ONE list because WebKit's
    /// `ignore-previous-rules` (exceptions) only applies to rules within the same list.
    public var network: String = "[]"
    /// Element-hiding rules, split into several JSON arrays so one bad selector only drops one chunk.
    public var cosmeticChunks: [String] = []
    public var networkRuleCount = 0
    public var cosmeticRuleCount = 0
    public var skipped = 0
    public init() {}
}

public enum FilterCompiler {
    static let maxNetworkRules = 140_000      // WebKit's hard limit is 150,000 per list
    static let selectorsPerRule = 100
    static let rulesPerCosmeticChunk = 500

    enum Parsed {
        case network(rule: [String: Any], allow: Bool, key: String)
        case cosmetic(domains: [String], selector: String)
        case skip
    }

    public static func compile(lists: [String]) -> CompiledFilters {
        var block: [[String: Any]] = []
        var allow: [[String: Any]] = []
        var cosmetic: [String: [String]] = [:]       // "" = generic
        var seen = Set<String>()
        var out = CompiledFilters()

        for text in lists {
            text.enumerateLines { raw, _ in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { return }
                switch parse(line) {
                case .network(let rule, let isAllow, let key):
                    guard seen.insert(key).inserted else { return }
                    if isAllow { allow.append(rule) } else { block.append(rule) }
                case .cosmetic(let domains, let selector):
                    let targets = domains.isEmpty ? [""] : domains.map { $0.lowercased() }
                    for d in targets {
                        let k = d + "##" + selector
                        guard seen.insert(k).inserted else { continue }
                        cosmetic[d, default: []].append(selector)
                    }
                case .skip:
                    out.skipped += 1
                }
            }
        }

        // Exceptions go last: ignore-previous-rules only affects earlier rules in the list.
        let blockBudget = max(0, maxNetworkRules - min(allow.count, maxNetworkRules / 4))
        let rules = Array(block.prefix(blockBudget)) + Array(allow.prefix(maxNetworkRules / 4))
        out.networkRuleCount = rules.count
        out.network = json(rules)

        var cosmeticRules: [[String: Any]] = []
        var selectorCount = 0
        if let generic = cosmetic[""] {
            selectorCount += generic.count
            for batch in chunked(generic, selectorsPerRule) {
                cosmeticRules.append(["trigger": ["url-filter": ".*"],
                                      "action": ["type": "css-display-none", "selector": batch.joined(separator: ", ")]])
            }
        }
        for domain in cosmetic.keys.sorted() where !domain.isEmpty {
            guard domain.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
            let sels = cosmetic[domain] ?? []
            selectorCount += sels.count
            for batch in chunked(sels, selectorsPerRule) {
                cosmeticRules.append(["trigger": ["url-filter": ".*", "if-domain": ["*" + domain]],
                                      "action": ["type": "css-display-none", "selector": batch.joined(separator: ", ")]])
            }
        }
        out.cosmeticRuleCount = selectorCount
        out.cosmeticChunks = chunked(cosmeticRules, rulesPerCosmeticChunk).map(json)
        return out
    }

    // MARK: - Parsing

    static func parse(_ line: String) -> Parsed {
        for marker in ["#@#", "#?#", "#$#", "#%#", "#@$#", "#@?#"] where line.contains(marker) { return .skip }
        if let r = line.range(of: "##") {
            let domPart = String(line[line.startIndex..<r.lowerBound])
            let selector = String(line[r.upperBound...])
            guard isSupportedSelector(selector) else { return .skip }
            let doms = domPart.isEmpty ? [] : domPart.split(separator: ",").map(String.init)
            if doms.contains(where: { $0.hasPrefix("~") || $0.contains("*") || $0.contains("/") }) { return .skip }
            return .cosmetic(domains: doms, selector: selector)
        }
        return parseNetwork(line)
    }

    static let unsupportedSelectorTokens = [
        ":has-text(", ":xpath(", ":matches-css", ":-abp-", ":min-text-length", ":nth-ancestor", ":upward(",
        ":watch-attr", ":others(", ":remove(", ":style(", ":contains(", ":matches-path", ":matches-media",
        "+js(", "::", "{", "}",
    ]

    static func isSupportedSelector(_ s: String) -> Bool {
        guard !s.isEmpty, !s.hasPrefix("+"), !s.hasPrefix("^") else { return false }
        return !unsupportedSelectorTokens.contains { s.contains($0) }
    }

    static let typeMap: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
        "xmlhttprequest": "raw", "xhr": "raw", "media": "media", "font": "font",
        "subdocument": "document", "document": "document", "doc": "document", "popup": "popup",
    ]

    static func parseNetwork(_ line: String) -> Parsed {
        var pattern = line
        var isAllow = false
        if pattern.hasPrefix("@@") { isAllow = true; pattern = String(pattern.dropFirst(2)) }

        var options: [String] = []
        if let idx = pattern.lastIndex(of: "$") {
            let tail = String(pattern[pattern.index(after: idx)...])
            if !tail.isEmpty && !tail.contains("/") {
                options = tail.split(separator: ",").map(String.init)
                pattern = String(pattern[..<idx])
            }
        }
        if pattern.count > 2 && pattern.hasPrefix("/") && pattern.hasSuffix("/") { return .skip }   // regex filter
        if pattern.isEmpty { return .skip }

        var thirdParty: Bool?
        var types: [String] = []
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var caseSensitive = false

        for opt in options {
            var name = opt.lowercased()
            let negated = name.hasPrefix("~")
            if negated { name.removeFirst() }
            if name.hasPrefix("domain=") {
                for d in name.dropFirst(7).split(separator: "|") {
                    var dom = String(d)
                    if dom.contains("*") || dom.contains("/") { return .skip }
                    if dom.hasPrefix("~") { dom.removeFirst(); unlessDomains.append(dom) } else { ifDomains.append(dom) }
                }
                continue
            }
            switch name {
            case "third-party", "3p": thirdParty = !negated
            case "first-party", "1p": thirdParty = negated
            case "important", "all": continue
            case "match-case": caseSensitive = true
            default:
                guard !negated, let mapped = typeMap[name] else { return .skip }   // unsupported option
                if mapped == "document" && isAllow { return .skip }               // whole-site allow: use the Allowlist
                types.append(mapped)
            }
        }
        if !ifDomains.isEmpty && !unlessDomains.isEmpty { return .skip }
        guard let regex = regex(from: pattern) else { return .skip }

        var trigger: [String: Any] = ["url-filter": regex]
        if caseSensitive { trigger["url-filter-is-case-sensitive"] = true }
        if !types.isEmpty { trigger["resource-type"] = Array(Set(types)).sorted() }
        if let tp = thirdParty { trigger["load-type"] = [tp ? "third-party" : "first-party"] }
        if !ifDomains.isEmpty { trigger["if-domain"] = ifDomains.map { "*" + $0 } }
        if !unlessDomains.isEmpty { trigger["unless-domain"] = unlessDomains.map { "*" + $0 } }

        let rule: [String: Any] = ["trigger": trigger,
                                   "action": ["type": isAllow ? "ignore-previous-rules" : "block"]]
        let key = (isAllow ? "@@" : "") + line
        return .network(rule: rule, allow: isAllow, key: key)
    }

    /// ABP pattern -> the restricted regex dialect WebKit accepts (no alternation, no lookahead, no {n}).
    static func regex(from pattern: String) -> String? {
        var p = pattern
        var prefix = ""
        if p.hasPrefix("||") { p.removeFirst(2); prefix = "^[^:/?#]+://([^/?#]*\\.)?" }
        else if p.hasPrefix("|") { p.removeFirst(); prefix = "^" }
        var suffix = ""
        if p.hasSuffix("|") { p.removeLast(); suffix = "$" }
        if p.isEmpty && prefix.isEmpty { return nil }

        var out = ""
        for ch in p {
            guard ch.isASCII else { return nil }
            switch ch {
            case "*": out += ".*"
            case "^": out += "[/:?#&=]"
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "$", "|": out += "\\" + String(ch)
            default: out.append(ch)
            }
        }
        return prefix + out + suffix
    }

    // MARK: - Helpers

    static func chunked<T>(_ array: [T], _ size: Int) -> [[T]] {
        guard size > 0, !array.isEmpty else { return [] }
        return stride(from: 0, to: array.count, by: size).map { Array(array[$0..<min($0 + size, array.count)]) }
    }

    static func json(_ rules: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// Blocks cookies on every third-party request (kept for tests and the default mode).
    public static let thirdPartyCookieRules =
        #"[{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block-cookies"}}]"#

    /// Cookie rules for a mode: "off" (nil), "third-party", or "all" (every cookie blocked except on `exceptions`).
    public static func cookieRules(mode: String, exceptions: [String]) -> String? {
        switch mode {
        case "off":
            return nil
        case "all":
            var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]]]
            let domains = exceptions.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.isASCII } }
                .map { "*" + $0 }
            if !domains.isEmpty {
                rules.append(["trigger": ["url-filter": ".*", "if-domain": domains], "action": ["type": "ignore-previous-rules"]])
            }
            return json(rules)
        default:
            return thirdPartyCookieRules
        }
    }
}
