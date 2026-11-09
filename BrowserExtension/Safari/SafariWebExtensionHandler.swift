import AppKit
import Foundation
import os
import SafariServices
import SSHAgent

/// Safari's native side of the extension: forwards `match` / `fill` / `save` / `generate` to the running app over the
/// App Group socket. Holds no keys and stores nothing.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let log = Logger(subsystem: "io.github.sinhong2011.triwarden", category: "bridge")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]
        DispatchQueue.global(qos: .userInitiated).async {
            let response: CLIResponse
            if let message, JSONSerialization.isValidJSONObject(message),
               let data = try? JSONSerialization.data(withJSONObject: message),
               let request = try? JSONDecoder().decode(CLIRequest.self, from: data),
               [.match, .fill, .save, .copy, .generate].contains(request.command) {
                response = BridgeClient.send(request)
            } else {
                response = .failure("Unsupported request.")
            }
            // Best-effort: sandboxed Safari web extensions usually cannot launch the host app
            // (no temporary exception entitlement). Open-at-login + the in-page banner cover recovery;
            // this attempt is logged so `log show` shows whether the sandbox blocked it.
            if response.code == "app_not_running" {
                Self.tryOpenHostApp()
            }
            let object = (try? JSONEncoder().encode(response)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
            let reply = NSExtensionItem()
            reply.userInfo = [SFExtensionMessageKey: object]
            context.completeRequest(returningItems: [reply])
        }
    }

    /// Containing `Triwarden.app` for this appex (`…/Triwarden.app/Contents/PlugIns/….appex`).
    private static var hostAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Triwarden.app
    }

    private static func tryOpenHostApp() {
        let appURL = hostAppURL
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            log.error("host app missing at \(appURL.path, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                log.error("sandbox blocked opening host app: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("requested host app open at \(appURL.path, privacy: .public)")
            }
        }
    }
}
