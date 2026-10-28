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

    @Test func oldRepliesStillDecode() throws {
        let reply = Data(#"{"ok":true,"rows":[{"id":"1","name":"n","detail":"d"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(CLIResponse.self, from: reply)
        #expect(decoded.rows?.first?.totpPeriod == nil)
    }
}
