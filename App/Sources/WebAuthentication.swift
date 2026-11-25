import AppKit
import AuthenticationServices

/// Runs an identity provider's sign-in in a system web-authentication sheet and returns the callback URL.
/// The `bitwarden` callback scheme is caught for this session only; no URL scheme is registered.
@MainActor
enum WebAuthentication {
    enum Cancelled: Error { case byUser }

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
        }
    }

    static func run(_ url: URL) async throws -> URL {
        let anchor = Anchor()
        return try await withCheckedThrowingContinuation { continuation in
            // AuthenticationServices calls this on its own XPC queue, not the main thread. `@Sendable` keeps it out of
            // this enum's MainActor isolation; otherwise Swift 6's executor check traps (EXC_BREAKPOINT) right here.
            // The anchor is captured so it lives as long as the session (presentationContextProvider is weak).
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("bitwarden")) { @Sendable [anchor] callback, error in
                withExtendedLifetime(anchor) {}
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Cancelled.byUser)
                } else {
                    continuation.resume(throwing: error ?? Cancelled.byUser)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false // keep the IdP's own session (and its SSO) if any
            withExtendedLifetime(anchor) { _ = session.start() }
        }
    }
}
