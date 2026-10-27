import Darwin
import Foundation
import SSHAgent

// `tw` — talks to the running Triwarden app. Secrets need the vault unlocked and an approval
// (Touch ID or the Mac password) in the app.

let usage = """
usage: tw <command> [arguments]

  status                    whether the vault is unlocked
  list [query]              items (name, username/site); needs approval
  get <item> [--field F]    print a field: password (default), username, uri, notes, totp, or a custom field
  code <item>               print the current one-time code
  generate [--length N]     a new random password (works while locked)
  lock                      lock every account
  install-chrome <id>       register tw as the native host for the Chrome/Edge/Brave extension
  install-firefox           register tw as the native host for the Firefox extension

<item> is an item id, an exact name, or a unique part of a name, username or site.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("tw: \(message)\n".utf8))
    exit(code)
}

let socket = ProcessInfo.processInfo.environment["TW_SOCKET"] ?? BridgeClient.defaultSocketPath
let chromeHost = "io.github.sinhong2011.triwarden"
/// The Firefox add-on id. It must equal `browser_specific_settings.gecko.id` in
/// BrowserExtension/WebExtension/wxt.config.ts (scripts/test-install-chrome-path.py checks that).
let firefoxExtensionID = "triwarden@sinhong2011.github.io"

/// Chrome starts the host with the extension's origin; Firefox with the host manifest's path, then the add-on id.
func startedByBrowser(_ arguments: [String]) -> Bool {
    guard let first = arguments.first else { return false }
    return first.hasPrefix("chrome-extension://") || first.hasSuffix("/\(chromeHost).json")
}

/// Browser native messaging (Chrome and Firefox): messages are 4-byte little-endian length + JSON on stdin/stdout.
func nativeMessagingLoop() -> Never {
    let input = FileHandle.standardInput, output = FileHandle.standardOutput
    while let header = try? input.read(upToCount: 4), header.count == 4 {
        let length = Int(header[0]) | Int(header[1]) << 8 | Int(header[2]) << 16 | Int(header[3]) << 24
        guard length > 0, length < 1_048_576, let body = try? input.read(upToCount: length), body.count == length else { break }
        let response: CLIResponse
        if let request = try? JSONDecoder().decode(CLIRequest.self, from: body),
           [.match, .fill, .save].contains(request.command) {
            response = BridgeClient.send(request, socket: socket)
        } else {
            response = .failure("Unsupported request.")
        }
        let data = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
        let n = UInt32(data.count)
        output.write(Data([UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24)]) + data)
    }
    exit(0)
}

/// The running binary's absolute path, with symlinks resolved.
///
/// `argv[0]` is only "tw" when started through PATH (a Homebrew symlink, say), and treating that
/// as a file URL would resolve it against the current directory. Ask the system instead, and fall
/// back to `argv[0]` only when it is already absolute.
func executablePath() -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    if proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 {
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }
    let argv0 = CommandLine.arguments[0]
    guard argv0.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: argv0).resolvingSymlinksInPath().path
}

/// Write the native-messaging host manifest for each browser whose data folder exists. Returns the files written.
func writeHostManifest(_ manifest: [String: Any], browsers: [(folder: String, hostFolder: String)]) -> [String] {
    guard let me = executablePath() else {
        fail("couldn't work out where tw is installed; run it by its full path", code: 70)
    }
    var manifest = manifest
    manifest["path"] = me
    let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    var written: [String] = []
    for browser in browsers {
        guard FileManager.default.fileExists(atPath: support.appending(path: browser.folder).path) else { continue }
        let dir = support.appending(path: "\(browser.hostFolder)/NativeMessagingHosts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "\(chromeHost).json")
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
           (try? data.write(to: file)) != nil { written.append(file.path) }
    }
    return written
}

/// `tw install-chrome <extension-id>` registers this binary as Chrome's native-messaging host.
func installChromeHost(_ extensionID: String) -> Never {
    guard extensionID.range(of: "^[a-p]{32}$", options: .regularExpression) != nil else {
        fail("that doesn't look like a Chrome extension id (32 letters a–p, see chrome://extensions)", code: 64)
    }
    let manifest: [String: Any] = [
        "name": chromeHost, "description": "Triwarden", "type": "stdio",
        "allowed_origins": ["chrome-extension://\(extensionID)/"],
    ]
    let written = writeHostManifest(manifest, browsers: [
        ("Google/Chrome", "Google/Chrome"), ("Google/Chrome Beta", "Google/Chrome Beta"), ("Chromium", "Chromium"),
        ("Microsoft Edge", "Microsoft Edge"), ("BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser"),
        ("Arc/User Data", "Arc/User Data"),
    ])
    guard !written.isEmpty else { fail("no Chromium-based browser found") }
    written.forEach { print("wrote \($0)") }
    exit(0)
}

/// `tw install-firefox` registers this binary as Firefox's native-messaging host. Firefox lists the add-ons that
/// may start it (`allowed_extensions`) instead of Chrome's origins.
func installFirefoxHost() -> Never {
    let manifest: [String: Any] = [
        "name": chromeHost, "description": "Triwarden", "type": "stdio",
        "allowed_extensions": [firefoxExtensionID],
    ]
    // Firefox keeps its profiles in "Firefox" and reads hosts from "Mozilla".
    let written = writeHostManifest(manifest, browsers: [("Firefox", "Mozilla")])
    guard !written.isEmpty else { fail("Firefox not found") }
    written.forEach { print("wrote \($0)") }
    exit(0)
}

if startedByBrowser(Array(CommandLine.arguments.dropFirst())) { nativeMessagingLoop() }

var args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else { print(usage); exit(64) }
if first == "-h" || first == "--help" || first == "help" { print(usage); exit(0) }
if first == "install-chrome" {
    guard args.count == 2 else { fail("usage: tw install-chrome <extension-id>", code: 64) }
    installChromeHost(args[1])
}
if first == "install-firefox" {
    guard args.count == 1 else { fail("usage: tw install-firefox", code: 64) }
    installFirefoxHost()
}
guard let command = CLIRequest.Command(rawValue: first) else { fail("unknown command “\(first)”\n\n" + usage, code: 64) }
args.removeFirst()

@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}
var request = CLIRequest(command: command)
request.field = option("--field")
request.length = option("--length").flatMap(Int.init)
request.query = args.isEmpty ? nil : args.joined(separator: " ")
if [.get, .code].contains(command), request.query == nil { fail("\(command.rawValue) needs an item", code: 64) }

let response = BridgeClient.send(request, socket: socket)
guard response.ok else { fail(response.error ?? "failed") }
if let rows = response.rows {
    let width = min(rows.map(\.name.count).max() ?? 0, 40)
    for row in rows {
        print(row.name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + row.detail + "  " + row.id)
    }
} else if let value = response.value {
    // No trailing newline when piped, so `tw get x | pbcopy` copies exactly the secret.
    if isatty(STDOUT_FILENO) != 0 { print(value) } else { FileHandle.standardOutput.write(Data(value.utf8)) }
}
