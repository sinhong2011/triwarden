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
        #expect(Set(NativeHost.browsers.map(\.hostFolder)).count == NativeHost.browsers.count)
        #expect(NativeHost.browsers.allSatisfy { $0.hostFolder.hasSuffix("NativeMessagingHosts") })
    }

    @Test func onlyOurOwnManifestFileIsUsed() throws {
        // Only our own file name is ever written or read.
        #expect(NativeHost.manifestURL(chrome).lastPathComponent == "io.github.sinhong2011.triwarden.json")
        #expect(NativeHost.manifestURL(firefox).path.contains("Mozilla/NativeMessagingHosts"))
    }
}
