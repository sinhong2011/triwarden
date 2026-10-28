import Foundation
import SafariServices
import SSHAgent

/// Safari's native side of the extension: forwards `match` / `fill` / `save` to the running app over the
/// App Group socket. Holds no keys and stores nothing.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]
        DispatchQueue.global(qos: .userInitiated).async {
            let response: CLIResponse
            if let message, JSONSerialization.isValidJSONObject(message),
               let data = try? JSONSerialization.data(withJSONObject: message),
               let request = try? JSONDecoder().decode(CLIRequest.self, from: data),
               [.match, .fill, .save, .copy].contains(request.command) {
                response = BridgeClient.send(request)
            } else {
                response = .failure("Unsupported request.")
            }
            let object = (try? JSONEncoder().encode(response)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
            let reply = NSExtensionItem()
            reply.userInfo = [SFExtensionMessageKey: object]
            context.completeRequest(returningItems: [reply])
        }
    }
}
