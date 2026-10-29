import Foundation

/// Formats reference metadata only. This type never resolves a vault value or grants access.
public enum SavedToolCommands {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    public static func launch(_ profile: SecretsProfile) throws -> String {
        try profile.validate()
        return "tw run --profile " + profile.name
    }

    public static func alias(_ profile: SecretsProfile) throws -> String {
        let command = try launch(profile)
        return "alias " + aliasName(profile) + "=" + shellQuote(command)
    }

    /// The short name the suggested alias defines, such as `tw-my-assistant`.
    public static func aliasName(_ profile: SecretsProfile) -> String {
        let words = profile.title.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted)
            .filter { !$0.isEmpty }
        let slug = String(words.joined(separator: "-").prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // A prefix avoids common built-in names. The user must select a different name for duplicate titles.
        return "tw-" + (slug.isEmpty ? profile.name : slug)
    }

    public static func validateListArguments(_ arguments: [String]) throws {
        guard arguments.isEmpty || arguments == ["list"] else {
            throw SecretsFailure("usage: tw tools list\nOpen Tools in Triwarden to save or edit a tool.")
        }
    }

    public static func list(_ profiles: [SecretsProfile]) throws -> String {
        guard !profiles.isEmpty else { return "No saved tools. Open Tools in Triwarden to add a tool." }
        // Stable ordering and IDs disambiguate tools that have the same display name.
        return try profiles.sorted { $0.name < $1.name }.map { profile in
            let command = try launch(profile)
            return profile.title + (profile.enabled ? "" : " (paused)") + "\n  " + command
        }.joined(separator: "\n\n")
    }
}
