import Foundation
import Testing
@testable import SSHAgent

struct NativeHostTests {
    private func temporarySupport() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "triwarden-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let chrome = NativeHost.browsers.first { $0.id == "chrome" }!
    private let firefox = NativeHost.browsers.first { $0.id == "firefox" }!
    private let id = String(repeating: "a", count: 16) + String(repeating: "p", count: 16)

    @Test func chromeManifestNamesTheExtensionOrigin() throws {
        let data = try NativeHost.manifest(for: chrome, tool: "/Applications/Triwarden.app/Contents/MacOS/tw", chromeExtensionID: id)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["name"] as? String == "io.github.sinhong2011.triwarden")
        #expect(object["type"] as? String == "stdio")
        #expect(object["path"] as? String == "/Applications/Triwarden.app/Contents/MacOS/tw")
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://\(id)/"])
        #expect(object["allowed_extensions"] == nil)
    }

    @Test func firefoxManifestNamesTheAddOn() throws {
        let data = try NativeHost.manifest(for: firefox, tool: "/tw")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["allowed_extensions"] as? [String] == [NativeHost.firefoxExtensionID])
        #expect(object["allowed_origins"] == nil)
    }

    @Test func chromiumDefaultsToTheStoreIDAndRejectsABadOne() throws {
        // With no ID given, the Chrome Web Store's ID is used.
        let data = try NativeHost.manifest(for: chrome, tool: "/tw")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://\(NativeHost.chromeExtensionID)/"])
        #expect(NativeHost.isChromeExtensionID(NativeHost.chromeExtensionID))

        // An ID that was given but is malformed is an error, never replaced by the default.
        #expect(throws: NativeHost.Failure.badExtensionID) { try NativeHost.manifest(for: chrome, tool: "/tw", chromeExtensionID: "short") }
        #expect(throws: NativeHost.Failure.badExtensionID) {
            try NativeHost.manifest(for: chrome, tool: "/tw", chromeExtensionID: String(repeating: "z", count: 32))
        }
        #expect(throws: NativeHost.Failure.badExtensionID) { try NativeHost.manifest(for: chrome, tool: "/tw", chromeExtensionID: nil) }
        #expect(NativeHost.isChromeExtensionID(id))
    }

    @Test func stateFollowsTheManifestOnDisk() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let tool = "/Applications/Triwarden.app/Contents/MacOS/tw"

        #expect(NativeHost.state(of: chrome, tool: tool, support: support) == .notInstalled)

        try FileManager.default.createDirectory(at: support.appending(path: chrome.dataFolder), withIntermediateDirectories: true)
        #expect(NativeHost.state(of: chrome, tool: tool, support: support) == .notConnected)

        let folder = NativeHost.hostFolderURL(chrome, support: support)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try NativeHost.manifest(for: chrome, tool: tool, chromeExtensionID: id).write(to: NativeHost.manifestURL(chrome, support: support))
        #expect(NativeHost.state(of: chrome, tool: tool, support: support) == .connected)
        #expect(NativeHost.chromeExtensionID(in: chrome, support: support) == id)

        // The app moved: the manifest still points at the old copy.
        #expect(NativeHost.state(of: chrome, tool: "/Users/me/Triwarden.app/Contents/MacOS/tw", support: support) == .movedApp(tool))
    }

    @Test func stateFromWhatTheAppRecorded() {
        let tool = "/Applications/Triwarden.app/Contents/MacOS/tw"
        #expect(NativeHost.state(recordedTool: nil, tool: tool) == .notConnected)
        #expect(NativeHost.state(recordedTool: tool, tool: tool) == .connected)
        #expect(NativeHost.state(recordedTool: "/Old/Triwarden.app/Contents/MacOS/tw", tool: tool) == .movedApp("/Old/Triwarden.app/Contents/MacOS/tw"))
    }

    @Test func everyBrowserHasABundleIDAndItsOwnHostFolder() {
        #expect(Set(NativeHost.browsers.map(\.bundleID)).count == NativeHost.browsers.count)
        #expect(NativeHost.browsers.allSatisfy { $0.hostFolder.hasSuffix("NativeMessagingHosts") })
        // Brave shares Chrome's host folder on macOS (Brave reads Chrome's NativeMessagingHosts).
        let brave = NativeHost.browsers.first { $0.id == "brave" }!
        #expect(brave.hostFolder == chrome.hostFolder)
        #expect(brave.dataFolder == "BraveSoftware/Brave-Browser")
        #expect(NativeHost.hostFoldersForInstall(brave) == [
            "Google/Chrome/NativeMessagingHosts",
            "BraveSoftware/Brave-Browser/NativeMessagingHosts",
        ])
        let others = NativeHost.browsers.filter { $0.id != "brave" }
        #expect(Set(others.map(\.hostFolder)).count == others.count)
    }

    @Test func eachBrowserInstallsFromItsOwnStore() {
        for browser in NativeHost.browsers where browser.family == .chromium {
            #expect(NativeHost.storeURL(for: browser) == NativeHost.chromeStoreURL)
        }
        #expect(NativeHost.storeURL(for: firefox) == NativeHost.firefoxStoreURL)
        #expect(NativeHost.chromeStoreURL.absoluteString.hasSuffix("/" + NativeHost.chromeExtensionID))
        #expect(NativeHost.firefoxStoreURL.host() == "addons.mozilla.org")
    }

    @Test func onlyOurOwnManifestFileIsUsed() throws {
        // Only our own file name is ever written or read.
        #expect(NativeHost.manifestURL(chrome).lastPathComponent == "io.github.sinhong2011.triwarden.json")
        #expect(NativeHost.manifestURL(firefox).path.contains("Mozilla/NativeMessagingHosts"))
    }

    // MARK: Other Chromium browsers

    private func makeFolder(_ path: String, in base: URL, files: [String] = []) throws {
        let dir = base.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files { try Data("{}".utf8).write(to: dir.appending(path: file)) }
    }

    private func makeApp(_ name: String, bundleID: String, framework: String, extra: [String: String] = [:], in base: URL) throws -> URL {
        let app = base.appending(path: "\(name).app", directoryHint: .isDirectory)
        try makeFolder("Contents/Frameworks/\(framework)", in: app)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        for (key, value) in extra { info[key] = value }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    @Test func aChromiumProfileFolderHasLocalStateAndAProfile() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        try makeFolder("Vivaldi", in: support, files: ["Local State"])
        try makeFolder("Vivaldi/Default", in: support)
        try makeFolder("Thorium/User Data", in: support, files: ["Local State"])
        try makeFolder("Thorium/User Data/Profile 1", in: support)
        try makeFolder("Slack", in: support, files: ["Local State", "Preferences"]) // an Electron app
        try makeFolder("Google/Chrome", in: support, files: ["Local State"])         // listed already
        try makeFolder("Google/Chrome/Default", in: support)

        #expect(NativeHost.isChromiumDataFolder(support.appending(path: "Vivaldi")))
        #expect(!NativeHost.isChromiumDataFolder(support.appending(path: "Slack")))
        #expect(NativeHost.unlistedChromiumDataFolders(support: support) == ["Thorium/User Data", "Vivaldi"])
    }

    @Test func aBrowserKnownByItsFolderGetsAManifestInsideIt() throws {
        let vivaldi = NativeHost.chromiumBrowser(id: "folder:Vivaldi", title: NativeHost.title(forDataFolder: "Vivaldi"), dataFolder: "Vivaldi")
        #expect(vivaldi.title == "Vivaldi")
        #expect(vivaldi.hostFolder == "Vivaldi/NativeMessagingHosts")
        #expect(NativeHost.title(forDataFolder: "Thorium/User Data") == "Thorium")
        let data = try NativeHost.manifest(for: vivaldi, tool: "/tw")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["allowed_origins"] as? [String] == ["chrome-extension://\(NativeHost.chromeExtensionID)/"])

        let unknown = NativeHost.chromiumBrowser(id: "x", title: "X")
        #expect(unknown.hostFolder.isEmpty)
    }

    @Test func relativeSupportPathStaysInsideApplicationSupport() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        try makeFolder("Thorium/User Data", in: support)
        #expect(NativeHost.relativeSupportPath(support.appending(path: "Thorium/User Data"), support: support) == "Thorium/User Data")
        #expect(NativeHost.relativeSupportPath(support, support: support) == nil)
        #expect(NativeHost.relativeSupportPath(support.deletingLastPathComponent(), support: support) == nil)
    }

    @Test func discoversChromiumBrowsersThatAreNotListed() throws {
        let apps = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: apps) }
        let vivaldi = try makeApp("Vivaldi", bundleID: "com.vivaldi.Vivaldi", framework: "Vivaldi Framework.framework", in: apps)
        let custom = try makeApp("Nova", bundleID: "com.example.nova", framework: "Nova Framework.framework",
                                 extra: ["CrProductDirName": "Nova/Browser"], in: apps)
        let unknown = try makeApp("Helix", bundleID: "com.example.helix", framework: "Helix Framework.framework", in: apps)
        let electron = try makeApp("Chat", bundleID: "com.example.chat", framework: "Electron Framework.framework", in: apps)
        let chrome = try makeApp("Google Chrome", bundleID: "com.google.Chrome", framework: "Google Chrome Framework.framework", in: apps)

        #expect(NativeHost.isChromiumApp(at: vivaldi))
        #expect(!NativeHost.isChromiumApp(at: electron))

        let found = NativeHost.discoverChromiumBrowsers(apps: [vivaldi, custom, unknown, electron, chrome, vivaldi])
        #expect(found.map(\.id) == ["com.example.helix", "com.example.nova", "com.vivaldi.Vivaldi"])
        #expect(found.map(\.dataFolder) == ["", "Nova/Browser", "Vivaldi"])
        #expect(found.allSatisfy { $0.family == .chromium })
    }

    // MARK: Other Firefox-based browsers

    private func makeGeckoApp(_ name: String, bundleID: String, ini: String, in base: URL) throws -> URL {
        let app = try makeApp(name, bundleID: bundleID, framework: "unused", in: base)
        try FileManager.default.removeItem(at: app.appending(path: "Contents/Frameworks"))
        try makeFolder("Contents/MacOS", in: app, files: ["XUL"])
        try makeFolder("Contents/Resources", in: app)
        try Data(ini.utf8).write(to: app.appending(path: "Contents/Resources/application.ini"))
        return app
    }

    @Test func discoversFirefoxBasedBrowsersAndTheirFolder() throws {
        let apps = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: apps) }
        let librewolf = try makeGeckoApp("LibreWolf", bundleID: "io.gitlab.librewolf-community.librewolf",
                                         ini: "[App]\nVendor=LibreWolf\nName=LibreWolf\n", in: apps)
        let custom = try makeGeckoApp("Kite", bundleID: "com.example.kite",
                                      ini: "[App]\nName=Kite\nProfile=Kite Browser\n[Gecko]\nName=ignored\n", in: apps)
        let thunderbird = try makeGeckoApp("Thunderbird", bundleID: "org.mozilla.thunderbird", ini: "[App]\nName=Thunderbird\n", in: apps)
        let firefox = try makeGeckoApp("Firefox", bundleID: "org.mozilla.firefox", ini: "[App]\nName=Firefox\n", in: apps)
        let vivaldi = try makeApp("Vivaldi", bundleID: "com.vivaldi.Vivaldi", framework: "Vivaldi Framework.framework", in: apps)

        #expect(NativeHost.isFirefoxApp(at: librewolf))
        #expect(!NativeHost.isFirefoxApp(at: vivaldi))
        #expect(NativeHost.firefoxDataFolder(app: custom) == "Kite Browser")

        let found = NativeHost.discoverFirefoxBrowsers(apps: [librewolf, custom, thunderbird, firefox, vivaldi])
        #expect(found.map(\.id) == ["com.example.kite", "io.gitlab.librewolf-community.librewolf"])
        #expect(found.allSatisfy { $0.family == .firefox && $0.hostFolder == NativeHost.mozillaHostFolder })
        #expect(NativeHost.discoverBrowsers(apps: [librewolf, vivaldi]).map(\.title) == ["LibreWolf", "Vivaldi"])
    }

    @Test func firefoxForksGetTheSharedFolderAndTheirOwn() {
        let librewolf = NativeHost.firefoxBrowser(id: "x", title: "LibreWolf", dataFolder: "LibreWolf")
        #expect(NativeHost.hostFoldersForInstall(librewolf) == ["Mozilla/NativeMessagingHosts", "LibreWolf/NativeMessagingHosts"])
        // The listed ones keep exactly their folder.
        #expect(NativeHost.hostFoldersForInstall(firefox) == ["Mozilla/NativeMessagingHosts"])
        let zen = NativeHost.browsers.first { $0.id == "zen" }!
        #expect(NativeHost.hostFoldersForInstall(zen) == ["zen/NativeMessagingHosts"])
        // No folder of its own: only the shared one.
        #expect(NativeHost.hostFoldersForInstall(NativeHost.firefoxBrowser(id: "y", title: "Y", dataFolder: "")) == ["Mozilla/NativeMessagingHosts"])
    }

    @Test func findsUnlistedFirefoxProfileFolders() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        try makeFolder("LibreWolf", in: support, files: ["profiles.ini"])
        try makeFolder("Waterfox", in: support, files: ["profiles.ini"])
        try makeFolder("Firefox", in: support, files: ["profiles.ini"])     // listed
        try makeFolder("Thunderbird", in: support, files: ["profiles.ini"]) // mail, not a browser
        try makeFolder("Mozilla/NativeMessagingHosts", in: support)
        #expect(NativeHost.unlistedFirefoxDataFolders(support: support) == ["LibreWolf", "Waterfox"])
    }
}
