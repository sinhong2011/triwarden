import Foundation

/// The native-messaging host manifest that lets a browser start `tw` for the Triwarden extension. Chromium browsers
/// name the extension origins that may start it (`allowed_origins`); Firefox names add-on ids (`allowed_extensions`).
public enum NativeHost {
    public static let name = "io.github.sinhong2011.triwarden"
    /// The Firefox add-on id. It must equal `browser_specific_settings.gecko.id` in
    /// BrowserExtension/WebExtension/wxt.config.ts (scripts/test-install-chrome-path.py checks that).
    public static let firefoxExtensionID = "triwarden@sinhong2011.github.io"

    /// The Chrome Web Store ID of the extension. The manifest carries the store's public key (wxt.config.ts), so an
    /// unpacked build has this ID too. scripts/test-install-chrome-path.py checks the two agree.
    public static let chromeExtensionID = "deiehcliaaoigminkkbnjlgmaoagimdm"

    /// The extension's page on the Chrome Web Store. Chrome, Edge, Brave and the other Chromium browsers install from it.
    public static let chromeStoreURL = URL(string: "https://chromewebstore.google.com/detail/\(chromeExtensionID)")!

    public struct Browser: Identifiable, Hashable, Sendable {
        public enum Family: Sendable { case chromium, firefox }
        public let id: String
        public let title: String
        /// The app's bundle id, to tell whether it is installed (a sandboxed app cannot look into other apps' folders).
        public let bundleID: String
        public let family: Family
        /// Where the browser keeps its profiles, under `~/Library/Application Support`. Present when it is installed.
        public let dataFolder: String
        /// Where it reads native-messaging hosts from, under `~/Library/Application Support`.
        public let hostFolder: String
    }

    /// Where to install the extension for `browser`; nil when it has no listing yet (Firefox, until Mozilla approves it).
    public static func storeURL(for browser: Browser) -> URL? {
        browser.family == .chromium ? chromeStoreURL : nil
    }

    public static let browsers: [Browser] = [
        .init(id: "chrome", title: "Google Chrome", bundleID: "com.google.Chrome", family: .chromium, dataFolder: "Google/Chrome", hostFolder: "Google/Chrome/NativeMessagingHosts"),
        .init(id: "chrome-beta", title: "Chrome Beta", bundleID: "com.google.Chrome.beta", family: .chromium, dataFolder: "Google/Chrome Beta", hostFolder: "Google/Chrome Beta/NativeMessagingHosts"),
        .init(id: "chromium", title: "Chromium", bundleID: "org.chromium.Chromium", family: .chromium, dataFolder: "Chromium", hostFolder: "Chromium/NativeMessagingHosts"),
        .init(id: "edge", title: "Microsoft Edge", bundleID: "com.microsoft.edgemac", family: .chromium, dataFolder: "Microsoft Edge", hostFolder: "Microsoft Edge/NativeMessagingHosts"),
        .init(id: "brave", title: "Brave", bundleID: "com.brave.Browser", family: .chromium, dataFolder: "BraveSoftware/Brave-Browser", hostFolder: "BraveSoftware/Brave-Browser/NativeMessagingHosts"),
        .init(id: "arc", title: "Arc", bundleID: "company.thebrowser.Browser", family: .chromium, dataFolder: "Arc/User Data", hostFolder: "Arc/User Data/NativeMessagingHosts"),
        .init(id: "firefox", title: "Firefox", bundleID: "org.mozilla.firefox", family: .firefox, dataFolder: "Firefox", hostFolder: "Mozilla/NativeMessagingHosts"),
    ]

    /// `~/Library/Application Support`. `TW_SUPPORT_DIR` overrides it, for tests: they must never write into the real
    /// browsers' folders. A sandboxed app's own home is its container, so otherwise this asks the system for the
    /// account's home directory.
    public static var applicationSupport: URL {
        if let override = ProcessInfo.processInfo.environment["TW_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir)).appending(path: "Library/Application Support")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    }

    public static func hostFolderURL(_ browser: Browser, support: URL = applicationSupport) -> URL {
        support.appending(path: browser.hostFolder, directoryHint: .isDirectory)
    }

    public static func manifestURL(_ browser: Browser, support: URL = applicationSupport) -> URL {
        hostFolderURL(browser, support: support).appending(path: "\(name).json")
    }

    /// Whether the browser's folder exists. Reliable for a tool outside the sandbox (`tw`); the sandboxed app uses
    /// `NSWorkspace` with `bundleID` instead.
    public static func isInstalled(_ browser: Browser, support: URL = applicationSupport) -> Bool {
        FileManager.default.fileExists(atPath: support.appending(path: browser.dataFolder).path)
    }

    /// A Chrome extension id: 32 letters a to p.
    public static func isChromeExtensionID(_ id: String) -> Bool {
        id.range(of: "^[a-p]{32}$", options: .regularExpression) != nil
    }

    /// The manifest JSON for `browser`, pointing at `tool` (the bundled `tw`). Chromium needs the extension's id.
    public static func manifest(for browser: Browser, tool: String, chromeExtensionID: String? = NativeHost.chromeExtensionID) throws -> Data {
        var manifest: [String: Any] = ["name": name, "description": "Triwarden", "type": "stdio", "path": tool]
        switch browser.family {
        case .chromium:
            guard let id = chromeExtensionID, isChromeExtensionID(id) else { throw Failure.badExtensionID }
            manifest["allowed_origins"] = ["chrome-extension://\(id)/"]
        case .firefox:
            manifest["allowed_extensions"] = [firefoxExtensionID]
        }
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    public enum Failure: Error, Equatable { case badExtensionID }

    public enum State: Equatable, Sendable {
        case notInstalled          // the browser isn't on this Mac
        case notConnected          // no manifest yet
        case connected             // a manifest points at this app's tool
        case movedApp(String)      // a manifest exists but points somewhere else (the app moved, or another copy)
    }

    /// Whether `browser` is connected to the tool at `tool`, from the path recorded when it was connected (`recordedTool`).
    /// A sandboxed app cannot read another app's folder, so it keeps its own note of what it wrote.
    public static func state(recordedTool: String?, tool: String) -> State {
        guard let recordedTool else { return .notConnected }
        return URL(fileURLWithPath: recordedTool).resolvingSymlinksInPath().path == URL(fileURLWithPath: tool).resolvingSymlinksInPath().path
            ? .connected : .movedApp(recordedTool)
    }

    /// The same, read from the manifest on disk. For callers that can read it (tests, the unsandboxed `tw`).
    public static func state(of browser: Browser, tool: String, support: URL = applicationSupport) -> State {
        guard isInstalled(browser, support: support) else { return .notInstalled }
        guard let data = try? Data(contentsOf: manifestURL(browser, support: support)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String else { return .notConnected }
        return state(recordedTool: path, tool: tool)
    }

    /// The Chrome extension id a manifest allows, to keep it when the app moves and the manifest is rewritten.
    public static func chromeExtensionID(in browser: Browser, support: URL = applicationSupport) -> String? {
        guard let data = try? Data(contentsOf: manifestURL(browser, support: support)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let origin = (object["allowed_origins"] as? [String])?.first else { return nil }
        let id = origin.replacingOccurrences(of: "chrome-extension://", with: "").replacingOccurrences(of: "/", with: "")
        return isChromeExtensionID(id) ? id : nil
    }
}
