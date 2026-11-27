import Foundation

/// The providers a "Sign in with" login can name. The browser extension detects the button; the app only accepts these.
/// Saved as a text custom field ("Sign in with" = "Google"), readable in any Bitwarden client and kept by exports.
enum SignInProvider: String, CaseIterable, Sendable {
    case google, apple, microsoft, github, facebook, x, amazon, discord, slack, linkedin, gitlab, twitch

    static let fieldName = "Sign in with"

    var displayName: String {
        switch self {
        case .google: "Google"
        case .apple: "Apple"
        case .microsoft: "Microsoft"
        case .github: "GitHub"
        case .facebook: "Facebook"
        case .x: "X"
        case .amazon: "Amazon"
        case .discord: "Discord"
        case .slack: "Slack"
        case .linkedin: "LinkedIn"
        case .gitlab: "GitLab"
        case .twitch: "Twitch"
        }
    }

    /// A field value typed by hand or by another client: "Google", "google", "Sign in with Apple".
    init?(fieldValue: String) {
        var value = fieldValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("sign in with ") { value.removeFirst("sign in with ".count) }
        if value == "twitter" { value = "x" }
        guard let match = Self.allCases.first(where: { $0.rawValue == value || $0.displayName.lowercased() == value })
        else { return nil }
        self = match
    }

    /// Short, one address, no spaces: what an account chooser shows. Anything else from a page is dropped.
    static func isEmail(_ s: String) -> Bool {
        s.count <= 254 && s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
