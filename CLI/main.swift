import Darwin
import Foundation
import SSHAgent
import SecretsAgent
#if DEBUG
import LocalAuthentication
import Security
#endif

// `tw` — talks to the running Triwarden app. Secrets need the vault unlocked and an approval
// (Touch ID or the Mac password) in the app.

let usage = """
usage: tw <command> [arguments]

  run                      choose a saved tool in this terminal
  run --profile ID         launch an exact saved tool from Tools in Triwarden
  run --env-file FILE      launch a saved tool from its .env.triwarden references
  tools list               list saved tool names and exact launch commands
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
#if DEBUG
// Diagnostic-only: verify that this helper cannot read or overwrite a disposable App-owned record.
// Never accept a production service name, request a real credential, or print returned data.
if first == "--selftest-secrets-keychain" {
    let prefix = "io.github.sinhong2011.triwarden.secrets.selftest."
    guard args.count == 2, args[1].hasPrefix(prefix), UUID(uuidString: String(args[1].dropFirst(prefix.count))) != nil else {
        fail("Expected an isolated self-test Keychain service.", code: 64)
    }
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: args[1],
        kSecAttrAccount as String: "local-profile",
        kSecAttrAccessGroup as String: "FX3VR69P5K.io.github.sinhong2011.triwarden.shared",
        kSecUseDataProtectionKeychain as String: true,
        kSecUseAuthenticationContext as String: context,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    var updateQuery = query
    updateQuery.removeValue(forKey: kSecReturnData as String)
    updateQuery.removeValue(forKey: kSecMatchLimit as String)
    let updateStatus = SecItemUpdate(updateQuery as CFDictionary,
                                    [kSecValueData as String: Data("synthetic-write-must-be-denied".utf8)] as CFDictionary)
    let readDenied = status == errSecMissingEntitlement || status == errSecItemNotFound
    let writeDenied = updateStatus == errSecMissingEntitlement || updateStatus == errSecItemNotFound
    exit(readDenied && writeDenied ? 0 : 1)
}
#endif
var runStore = SecretsProfileStore.shared
var runArguments = Array(args.dropFirst())
var isRun = first == "run"
var isTools = first == "tools"
#if DEBUG
var selectionProbe = false
// Only a UUID-scoped disposable socket/profile can be selected by the native online diagnostic.
// The regular run path still ignores caller-supplied sockets and always uses its saved profile.
if ["--selftest-secrets-run", "--selftest-secrets-run-env", "--selftest-secrets-tools", "--selftest-secrets-select", "--selftest-secrets-env"].contains(first) {
    guard args.count == 2, UUID(uuidString: args[1]) != nil else { fail("Expected a self-test UUID.", code: 64) }
    let root = runStore.directory.deletingLastPathComponent().appendingPathComponent("S" + args[1].prefix(8))
    guard (try? String(contentsOf: root.appendingPathComponent("test-id"), encoding: .utf8)) == args[1] else {
        fail("The isolated self-test marker is missing.", code: 64)
    }
    runStore = SecretsProfileStore(directory: root.appendingPathComponent("p"))
    runArguments = ["--profile", "canary"]
    selectionProbe = first == "--selftest-secrets-select" || first == "--selftest-secrets-env"
    isRun = first == "--selftest-secrets-run" || first == "--selftest-secrets-run-env" || selectionProbe
    isTools = !isRun
    if isTools { runArguments = ["list"] }
    if selectionProbe { runArguments = [] }
    if first == "--selftest-secrets-env" || first == "--selftest-secrets-run-env" {
        runArguments = ["--env-file", root.appendingPathComponent(".env.triwarden").path]
    }
}
#endif
if isTools {
    do {
        try SavedToolCommands.validateListArguments(runArguments)
        print(try SavedToolCommands.list(runStore.loadAll()))
        exit(0)
    } catch { fail(error.localizedDescription) }
}
if isRun {
    do {
        let store = runStore
        let selected: SecretsProfile?
        var referenceFile: EnvReferenceFile?
        let name: String
        if runArguments.isEmpty {
            guard let choice = try TerminalToolSelection.choose(profiles: store.loadAll()) else {
                FileHandle.standardError.write(Data("Launch cancelled.\n".utf8))
                exit(130)
            }
            selected = choice; name = choice.name
        } else {
            selected = nil
            switch try RunArguments.source(runArguments) {
            case .profile(let id): name = id
            case .environmentFile(let path):
                let file = try EnvReferenceFile.read(URL(fileURLWithPath: path))
                referenceFile = file; name = file.toolID
            }
        }
        let profile = try store.load(named: name)
        try referenceFile?.validate(against: profile)
        guard selected == nil || selected == profile else {
            throw SecretsFailure("The tool settings changed during selection. Use tw run to select the tool again.")
        }
        guard profile.enabled, profile.name == name else {
            throw SecretsFailure("Open Tools in Triwarden to review or resume the requested tool.")
        }
        #if DEBUG
        // The isolated selection diagnostic stops before identity checks, IPC, or credential access.
        if selectionProbe { print("Selected saved tool: " + profile.name); exit(0) }
        #endif
        // Resolve only the saved absolute executable. A caller-supplied PATH cannot choose the target.
        let identity = try LaunchIdentity.capture(profile)
        #if DEBUG
        if first == "--selftest-secrets-run" || first == "--selftest-secrets-run-env" {
            // Catch an unusable fixture working directory before asking for authentication.
            let directoryFD = open(identity.directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { throw SecretsFailure("The self-test helper cannot open its working directory (OS error \(errno)).") }
            close(directoryFD)
        }
        #endif
        let request = SecretsRunRequest(profile: profile, revision: try profile.revision(), launch: identity)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else {
            throw SecretsFailure(TerminalHelperInstallation.repairLink)
        }
        let ownPath = URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).resolvingSymlinksInPath()
        guard ownPath.lastPathComponent == "tw", ownPath.deletingLastPathComponent().lastPathComponent == "MacOS" else {
            throw SecretsFailure(TerminalHelperInstallation.repairLink)
        }
        let app = ownPath.deletingLastPathComponent().appendingPathComponent("Triwarden")
        // Deliberately ignore TW_SOCKET for credential delivery. Authenticate the App, too.
        let response = try SecretsClient.request(request, socket: store.socketURL, expectedApp: app)
        let values = try response.validatedValues(for: request)
        guard try store.load(named: name) == profile else { throw SecretsFailure("The tool settings changed during approval. Start the launch again.") }
        let environment = try LaunchPolicy.environment(parent: ProcessInfo.processInfo.environment, values: values)
        try SecretsExec.replace(profile: profile, identity: identity, environment: environment)
    } catch { fail(error.localizedDescription) }
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
