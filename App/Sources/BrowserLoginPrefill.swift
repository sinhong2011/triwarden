import Foundation

/// User-facing name and website derived from an allowed browser's front tab.
struct BrowserLoginPrefill: Equatable {
    let name: String
    let uri: String

    init?(isBrowser: Bool, host: String?, pageURL: URL?) {
        guard isBrowser, let host, !host.isEmpty else { return nil }
        name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        uri = pageURL?.absoluteString ?? "https://" + host
    }
}

/// A website trimmed to the site itself: "https://example.com/login?next=…" becomes "https://example.com".
///
/// Keeps the scheme exactly as written (http stays http, no scheme stays none), the host as written (www included:
/// matching already treats a site and its subdomains alike), and any port. Drops sign-in details, path, query and
/// fragment. Only web addresses are changed; app links such as `androidapp://` are left alone.
enum WebsiteSiteOnly {
    /// The site-only form of `text`, or nil when there is nothing to remove (or it isn't a web address).
    static func trimmed(_ text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let hasScheme = raw.contains("://")
        guard var parts = URLComponents(string: hasScheme ? raw : "https://" + raw) else { return nil }
        guard let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.percentEncodedHost, !host.isEmpty else { return nil }
        let extra = !(parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/")
            || parts.percentEncodedQuery != nil || parts.percentEncodedFragment != nil
            || parts.percentEncodedUser != nil || parts.percentEncodedPassword != nil
        guard extra else { return nil }
        parts.percentEncodedUser = nil
        parts.percentEncodedPassword = nil
        parts.percentEncodedPath = ""
        parts.percentEncodedQuery = nil
        parts.percentEncodedFragment = nil
        guard let site = parts.string else { return nil }
        return hasScheme ? site : String(site.dropFirst("https://".count))
    }

    /// `text` trimmed to the site, or unchanged when there is nothing to trim.
    static func apply(_ text: String) -> String { trimmed(text) ?? text }
}
