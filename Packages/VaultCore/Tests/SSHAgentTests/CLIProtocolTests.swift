import Darwin
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

    @Test func matchCanAskToBringTheWindowForward() throws {
        let asking = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match","foreground":true}"#.utf8))
        #expect(asking.foreground == true)
        let background = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match"}"#.utf8))
        #expect(background.foreground == nil)
        let menu = try JSONDecoder().decode(CLIRequest.self, from: Data(#"{"command":"match","silent":true}"#.utf8))
        #expect(menu.silent == true)
    }

    @Test func lockedFailureHasAStableCode() throws {
        let json = try object(.failure("The vault is locked. Unlock Triwarden first.", code: "vault_locked"))
        #expect(json["code"] as? String == "vault_locked")
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

    @Test func generateRequestCarriesPasswordOptions() throws {
        let data = Data(#"""
        {"command":"generate","length":24,"uppercase":true,"lowercase":true,"digits":false,"symbols":true,"avoidAmbiguous":true,"minNumbers":2,"minSpecial":1}
        """#.utf8)
        let req = try JSONDecoder().decode(CLIRequest.self, from: data)
        #expect(req.command == .generate)
        #expect(req.length == 24)
        #expect(req.digits == false)
        #expect(req.minNumbers == 2)
        #expect(req.symbols == true)
    }

    @Test func generateReplyEchoesOptionsAndEntropy() throws {
        var reply = CLIResponse(ok: true, value: "Ab1!", length: 20, uppercase: true, lowercase: true,
                                digits: true, symbols: true, avoidAmbiguous: true, minNumbers: 1,
                                minSpecial: 1, entropyBits: 110)
        let json = try object(reply)
        #expect(json["value"] as? String == "Ab1!")
        #expect(json["length"] as? Int == 20)
        #expect(json["uppercase"] as? Bool == true)
        #expect((json["entropyBits"] as? NSNumber)?.doubleValue == 110)
        // A passphrase reply uses length as word count and carries separator fields.
        reply = CLIResponse(ok: true, value: "a-b-c", length: 6, separator: "-", capitalize: false,
                            includeNumber: true, entropyBits: 80)
        let phrase = try object(reply)
        #expect(phrase["separator"] as? String == "-")
        #expect(phrase["includeNumber"] as? Bool == true)
    }


    @Test func failureCarriesAnOptionalCode() throws {
        let json = try object(.failure("Triwarden isn't running — open Triwarden to use the browser extension.",
                                       code: "app_not_running"))
        #expect(json["ok"] as? Bool == false)
        #expect(json["code"] as? String == "app_not_running")
        #expect((json["error"] as? String)?.contains("open Triwarden") == true)
        // Older clients that omit code still decode.
        let plain = try JSONDecoder().decode(CLIResponse.self, from: Data(#"{"ok":false,"error":"x"}"#.utf8))
        #expect(plain.code == nil)
        #expect(plain.error == "x")
    }

    @Test func unavailableMapsStaleSocketToAppNotRunning() {
        let reply = BridgeClient.unavailableResponse(errno: ECONNREFUSED, bridgeWanted: nil)
        #expect(reply.code == "app_not_running")
        #expect(reply.error?.contains("open Triwarden") == true)
    }

    @Test func unavailableMapsWantedFlagToAppNotRunningEvenWithoutSocket() {
        let reply = BridgeClient.unavailableResponse(errno: ENOENT, bridgeWanted: true)
        #expect(reply.code == "app_not_running")
    }

    @Test func unavailableMapsDisabledSettingSeparately() {
        let reply = BridgeClient.unavailableResponse(errno: ENOENT, bridgeWanted: false)
        #expect(reply.code == "connection_disabled")
        #expect(reply.error?.contains("Settings") == true)
    }

    @Test func unavailableWithoutFlagPrefersOpenApp() {
        let reply = BridgeClient.unavailableResponse(errno: ENOENT, bridgeWanted: nil)
        #expect(reply.code == "app_not_running")
    }
}
