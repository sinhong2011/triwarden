import TriCrypto
import Foundation
import Testing
@testable import VaultwardenAPI

/// Drives the whole OIDC flow headlessly against the dev stack's dex + SSO-enabled Vaultwarden
/// (`DevServer/compose.yml`): browser redirects and dex's password form are played with URLSession.
@Suite struct SSOTests {
    static var ip: String? { ProcessInfo.processInfo.environment["TRIWARDEN_DEV_IP"] }

    /// Follows redirects like a browser but stops at the `bitwarden://` callback.
    final class Browser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        var callback: URL?
        lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            if request.url?.scheme == "bitwarden" { callback = request.url; return nil }
            return request
        }
    }

    /// Plays dex's local password form for `login` and returns the `bitwarden://` callback.
    static func signIn(_ start: VaultClient.SSOStart, login: String) async throws -> URL {
        let browser = Browser()
        // Authorize → Vaultwarden → dex login page (local connector form).
        let (pageData, pageResponse) = try await browser.session.data(from: start.authorizeURL)
        let page = String(decoding: pageData, as: UTF8.self)
        var loginURL = try #require(pageResponse.url)
        if let range = page.range(of: #"href="(/dex/auth/local[^"]*)""#, options: .regularExpression) {
            let path = String(page[range]).dropFirst(6).dropLast().replacingOccurrences(of: "&amp;", with: "&")
            loginURL = URL(string: path, relativeTo: loginURL)!.absoluteURL
            _ = try await browser.session.data(from: loginURL)
        }
        let action = page.range(of: #"action="([^"]*)""#, options: .regularExpression).map {
            String(page[$0]).dropFirst(8).dropLast().replacingOccurrences(of: "&amp;", with: "&")
        }
        var post = URLRequest(url: action.flatMap { URL(string: $0, relativeTo: loginURL)?.absoluteURL } ?? loginURL)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data("login=\(login.replacingOccurrences(of: "@", with: "%40"))&password=chiikawa-dev-password".utf8)
        _ = try? await browser.session.data(for: post)
        return try #require(browser.callback, "no bitwarden:// callback")
    }

    @Test func ssoThenMasterPassword() async throws {
        guard let ip = Self.ip else { return } // set TRIWARDEN_DEV_IP to run
        let client = VaultClient(environment: .selfHosted(URL(string: "http://\(ip):18881")!), deviceIdentifier: UUID().uuidString)
        let start = try await client.beginSSO(identifier: "triwarden")
        #expect(start.authorizeURL.absoluteString.contains("code_challenge_method=S256"))

        let callback = try await Self.signIn(start, login: "usagi@chiikawarden.test")

        let session = try await client.finishSSO(callback: callback, start: start)
        #expect(session.email == "usagi@chiikawarden.test" && session.refreshToken != nil)
        #expect(throws: APIError.self) { try client.unlockSSO(session, password: "wrong") }
        let userKey = try client.unlockSSO(session, password: "chiikawa-dev-password")
        let names = try await client.sync().ciphers.compactMap { try? EncString($0.name).decryptString(with: userKey) }
        #expect(names.contains("GitHub"))

        // A forged callback is refused.
        await #expect(throws: APIError.self) {
            _ = try await client.finishSSO(callback: URL(string: "bitwarden://sso-callback?code=x&state=nope")!, start: start)
        }
    }

    /// TOTP after single sign-on: the code goes with the same authorization-code exchange (a password grant would be
    /// refused by an SSO-only server), and a mistyped code leaves the callback usable for another try.
    @Test func ssoThenTwoStep() async throws {
        guard let ip = Self.ip else { return } // set TRIWARDEN_DEV_IP to run
        let client = VaultClient(environment: .selfHosted(URL(string: "http://\(ip):18881")!), deviceIdentifier: UUID().uuidString)
        let start = try await client.beginSSO(identifier: "triwarden")
        let callback = try await Self.signIn(start, login: "momonga@chiikawarden.test")

        await #expect(throws: APIError.twoFactorRequired(providers: ["0"])) {
            _ = try await client.finishSSO(callback: callback, start: start)
        }
        await #expect(throws: APIError.self) {
            _ = try await client.finishSSO(callback: callback, start: start, twoFactor: ("0", "000000"))
        }
        // Vaultwarden refuses a code already used in this time step; its drift window accepts the next one.
        let totp = TOTP(DevServer.twoFactorSecret(port: 18881))!
        let session: VaultClient.SSOSession
        do {
            session = try await client.finishSSO(callback: callback, start: start, twoFactor: ("0", totp.code()))
        } catch {
            session = try await client.finishSSO(callback: callback, start: start,
                                                 twoFactor: ("0", totp.code(at: .now.addingTimeInterval(30))))
        }
        #expect(session.email == "momonga@chiikawarden.test")
        _ = try client.unlockSSO(session, password: DevServer.password)
    }
}
