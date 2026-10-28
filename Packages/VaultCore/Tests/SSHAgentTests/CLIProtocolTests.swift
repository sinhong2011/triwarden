import Foundation
import Testing
@testable import SSHAgent

/// The browser extension reads these JSON field names (BrowserExtension/WebExtension/lib/protocol.ts).
struct CLIProtocolTests {
    private func object(_ response: CLIResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
    }

    @Test func fillCarriesTheCodeAndItsCountdown() throws {
        let json = try object(.credentials(username: "u", password: "p", totp: "123456", totpRemaining: 17, totpPeriod: 30))
        #expect(json["totp"] as? String == "123456")
        #expect(json["totpRemaining"] as? Int == 17)
        #expect(json["totpPeriod"] as? Int == 30)
    }

    @Test func fillWithoutACodeLeavesTheFieldsOut() throws {
        let json = try object(.credentials(username: "u", password: "p", totp: nil))
        #expect(json["totp"] == nil)
        #expect(json["totpRemaining"] == nil)
        #expect(json["totpPeriod"] == nil)
    }

    @Test func matchRowsSayWhetherALoginHasACode() throws {
        let json = try object(.list([
            .init(id: "1", name: "With", detail: "a", totpPeriod: 60),
            .init(id: "2", name: "Without", detail: "b"),
        ]))
        let rows = try #require(json["rows"] as? [[String: Any]])
        #expect(rows[0]["totpPeriod"] as? Int == 60)
        #expect(rows[1]["totpPeriod"] == nil)
        // The code itself never rides along with a match.
        #expect(rows[0]["totp"] == nil)
    }

    @Test func matchCarriesIconCodeAndTheAutoShowSetting() throws {
        let json = try object(.list([.init(id: "1", name: "n", detail: "d", totpPeriod: 30, icon: "iVBOR", code: "123456")],
                                    autoShow: true))
        #expect(json["autoShow"] as? Bool == true)
        let row = try #require((json["rows"] as? [[String: Any]])?.first)
        #expect(row["icon"] as? String == "iVBOR")
        #expect(row["code"] as? String == "123456")
    }

    @Test func matchRowsCarryTheExactAndPasskeyFlags() throws {
        let json = try object(.list([
            .init(id: "1", name: "a", detail: "d", exact: true, passkey: true),
            .init(id: "2", name: "b", detail: "d"),
        ]))
        let rows = try #require(json["rows"] as? [[String: Any]])
        #expect(rows[0]["exact"] as? Bool == true)
        #expect(rows[0]["passkey"] as? Bool == true)
        #expect(rows[1]["exact"] == nil)
        #expect(rows[1]["passkey"] == nil)
    }

    @Test func requestAsksForCodesOnlyWhenTold() throws {
        let plain = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match","url":"https://a.test"}"#.utf8))
        #expect(plain.codes == nil)
        #expect(plain.reveal == nil)
        let asking = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match","codes":true,"reveal":true}"#.utf8))
        #expect(asking.codes == true)
        #expect(asking.reveal == true)
        // A focus-only request can name codes without revealing them: the app must not read that as a yes.
        let focus = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match","codes":true}"#.utf8))
        #expect(focus.reveal != true)
    }

    @Test func requestCarriesWhereItCameFrom() throws {
        let data = try JSONEncoder().encode(CLIRequest(command: .match, url: "https://a.test", origin: "chrome-extension://x/", browser: "com.google.Chrome"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["origin"] as? String == "chrome-extension://x/")
        #expect(json["browser"] as? String == "com.google.Chrome")
        // An extension that sends none is still understood.
        let plain = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match"}"#.utf8))
        #expect(plain.origin == nil && plain.browser == nil)
    }

    @Test func oldRepliesStillDecode() throws {
        let reply = Data(#"{"ok":true,"rows":[{"id":"1","name":"n","detail":"d"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(CLIResponse.self, from: reply)
        #expect(decoded.rows?.first?.totpPeriod == nil)
    }
}
