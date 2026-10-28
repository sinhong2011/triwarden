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
let chromeHost = NativeHost.name

/// Chrome starts the host with the extension's origin; Firefox with the host manifest's path, then the add-on id.
func startedByBrowser(_ arguments: [String]) -> Bool {
    guard let first = arguments.first else { return false }
    return first.hasPrefix("chrome-extension://") || first.hasSuffix("/\(chromeHost).json")
}

/// The bundle id of the browser that started `tw` (its parent process), e.g. "com.google.Chrome".
func launchingBrowserBundleID() -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(getppid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let path = String(cString: buffer)
    // The outermost .app: a browser's own helper apps live inside it.
    guard let end = path.range(of: ".app/")?.lowerBound else { return nil }
    return Bundle(path: String(path[..<end]) + ".app")?.bundleIdentifier
}

/// Browser native messaging (Chrome and Firefox): messages are 4-byte little-endian length + JSON on stdin/stdout.
func nativeMessagingLoop(launchedWith arguments: [String]) -> Never {
    // Chrome passes the extension's origin; Firefox passes the host manifest's path and then the add-on id.
    let origin = arguments.first { $0.hasPrefix("chrome-extension://") } ?? (arguments.count > 1 ? arguments[1] : nil)
    let browser = launchingBrowserBundleID()
    let input = FileHandle.standardInput, output = FileHandle.standardOutput
    while let header = try? input.read(upToCount: 4), header.count == 4 {
        let length = Int(header[0]) | Int(header[1]) << 8 | Int(header[2]) << 16 | Int(header[3]) << 24
        guard length > 0, length < 1_048_576, let body = try? input.read(upToCount: length), body.count == length else { break }
        let response: CLIResponse
        if var request = try? JSONDecoder().decode(CLIRequest.self, from: body),
           [.match, .fill, .save, .copy].contains(request.command) {
            request.origin = origin // from how the browser started us, whatever the message said
            request.browser = browser
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

/// Write the native-messaging host manifest for each installed browser of `family`. Returns the files written.
func installHost(_ family: NativeHost.Browser.Family, chromeExtensionID: String? = nil) -> [String] {
    guard let me = executablePath() else {
        fail("couldn't work out where tw is installed; run it by its full path", code: 70)
    }
    var written: [String] = []
    for browser in NativeHost.browsers where browser.family == family && NativeHost.isInstalled(browser) {
        guard let data = try? NativeHost.manifest(for: browser, tool: me, chromeExtensionID: chromeExtensionID) else { continue }
        let file = NativeHost.manifestURL(browser)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: file)) != nil { written.append(file.path) }
    }
    return written
}

/// `tw install-chrome <extension-id>` registers this binary as Chrome's native-messaging host.
func installChromeHost(_ extensionID: String) -> Never {
    guard NativeHost.isChromeExtensionID(extensionID) else {
        fail("that doesn't look like a Chrome extension id (32 letters a–p, see chrome://extensions)", code: 64)
    }
    let written = installHost(.chromium, chromeExtensionID: extensionID)
    guard !written.isEmpty else { fail("no Chromium-based browser found") }
    written.forEach { print("wrote \($0)") }
    exit(0)
}

/// `tw install-firefox` registers this binary as Firefox's native-messaging host. Firefox lists the add-ons that
/// may start it (`allowed_extensions`) instead of Chrome's origins.
func installFirefoxHost() -> Never {
    let written = installHost(.firefox)
    guard !written.isEmpty else { fail("Firefox not found") }
    written.forEach { print("wrote \($0)") }
    exit(0)
}

if startedByBrowser(Array(CommandLine.arguments.dropFirst())) { nativeMessagingLoop(launchedWith: Array(CommandLine.arguments.dropFirst())) }

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
