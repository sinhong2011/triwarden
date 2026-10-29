import Foundation

/// Suggestions only. The app saves explicit paths and arguments for the normal approval checks.
public enum ToolLaunchRecipe: String, CaseIterable, Sendable {
    // Coding agents first, then project runners. Only the case order is shown; nothing stores the raw value.
    case claudeCode, codex, gemini, cursorAgent, aider, opencode
    case npm, pnpm, bun, node, python, uv, custom

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .cursorAgent: "Cursor CLI"
        case .aider: "Aider"
        case .opencode: "OpenCode"
        case .npm: "npm development project"
        case .pnpm: "pnpm development project"
        case .bun: "Bun development project"
        case .node: "Node.js script"
        case .python: "Python script"
        case .uv: "Python script with uv"
        case .custom: "Other program"
        }
    }
    public var binary: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        case .cursorAgent: "cursor-agent"
        case .aider: "aider"
        case .opencode: "opencode"
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .bun: "bun"
        case .node: "node"
        case .python: "python3"
        case .uv: "uv"
        case .custom: nil
        }
    }
    /// The variable the program reads its key from. Nil when it depends on the provider the user picks.
    public var variable: String? {
        switch self {
        case .claudeCode: "ANTHROPIC_API_KEY"
        case .codex: "OPENAI_API_KEY"
        case .gemini: "GEMINI_API_KEY"
        case .cursorAgent: "CURSOR_API_KEY"
        case .aider, .opencode, .npm, .pnpm, .bun, .node, .python, .uv, .custom: nil
        }
    }
    /// The recipe runs a script file the user chooses.
    public var needsScript: Bool { self == .node || self == .python || self == .uv }

    public func suggestedName(current: String, previous: Self?) -> String {
        current.isEmpty || current == previous?.title ? title : current
    }

    public func suggestedVariable(current: String, previous: Self?, keyDefault: String) -> String {
        current.isEmpty || current == (previous?.variable ?? keyDefault) ? (variable ?? keyDefault) : current
    }

    public func arguments(script: String, extra: [String]) -> [String] {
        switch self {
        case .npm, .pnpm, .bun: ["run", "dev"] + extra
        case .node, .python: [script] + extra
        case .uv: ["run", script] + extra
        case .claudeCode, .codex, .gemini, .cursorAgent, .aider, .opencode, .custom: extra
        }
    }

    public func candidates(home: URL) -> [String] {
        guard let binary else { return [] }
        return [home.appendingPathComponent(".local/bin/" + binary).path] +
            LaunchPolicy.searchPath.split(separator: ":").map { "\($0)/\(binary)" }
    }

    public func findExecutable(home: URL) -> String? {
        candidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
