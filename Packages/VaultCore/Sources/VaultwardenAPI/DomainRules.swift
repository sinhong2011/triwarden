import Foundation

/// The account's equivalent-domain rules (`settings/domains`): the groups you made yourself, and Bitwarden's
/// built-in groups with whether each is turned off. Sites in one group share sign-ins.
public struct DomainRules: Sendable, Equatable {
    /// One of the server's built-in groups. `type` is how the server names it; there is no title.
    public struct BuiltInGroup: Sendable, Equatable, Identifiable {
        public let type: Int
        public let domains: [String]
        /// Turned off for this account: its sites no longer share sign-ins.
        public var excluded: Bool
        public var id: Int { type }

        public init(type: Int, domains: [String], excluded: Bool) {
            self.type = type
            self.domains = domains
            self.excluded = excluded
        }
    }

    /// Your own groups, each a list of hosts.
    public var custom: [[String]]
    public var builtIn: [BuiltInGroup]

    public init(custom: [[String]], builtIn: [BuiltInGroup]) {
        self.custom = custom
        self.builtIn = builtIn
    }

    /// From the server's answer, in camelCase or PascalCase.
    public init(json: [String: Any]) {
        let root = CipherEditor.normalize(json) as? [String: Any] ?? [:]
        let custom = (root["equivalentDomains"] as? [Any] ?? []).compactMap { group -> [String]? in
            let list = (group as? [Any])?.compactMap { $0 as? String } ?? []
            return list.isEmpty ? nil : list.map { $0.lowercased() }
        }
        let builtIn = (root["globalEquivalentDomains"] as? [Any] ?? []).compactMap { any -> BuiltInGroup? in
            guard let group = any as? [String: Any], let type = (group["type"] as? NSNumber)?.intValue else { return nil }
            let domains = (group["domains"] as? [Any] ?? []).compactMap { ($0 as? String)?.lowercased() }
            return BuiltInGroup(type: type, domains: domains, excluded: (group["excluded"] as? Bool) ?? false)
        }
        self.init(custom: custom, builtIn: builtIn)
    }

    /// From a sync payload's `domains`, when it has one.
    public init?(syncData: Data) {
        guard let root = CipherEditor.normalize(try? JSONSerialization.jsonObject(with: syncData)) as? [String: Any],
              let domains = root["domains"] as? [String: Any] else { return nil }
        self.init(json: domains)
    }

    /// The built-in groups turned off, by type.
    public var excludedBuiltInTypes: [Int] { builtIn.filter(\.excluded).map(\.type).sorted() }

    /// What `PUT settings/domains` takes: your groups (hosts normalized, duplicates and groups of one dropped) and
    /// the built-in types turned off.
    public var body: [String: Any] {
        ["equivalentDomains": Self.cleaned(custom), "excludedGlobalEquivalentDomains": excludedBuiltInTypes]
    }

    /// Groups as they should be saved: every entry normalized, invalid ones and repeats dropped, groups of fewer
    /// than two sites left out.
    public static func cleaned(_ groups: [[String]]) -> [[String]] {
        groups.compactMap { group in
            var seen = Set<String>()
            let hosts = group.compactMap(normalizedHost).filter { seen.insert($0).inserted }
            return hosts.count > 1 ? hosts : nil
        }
    }

    /// A site from what someone typed or pasted: `https://www.Example.com/login` → `example.com`. A leading `www.` is
    /// dropped: whoever pastes www.apple.com means apple.com, and a group's site already covers its subdomains (the
    /// built-in groups list bare domains too). Nil when it isn't a site address (no dot, spaces, odd characters).
    public static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let end = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<end]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        if let colon = text.lastIndex(of: ":") { text = String(text[..<colon]) }
        if text.hasPrefix("*.") { text.removeFirst(2) }
        while text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix("www."), text.dropFirst(4).contains(".") { text.removeFirst(4) }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, text.count <= 253 else { return nil }
        for label in labels {
            guard (1...63).contains(label.count), label.first != "-", label.last != "-",
                  label.allSatisfy({ $0 == "-" || $0.isLetter || $0.isNumber }) else { return nil }
        }
        return text
    }
}

extension VaultClient {
    /// The account's equivalent-domain rules.
    public func domainRules() async throws(APIError) -> DomainRules {
        DomainRules(json: try await callJSON("GET", "settings/domains"))
    }

    /// Replaces the account's own groups and which built-in groups are off.
    public func saveDomainRules(_ rules: DomainRules) async throws(APIError) {
        try await call("PUT", "settings/domains", json: rules.body)
    }
}
