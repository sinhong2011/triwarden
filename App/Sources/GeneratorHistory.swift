import Foundation

/// A generated value the person copied or used. Memory only; the history is cleared when the vault locks.
struct GeneratorHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let value: String
    /// `password`, `passphrase`, `username` or `pin` (GeneratorView.Mode's raw values; SSH keys are never kept).
    let kind: String
    let date: Date
    /// The site it was made for, when the browser extension asked for it (so a password whose save was missed can be
    /// found again by where it was used).
    var site: String? = nil
}

/// The rules for the generator's history, kept apart from AppModel so they can be tested on their own.
enum GeneratorHistory {
    /// Oldest entries drop off past this many.
    static let limit = 50

    /// `history` with `value` added at the top. An empty value, or the same value as the newest entry, changes nothing.
    static func remembering(_ value: String, kind: String, site: String? = nil, date: Date = .now,
                            in history: [GeneratorHistoryEntry]) -> [GeneratorHistoryEntry] {
        guard !value.isEmpty, history.first?.value != value else { return history }
        var updated = history
        updated.insert(GeneratorHistoryEntry(value: value, kind: kind, date: date, site: site), at: 0)
        if updated.count > limit { updated.removeLast(updated.count - limit) }
        return updated
    }

    /// The host of the page the extension asked from, for display. Nil for anything that isn't a web page.
    static func site(fromPageURL url: String?) -> String? {
        guard let url, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              let host = parsed.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
