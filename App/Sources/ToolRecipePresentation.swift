import Foundation
import SecretsAgent

extension ToolLaunchRecipe {
    var localizedTitle: String {
        switch self {
        case .claudeCode: String(localized: "Claude Code")
        case .codex: String(localized: "Codex CLI")
        case .gemini: String(localized: "Gemini CLI")
        case .cursorAgent: String(localized: "Cursor CLI")
        case .aider: String(localized: "Aider")
        case .opencode: String(localized: "OpenCode")
        case .npm: String(localized: "npm development project")
        case .pnpm: String(localized: "pnpm development project")
        case .bun: String(localized: "Bun development project")
        case .node: String(localized: "Node.js script")
        case .python: String(localized: "Python script")
        case .uv: String(localized: "Python script with uv")
        case .custom: String(localized: "Other program")
        }
    }

    /// What the recipe runs, in the user's words, shown under the picker.
    var localizedNote: String? {
        switch self {
        case .claudeCode: String(localized: "Use an Anthropic API key. Claude Code can charge this API account instead of your subscription.")
        case .codex: String(localized: "Use an OpenAI API key. Codex can charge this API account instead of your ChatGPT plan.")
        case .gemini: String(localized: "Use a Gemini API key from Google AI Studio.")
        case .cursorAgent: String(localized: "Use a Cursor API key from your Cursor dashboard.")
        case .aider: String(localized: "Aider works with many providers. Use the variable for yours, such as ANTHROPIC_API_KEY or OPENAI_API_KEY.")
        case .opencode: String(localized: "OpenCode works with many providers. Use the variable for yours, such as ANTHROPIC_API_KEY or OPENAI_API_KEY.")
        case .npm: String(localized: "Runs npm run dev in this folder.")
        case .pnpm: String(localized: "Runs pnpm run dev in this folder.")
        case .bun: String(localized: "Runs bun run dev in this folder.")
        case .uv: String(localized: "Runs uv run with your script, so the project's dependencies are used.")
        case .node, .python, .custom: nil
        }
    }

    /// The launch can bill an API account rather than the user's subscription.
    var billsAPIAccount: Bool { self == .claudeCode || self == .codex }
}
