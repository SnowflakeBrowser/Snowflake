import Foundation

/// Removes well-known tracking parameters (utm_*, fbclid, gclid ...) from web addresses.
public enum TrackingParams {
    private static let exact: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "wbraid", "gbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid",
        "mc_eid", "mc_cid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id", "ref_src", "ref_url",
    ]
    private static let prefixes = ["utm_", "pk_", "mtm_", "hsa_"]

    public static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return exact.contains(n) || prefixes.contains { n.hasPrefix($0) }
    }

    /// The address without tracking parameters, or nil when there was nothing to remove.
    public static func cleaned(_ url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = c.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !isTracking($0.name) }
        if kept.count == items.count { return nil }
        c.queryItems = kept.isEmpty ? nil : kept
        return c.url
    }
}
