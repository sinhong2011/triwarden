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

        public init(id: String, title: String, bundleID: String, family: Family, dataFolder: String, hostFolder: String) {
            self.id = id; self.title = title; self.bundleID = bundleID; self.family = family
            self.dataFolder = dataFolder; self.hostFolder = hostFolder
        }
    }

    /// The extension's page on Firefox Add-ons (AMO). No language in the address: AMO picks the visitor's.
    public static let firefoxStoreURL = URL(string: "https://addons.mozilla.org/firefox/addon/triwarden/")!

    /// Where to install the extension for `browser`: Chrome Web Store for Chromium browsers, Firefox Add-ons for Firefox.
    public static func storeURL(for browser: Browser) -> URL {
        switch browser.family {
        case .chromium: chromeStoreURL
        case .firefox: firefoxStoreURL
        }
    }

    public static let browsers: [Browser] = [
        .init(id: "chrome", title: "Google Chrome", bundleID: "com.google.Chrome", family: .chromium, dataFolder: "Google/Chrome", hostFolder: "Google/Chrome/NativeMessagingHosts"),
        .init(id: "chrome-beta", title: "Chrome Beta", bundleID: "com.google.Chrome.beta", family: .chromium, dataFolder: "Google/Chrome Beta", hostFolder: "Google/Chrome Beta/NativeMessagingHosts"),
        .init(id: "chrome-for-testing", title: "Chrome for Testing", bundleID: "com.google.chrome.for.testing", family: .chromium, dataFolder: "Google/Chrome for Testing", hostFolder: "Google/Chrome for Testing/NativeMessagingHosts"),
        .init(id: "chromium", title: "Chromium", bundleID: "org.chromium.Chromium", family: .chromium, dataFolder: "Chromium", hostFolder: "Chromium/NativeMessagingHosts"),
        .init(id: "edge", title: "Microsoft Edge", bundleID: "com.microsoft.edgemac", family: .chromium, dataFolder: "Microsoft Edge", hostFolder: "Microsoft Edge/NativeMessagingHosts"),
        // Brave on macOS resolves native-messaging hosts from Chrome's folder, not BraveSoftware
        // (Brave framework ships `/Library/Google/Chrome/NativeMessagingHosts`; KeePassXC #13429).
        // dataFolder stays Brave's own profile so we still detect that Brave is installed.
        .init(id: "brave", title: "Brave", bundleID: "com.brave.Browser", family: .chromium, dataFolder: "BraveSoftware/Brave-Browser", hostFolder: "Google/Chrome/NativeMessagingHosts"),
        .init(id: "arc", title: "Arc", bundleID: "company.thebrowser.Browser", family: .chromium, dataFolder: "Arc/User Data", hostFolder: "Arc/User Data/NativeMessagingHosts"),
        .init(id: "zen", title: "Zen", bundleID: "app.zen-browser.zen", family: .firefox, dataFolder: "zen", hostFolder: "zen/NativeMessagingHosts"),
        .init(id: "firefox", title: "Firefox", bundleID: "org.mozilla.firefox", family: .firefox, dataFolder: "Firefox", hostFolder: "Mozilla/NativeMessagingHosts"),
    ]

    // MARK: Other Chromium browsers

    /// Where some Chromium browsers that aren't in `browsers` usually keep their profiles. Only a starting point for the
    /// folder picker: the folder the person picks is checked with `isChromiumDataFolder` before anything is written.
    static let likelyChromiumDataFolders: [String: String] = [
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "net.imput.helium": "net.imput.helium",
    ]

    /// A Chromium browser that isn't in `browsers`. Its folder is empty until the person picks its profile folder.
    public static func chromiumBrowser(id: String, title: String, bundleID: String = "", dataFolder: String = "") -> Browser {
        .init(id: id, title: title, bundleID: bundleID, family: .chromium, dataFolder: dataFolder,
              hostFolder: dataFolder.isEmpty ? "" : dataFolder + "/NativeMessagingHosts")
    }

    /// Whether the app at `app` is built on Chromium: it ships a `<Name> Framework.framework`, which every Chromium
    /// browser does. Electron apps ship one too, always named `Electron Framework`, so that one doesn't count.
    public static func isChromiumApp(at app: URL) -> Bool {
        let frameworks = (try? FileManager.default.contentsOfDirectory(atPath: app.appending(path: "Contents/Frameworks").path)) ?? []
        return frameworks.contains { $0.hasSuffix(" Framework.framework") && $0 != "Electron Framework.framework" }
    }

    /// Whether `folder` is a Chromium browser's profile folder (its user data directory): it has `Local State` and a
    /// `Default` or `Profile N` profile. Electron apps have `Local State` but no profile folders.
    public static func isChromiumDataFolder(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appending(path: "Local State").path) else { return false }
        let entries = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.contains { $0 == "Default" || $0.hasPrefix("Profile ") }
    }

    /// The Chromium browsers among `apps` (the apps that open web pages) that `browsers` doesn't already list.
    public static func discoverChromiumBrowsers(apps: [URL]) -> [Browser] {
        let listed = Set(browsers.map(\.bundleID))
        var seen = Set<String>()
        return apps.compactMap { app -> Browser? in
            guard let bundle = Bundle(url: app), let bundleID = bundle.bundleIdentifier,
                  !listed.contains(bundleID), seen.insert(bundleID).inserted, isChromiumApp(at: app) else { return nil }
            let title = displayName(bundle, app)
            // Chromium reads CrProductDirName from Info.plist when a build sets it; otherwise the folder is compiled in.
            let folder = (bundle.object(forInfoDictionaryKey: "CrProductDirName") as? String) ?? likelyChromiumDataFolders[bundleID] ?? ""
            return chromiumBrowser(id: bundleID, title: title, bundleID: bundleID, dataFolder: folder)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Chromium profile folders under `support` (one or two levels down, like `Vivaldi` or `Arc/User Data`) that no
    /// browser in `browsers` already covers. For `tw`, which runs outside the sandbox and can look.
    public static func unlistedChromiumDataFolders(support: URL = applicationSupport) -> [String] {
        unlistedDataFolders(support: support, where: isChromiumDataFolder)
    }

    private static func unlistedDataFolders(support: URL, where matches: (URL) -> Bool) -> [String] {
        let fm = FileManager.default
        let listed = Set(browsers.map(\.dataFolder))
        var found: [String] = []
        func children(_ relative: String) -> [String] {
            let url = relative.isEmpty ? support : support.appending(path: relative)
            return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
                .map { relative.isEmpty ? $0 : relative + "/" + $0 }
        }
        for top in children("") {
            for candidate in [top] + children(top) where !listed.contains(candidate) {
                if matches(support.appending(path: candidate, directoryHint: .isDirectory)) { found.append(candidate) }
            }
        }
        return found
    }

    // MARK: Other Firefox-based browsers

    /// Where Firefox reads native-messaging hosts by default. Most Firefox-based browsers (LibreWolf, Waterfox, Floorp,
    /// Mullvad Browser…) keep that default, so one file here serves all of them: the manifest is the same for each.
    public static let mozillaHostFolder = "Mozilla/NativeMessagingHosts"

    /// Firefox-family apps that use Gecko for something other than browsing the web.
    static let notBrowsers: Set<String> = ["org.mozilla.thunderbird", "Thunderbird"]

    /// A Firefox-based browser that isn't in `browsers`: it reads the shared Mozilla folder, and `dataFolder` is its own
    /// folder under Application Support (where `profiles.ini` is), which some forks read instead (Zen does).
    public static func firefoxBrowser(id: String, title: String, bundleID: String = "", dataFolder: String) -> Browser {
        .init(id: id, title: title, bundleID: bundleID, family: .firefox, dataFolder: dataFolder, hostFolder: mozillaHostFolder)
    }

    /// Whether the app at `app` is built on Firefox's engine: it ships `XUL`, Gecko's library.
    public static func isFirefoxApp(at app: URL) -> Bool {
        FileManager.default.fileExists(atPath: app.appending(path: "Contents/MacOS/XUL").path)
    }

    /// Where a Firefox-based app keeps its profiles under Application Support. Gecko builds that from `application.ini`:
    /// `Profile` when the app sets it, otherwise `Name` (`Firefox` for Firefox).
    public static func firefoxDataFolder(app: URL) -> String? {
        guard let text = try? String(contentsOf: app.appending(path: "Contents/Resources/application.ini"), encoding: .utf8) else { return nil }
        var section = ""
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line; continue }
            guard section == "[App]", let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        let folder = values["Profile"] ?? values["Name"]
        return folder?.isEmpty == false ? folder : nil
    }

    /// The Firefox-based browsers among `apps` that `browsers` doesn't already list.
    public static func discoverFirefoxBrowsers(apps: [URL]) -> [Browser] {
        let listed = Set(browsers.map(\.bundleID))
        var seen = Set<String>()
        return apps.compactMap { app -> Browser? in
            guard let bundle = Bundle(url: app), let bundleID = bundle.bundleIdentifier, !listed.contains(bundleID),
                  !notBrowsers.contains(bundleID), seen.insert(bundleID).inserted, isFirefoxApp(at: app) else { return nil }
            let folder = firefoxDataFolder(app: app) ?? ""
            return firefoxBrowser(id: bundleID, title: displayName(bundle, app), bundleID: bundleID, dataFolder: folder)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Every browser among `apps` that `browsers` doesn't list: Chromium-based and Firefox-based.
    public static func discoverBrowsers(apps: [URL]) -> [Browser] {
        (discoverChromiumBrowsers(apps: apps) + discoverFirefoxBrowsers(apps: apps))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Firefox-family profile folders under `support` (with `profiles.ini`) that no browser in `browsers` covers.
    public static func unlistedFirefoxDataFolders(support: URL = applicationSupport) -> [String] {
        unlistedDataFolders(support: support) { folder in
            !notBrowsers.contains(folder.lastPathComponent)
                && FileManager.default.fileExists(atPath: folder.appending(path: "profiles.ini").path)
        }
    }

    /// For a Firefox-based browser that isn't listed: its own folder's NativeMessagingHosts, which gets a copy of the
    /// file next to the shared Mozilla one. Nil when it has no folder of its own or already reads it.
    public static func ownHostFolder(_ browser: Browser) -> String? {
        guard browser.family == .firefox, !browser.dataFolder.isEmpty, !browsers.contains(where: { $0.id == browser.id }) else { return nil }
        let own = browser.dataFolder + "/NativeMessagingHosts"
        return own == browser.hostFolder ? nil : own
    }

    static func displayName(_ bundle: Bundle, _ app: URL) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? app.deletingPathExtension().lastPathComponent
    }

    /// `folder`'s path relative to `support`, or nil when it isn't inside it.
    public static func relativeSupportPath(_ folder: URL, support: URL = applicationSupport) -> String? {
        let base = support.standardizedFileURL.resolvingSymlinksInPath().path
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// A name for a browser known only by its profile folder: `Vivaldi` for `Vivaldi`, `Thorium` for `Thorium/User Data`.
    public static func title(forDataFolder folder: String) -> String {
        let parts = folder.split(separator: "/").map(String.init).filter { $0 != "User Data" }
        return parts.last ?? folder
    }

    /// Folders under Application Support that should receive the host manifest for `browser`.
    /// Brave also keeps a copy under BraveSoftware in case a future Brave build starts reading it.
    public static func hostFoldersForInstall(_ browser: Browser) -> [String] {
        if browser.id == "brave" {
            return [
                "Google/Chrome/NativeMessagingHosts",
                "BraveSoftware/Brave-Browser/NativeMessagingHosts",
            ]
        }
        if let own = ownHostFolder(browser) { return [browser.hostFolder, own] }
        return [browser.hostFolder]
    }

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
