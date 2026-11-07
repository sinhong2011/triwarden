import CryptoKit
import Foundation
import Testing
import TriCrypto
@testable import VaultwardenAPI

@Suite struct KeePassExportTests {
    /// Light enough for tests; the file records whatever it was written with.
    let fastKDF = KeePassExport.KDF(iterations: 2, memoryMiB: 8, parallelism: 1)

    nonisolated(unsafe) static let folders: [[String: Any]] = [
        ["id": "6f1c1a0e-1111-4c4c-8888-000000000001", "name": "Work"],
        ["id": "6f1c1a0e-1111-4c4c-8888-000000000002", "name": "Work/Servers"],
    ]
    nonisolated(unsafe) static let items: [[String: Any]] = [
        ["id": "0e3a1f10-2222-4c4c-8888-000000000001", "type": 1, "name": "GitHub", "favorite": true,
         "folderId": "6f1c1a0e-1111-4c4c-8888-000000000002", "notes": "a & b < c",
         "revisionDate": "2025-03-04T05:06:07.123Z", "creationDate": "2024-01-02T03:04:05Z",
         "fields": [["name": "PIN", "value": "0420", "type": 1], ["name": "PIN", "value": "second", "type": 0],
                    ["name": "Who", "type": 3, "linkedId": 100], ["name": "Password", "value": "clash", "type": 0]],
         "passwordHistory": [["password": "older", "lastUsedDate": "2024-06-01T00:00:00Z"],
                             ["password": "oldest", "lastUsedDate": "2024-02-01T00:00:00Z"]],
         "login": ["username": "usagi", "password": "pw\u{1}1", "totp": "jbsw y3dp",
                   "uris": [["uri": "https://github.com"], ["uri": "https://gist.github.com"]],
                   "fido2Credentials": [["credentialId": "6f1c1a0e-1111-4c4c-8888-0000000000ff", "keyValue": "AQID",
                                         "rpId": "github.com", "userHandle": "dXNlcg", "userName": "usagi"]]]],
        ["id": "0e3a1f10-2222-4c4c-8888-000000000002", "type": 2, "name": "Note", "notes": "secret",
         "folderId": "6f1c1a0e-1111-4c4c-8888-000000000001"],
        ["id": "0e3a1f10-2222-4c4c-8888-000000000003", "type": 3, "name": "Visa",
         "card": ["cardholderName": "U Sagi", "number": "4111111111111111", "code": "123", "expMonth": "4", "expYear": "2030"],
         "fields": [["name": "Number again", "type": 3, "linkedId": 305]]],
        ["id": "0e3a1f10-2222-4c4c-8888-000000000004", "type": 4, "name": "Me",
         "identity": ["firstName": "U", "lastName": "Sagi", "username": "usagi", "ssn": "123-45-6789"]],
        ["id": "0e3a1f10-2222-4c4c-8888-000000000005", "type": 5, "name": "Server key",
         "sshKey": ["privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----", "publicKey": "ssh-ed25519 AAAA", "keyFingerprint": "SHA256:x"]],
    ]

    @Test func chaCha20MatchesRFC8439BlockVector() {
        var c = ChaCha20(key: Data(0..<32), nonce: Data([0, 0, 0, 9, 0, 0, 0, 0x4A, 0, 0, 0, 0]), counter: 1)
        let block = c.apply(Data(count: 64))
        #expect(block.map { String(format: "%02x", $0) }.joined() ==
            "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e")
        // The stream carries on across calls.
        var whole = ChaCha20(key: Data(0..<32), nonce: Data(count: 12))
        var split = ChaCha20(key: Data(0..<32), nonce: Data(count: 12))
        #expect(whole.apply(Data(count: 150)) == split.apply(Data(count: 7)) + split.apply(Data(count: 143)))
    }

    @Test func writesADatabaseThatDecryptsWithThePassword() throws {
        let file = try KeePassExport.kdbx(folders: Self.folders, items: Self.items, databaseName: "Personal",
                                          password: "file-pass", kdf: fastKDF)
        if let out = ProcessInfo.processInfo.environment["KDBX_OUT"] { try file.write(to: URL(fileURLWithPath: out)) }
        let db = try KDBXReader.read(file, password: "file-pass")
        #expect(throws: KDBXReader.Failure.wrongPassword) { try KDBXReader.read(file, password: "nope") }

        #expect(db.root.name == "Personal")
        let work = try #require(db.root.groups.first { $0.name == "Work" })
        let servers = try #require(work.groups.first { $0.name == "Servers" })
        #expect(work.entries.map { $0["Title"] } == ["Note"])
        #expect(db.root.entries.map { $0["Title"] } == ["Visa", "Me", "Server key"])

        let gh = try #require(servers.entries.first)
        #expect(gh["UserName"] == "usagi" && gh["Password"] == "pw1" && gh["URL"] == "https://github.com")
        #expect(gh["Notes"] == "a & b < c" && gh["KP2A_URL"] == "https://gist.github.com")
        #expect(gh["otp"] == "otpauth://totp/GitHub:usagi?secret=JBSWY3DP&period=30&digits=6&algorithm=SHA1")
        #expect(gh["PIN"] == "0420" && gh["PIN (2)"] == "second" && gh["Who"] == "{USERNAME}" && gh["Password (2)"] == "clash")
        #expect(gh["KPEX_PASSKEY_CREDENTIAL_ID"] == "bxwaDhERTEyIiAAAAAAA_w")
        #expect(gh["KPEX_PASSKEY_PRIVATE_KEY_PEM"] == "-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----")
        #expect(db.protected.contains("PIN") && db.protected.contains("otp") && !db.protected.contains("PIN (2)"))
        #expect(gh.tags == "Favorite")
        #expect(gh.history.map { $0["Password"] } == ["oldest", "older"])

        let card = db.root.entries[0], me = db.root.entries[1], ssh = db.root.entries[2]
        #expect(card["Number"] == "4111111111111111" && card["Security code"] == "123" && card["Number again"] == "{S:Number}")
        #expect(me["UserName"] == "usagi" && me["Social Security number"] == "123-45-6789" && me["First name"] == "U")
        #expect(ssh["Private key"] == "-----BEGIN OPENSSH PRIVATE KEY-----" && ssh["Fingerprint"] == "SHA256:x")
    }

    @Test func organizationCollectionsBecomeGroups() throws {
        let collections: [[String: Any]] = [["id": "c1", "name": "Shared"], ["id": "c2", "name": "Ops/Prod"]]
        let items: [[String: Any]] = [["type": 2, "name": "Runbook", "collectionIds": ["c2", "c1"]], ["type": 2, "name": "Loose"]]
        let file = try KeePassExport.kdbx(collections: collections, items: items, databaseName: "Acme", password: "p", kdf: fastKDF)
        let db = try KDBXReader.read(file, password: "p")
        #expect(db.root.groups.first { $0.name == "Shared" }?.entries.map { $0["Title"] } == ["Runbook"])
        #expect(db.root.groups.first { $0.name == "Ops" }?.groups.first?.name == "Prod")
        #expect(db.root.entries.map { $0["Title"] } == ["Loose"])
    }

    @Test func otpConversions() {
        typealias F = KeePassExport.EntryFields
        #expect(F.otpauth("otpauth://totp/x?secret=A", title: "t", username: "") == "otpauth://totp/x?secret=A")
        #expect(F.otpauth("steam://ABC", title: "Steam", username: "") == "otpauth://totp/Steam?secret=ABC&issuer=Steam&encoder=steam")
        #expect(F.otpauth("abc", title: "My Site", username: "") == "otpauth://totp/My%20Site?secret=ABC&period=30&digits=6&algorithm=SHA1")
    }
}

/// An independent minimal KDBX 4 reader: checks every hash and HMAC, decrypts, and unprotects values in order.
enum KDBXReader {
    enum Failure: Error, Equatable { case format, wrongPassword, corrupt }

    final class Group {
        var name = ""
        var entries: [Entry] = []
        var groups: [Group] = []
    }
    final class Entry {
        var strings: [String: String] = [:]
        var tags = ""
        var history: [Entry] = []
        subscript(key: String) -> String? { strings[key] }
    }
    struct Database { var root: Group; var protected: Set<String> }

    /// A little-endian unsigned integer from a few bytes.
    static func le(_ bytes: ArraySlice<UInt8>) -> Int {
        var v = 0
        for byte in bytes.reversed() { v = v << 8 | Int(byte) }
        return v
    }

    static func read(_ file: Data, password: String) throws -> Database {
        let b = [UInt8](file)
        func u32(_ i: Int) -> Int { le(b[i..<(i + 4)]) }
        guard Array(b[0..<8]) == KeePassExport.signature, b[8...11] == [0, 0, 4, 0] else { throw Failure.format }
        var i = 12
        var fields: [UInt8: Data] = [:]
        while true {
            let id = b[i], len = u32(i + 1)
            fields[id] = Data(b[(i + 5)..<(i + 5 + len)])
            i += 5 + len
            if id == 0 { break }
        }
        let header = Data(b[0..<i])
        guard Data(b[i..<(i + 32)]) == Data(SHA256.hash(data: header)) else { throw Failure.corrupt }
        guard let seed = fields[4], let iv = fields[7], let params = fields[11],
              fields[2] == KeePassExport.chaCha20Cipher else { throw Failure.format }

        // VariantDictionary
        var kdf: [String: Data] = [:]
        let p = [UInt8](params)
        var j = 2
        while p[j] != 0 {
            let kl = le(p[(j + 1)..<(j + 5)]), keyEnd = j + 5 + kl
            let key = String(decoding: p[(j + 5)..<keyEnd], as: UTF8.self)
            let vl = le(p[keyEnd..<(keyEnd + 4)])
            kdf[key] = Data(p[(keyEnd + 4)..<(keyEnd + 4 + vl)])
            j = keyEnd + 4 + vl
        }
        func int(_ k: String) -> Int { kdf[k]!.reversed().reduce(0) { $0 << 8 | Int($1) } }
        guard kdf["$UUID"] == KeePassExport.argon2idKDF, int("V") == 0x13 else { throw Failure.format }
        let composite = Data(SHA256.hash(data: Data(SHA256.hash(data: Data(password.utf8)))))
        let transformed = try KDF.argon2id(password: composite, salt: kdf["S"]!, iterations: int("I"),
                                           memoryKiB: int("M") / 1024, parallelism: int("P"))
        let hmacBase = Data(SHA512.hash(data: seed + transformed + Data([1])))
        guard Data(b[(i + 32)..<(i + 64)]) == KeePassExport.hmac(header, index: .max, base: hmacBase) else { throw Failure.wrongPassword }

        var payload = Data()
        var at = i + 64, index: UInt64 = 0
        while true {
            let mac = Data(b[at..<(at + 32)]), size = u32(at + 32)
            let chunk = Data(b[(at + 36)..<(at + 36 + size)])
            let signed = KeePassExport.Bytes.le(index) + Data(b[(at + 32)..<(at + 36)]) + chunk
            guard mac == KeePassExport.hmac(signed, index: index, base: hmacBase) else { throw Failure.corrupt }
            payload += chunk
            at += 36 + size
            index += 1
            if size == 0 { break }
        }
        guard at == b.count else { throw Failure.corrupt }
        var cipher = ChaCha20(key: Data(SHA256.hash(data: seed + transformed)), nonce: iv)
        let plain = [UInt8](cipher.apply(payload))
        var k = 0
        var inner: [UInt8: Data] = [:]
        while true {
            let id = plain[k]
            let len = le(plain[(k + 1)..<(k + 5)])
            inner[id] = Data(plain[(k + 5)..<(k + 5 + len)])
            k += 5 + len
            if id == 0 { break }
        }
        guard inner[1] == KeePassExport.Bytes.le(UInt32(3)), let innerKey = inner[2] else { throw Failure.format }
        let parser = XMLParser(data: Data(plain[k...]))
        let delegate = Delegate(stream: KeePassExport.InnerStream(key: innerKey))
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw Failure.format }
        return Database(root: root, protected: delegate.protectedKeys)
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var stream: KeePassExport.InnerStream
        var root: Group?
        var groups: [Group] = []
        var entries: [Entry] = []
        var path: [String] = []
        var text = ""
        var key = ""
        var protectedValue = false
        var protectedKeys: Set<String> = []
        init(stream: KeePassExport.InnerStream) { self.stream = stream }

        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(e); text = ""
            switch e {
            case "Group": let g = Group(); if root == nil { root = g } else { groups.last?.groups.append(g) }; groups.append(g)
            case "Entry":
                let entry = Entry()
                if path.dropLast().last == "History" { entries.last?.history.append(entry) } else { groups.last?.entries.append(entry) }
                entries.append(entry)
            case "Value": protectedValue = attributes["Protected"] == "True"
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            path.removeLast()
            switch e {
            case "Group": groups.removeLast()
            case "Entry": entries.removeLast()
            case "Name" where path.last == "Group": groups.last?.name = text
            case "Tags": entries.last?.tags = text
            case "Key": key = text
            case "Value":
                var value = text
                if protectedValue {
                    // XOR with the inner stream in document order: encrypting again decrypts.
                    var s = stream.cipher
                    value = String(decoding: s.apply(Data(base64Encoded: text) ?? Data()), as: UTF8.self)
                    stream.cipher = s
                    if entries.count == 1 { protectedKeys.insert(key) }
                }
                entries.last?.strings[key] = value
            default: break
            }
        }
    }
}
