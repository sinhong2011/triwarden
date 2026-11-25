import Foundation

/// The vault window's search filters: what the list is narrowed to besides the typed text. Saved between launches.
///
/// Each one can be typed as a token in the search field — `type:card` (or `type:bank`, `type:license`, `type:passport`), `is:favorite`, `has:otp`, `has:passkey`,
/// `is:weak`, `folder:Work` (or `#Work`), `vault:personal` — or picked from the filter menu.
public struct SearchFilters: Codable, Equatable, Sendable {
    public enum ItemType: String, Codable, CaseIterable, Sendable { case login, card, identity, note, sshKey, bankAccount, driversLicense, passport }

    public var type: ItemType?
    /// A folder path, as the sidebar shows it ("Work/Servers"); its subfolders count too.
    public var folder: String?
    public var favorites = false
    public var hasCode = false
    public var hasPasskey = false
    /// Flagged by Watchtower (weak, reused or exposed password).
    public var hasIssue = false

    public init(type: ItemType? = nil, folder: String? = nil, favorites: Bool = false, hasCode: Bool = false,
                hasPasskey: Bool = false, hasIssue: Bool = false) {
        self.type = type
        self.folder = folder
        self.favorites = favorites
        self.hasCode = hasCode
        self.hasPasskey = hasPasskey
        self.hasIssue = hasIssue
    }

    public var isEmpty: Bool { self == SearchFilters() }

    /// How many filters are on.
    public var count: Int {
        [type != nil, folder != nil, favorites, hasCode, hasPasskey, hasIssue].filter { $0 }.count
    }

    /// Turns a token's filter on (a vault token is the caller's: the vault switcher holds it).
    public mutating func apply(_ token: SearchToken) {
        switch token {
        case .type(let t): type = t
        case .folder(let f): folder = f
        case .favorites: favorites = true
        case .hasCode: hasCode = true
        case .hasPasskey: hasPasskey = true
        case .hasIssue: hasIssue = true
        case .vault: break
        }
    }

    /// Turns a token's filter off.
    public mutating func remove(_ token: SearchToken) {
        switch token {
        case .type: type = nil
        case .folder: folder = nil
        case .favorites: favorites = false
        case .hasCode: hasCode = false
        case .hasPasskey: hasPasskey = false
        case .hasIssue: hasIssue = false
        case .vault: break
        }
    }

    /// The filters that are on, as tokens, in the order the chips show them.
    public var tokens: [SearchToken] {
        var out: [SearchToken] = []
        if let type { out.append(.type(type)) }
        if let folder { out.append(.folder(folder)) }
        if favorites { out.append(.favorites) }
        if hasCode { out.append(.hasCode) }
        if hasPasskey { out.append(.hasPasskey) }
        if hasIssue { out.append(.hasIssue) }
        return out
    }

    // MARK: Saving

    public static let defaultsKey = "vaultSearchFilters"

    public static func load(from defaults: UserDefaults = .standard) -> SearchFilters {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(SearchFilters.self, from: $0) } ?? SearchFilters()
    }

    public func save(to defaults: UserDefaults = .standard) {
        if isEmpty { defaults.removeObject(forKey: Self.defaultsKey) } else { defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey) }
    }
}

/// One filter typed into the search field.
public enum SearchToken: Hashable, Sendable {
    case type(SearchFilters.ItemType)
    /// A folder name as typed; the caller matches it to a folder.
    case folder(String)
    /// A vault as typed: "personal", or an organization's name; the caller matches it.
    case vault(String)
    case favorites, hasCode, hasPasskey, hasIssue

    /// The canonical way to type it.
    public var text: String {
        switch self {
        case .type(let t): "type:" + Self.typeNames[t]!
        case .folder(let f): "folder:" + Self.quoted(f)
        case .vault(let v): "vault:" + Self.quoted(v)
        case .favorites: "is:favorite"
        case .hasCode: "has:otp"
        case .hasPasskey: "has:passkey"
        case .hasIssue: "is:weak"
        }
    }

    private static let typeNames: [SearchFilters.ItemType: String] = [
        .login: "login", .card: "card", .identity: "identity", .note: "note", .sshKey: "ssh",
        .bankAccount: "bank", .driversLicense: "license", .passport: "passport",
    ]
    private static let types: [String: SearchFilters.ItemType] = [
        "login": .login, "logins": .login, "password": .login, "passwords": .login,
        "card": .card, "cards": .card,
        "identity": .identity, "identities": .identity, "id": .identity,
        "note": .note, "notes": .note, "securenote": .note,
        "ssh": .sshKey, "sshkey": .sshKey, "sshkeys": .sshKey, "key": .sshKey, "keys": .sshKey,
        "bank": .bankAccount, "banks": .bankAccount, "bankaccount": .bankAccount, "bankaccounts": .bankAccount,
        "license": .driversLicense, "licenses": .driversLicense, "licence": .driversLicense, "licences": .driversLicense,
        "driverslicense": .driversLicense, "driverslicence": .driversLicense, "driverlicense": .driversLicense,
        "driverlicence": .driversLicense, "dl": .driversLicense,
        "passport": .passport, "passports": .passport,
    ]

    private static func quoted(_ s: String) -> String { s.contains(" ") ? "\"\(s)\"" : s }

    /// Reads one word (quotes already taken off its value) as a token, or nil when it's plain search text.
    public init?(_ word: String) {
        if word.count > 1, word.hasPrefix("#") {
            self = .folder(String(word.dropFirst()))
            return
        }
        guard let colon = word.firstIndex(of: ":") else { return nil }
        let key = word[..<colon].lowercased()
        var value = String(word[word.index(after: colon)...])
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        let v = value.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        switch key {
        case "type", "kind", "t":
            guard let t = Self.types[v] else { return nil }
            self = .type(t)
        case "folder", "f":
            guard !value.isEmpty else { return nil }
            self = .folder(value)
        case "vault", "org", "in", "v":
            guard !value.isEmpty else { return nil }
            self = .vault(value)
        case "is", "has":
            switch v {
            case "fav", "favorite", "favourite", "favorites", "favourites", "starred", "star": self = .favorites
            case "otp", "totp", "code", "codes", "2fa", "onetimecode": self = .hasCode
            case "passkey", "passkeys", "fido2", "webauthn": self = .hasPasskey
            case "weak", "reused", "exposed", "breached", "issue", "issues", "risk", "risky", "watchtower": self = .hasIssue
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Splits typed text into words, keeping a quoted value whole (`folder:"Home Office"`). An unclosed quote runs to
    /// the end.
    public static func words(_ raw: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        for c in raw {
            if c == "\"" { quoted.toggle(); current.append(c) } else if c == " " && !quoted {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Finished tokens in typed text, and what's left as search text. A token counts as finished once a space follows
    /// it (`finishedOnly`), so `type:c` isn't taken while it's still being typed. `accepts` can turn one down (a
    /// folder that doesn't exist): it stays text.
    public static func extract(from raw: String, finishedOnly: Bool = true,
                               accepts: (SearchToken) -> Bool = { _ in true }) -> (tokens: [SearchToken], text: String) {
        var words = Self.words(raw)
        var last: String?
        if finishedOnly, !raw.hasSuffix(" ") || raw.filter({ $0 == "\"" }).count % 2 == 1, !words.isEmpty {
            last = words.removeLast()
        }
        var tokens: [SearchToken] = []
        var kept: [String] = []
        for word in words {
            if let token = SearchToken(word), accepts(token) { tokens.append(token) } else { kept.append(word) }
        }
        var text = kept.joined(separator: " ")
        if let last { text += (text.isEmpty ? "" : " ") + last } else if finishedOnly, !text.isEmpty, raw.hasSuffix(" ") { text += " " }
        return (tokens, text)
    }
}
