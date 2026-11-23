import Foundation
import Testing
import TriCrypto
@testable import VaultwardenAPI

/// Bitwarden's bank account (6), driver's licence (7) and passport (8) items: read, created, edited, moved, exported
/// and imported under the official property names, with properties a newer server adds carried along untouched.
@Suite struct DocumentTypesTests {
    let key = try! SymmetricKeyPair(combined: Data((0..<64).map(UInt8.init)))
    let orgKey = try! SymmetricKeyPair(combined: Data((0..<64).map { UInt8(200 - $0) }))

    func enc(_ s: String) throws -> String { try EncString.encrypt(Data(s.utf8), with: key).description }
    func dec(_ any: Any?, _ k: SymmetricKeyPair? = nil) -> String? {
        (any as? String).flatMap { try? EncString($0).decryptString(with: k ?? key) }
    }

    @Test func kindsUseBitwardensObjectNames() {
        #expect(CipherEditor.Kind(rawValue: 6) == .bankAccount && CipherEditor.Kind.bankAccount.propertyObject == "bankAccount")
        #expect(CipherEditor.Kind(rawValue: 7) == .driversLicense && CipherEditor.Kind.driversLicense.propertyObject == "driversLicense")
        #expect(CipherEditor.Kind(rawValue: 8) == .passport && CipherEditor.Kind.passport.propertyObject == "passport")
        #expect(CipherEditor.Kind(rawValue: 9) == nil)
        #expect(DocumentField.bankAccount.map(\.key) == ["bankName", "nameOnAccount", "accountType", "accountNumber", "routingNumber",
                                                         "branchNumber", "pin", "swiftCode", "iban", "bankContactPhone"])
        #expect(DocumentField.passport.filter(\.secret).map(\.key) == ["passportNumber", "nationalIdentificationNumber"])
    }

    @Test func syncDecodesEachDocumentAndSkipsOddShapes() throws {
        let sync = Data("""
        {"profile":{"id":"u","email":"synthetic@example.com","key":""},"ciphers":[
          {"id":"b","type":6,"name":"n","bankAccount":{"bankName":"\(try enc("Acorn Bank"))","iban":null,"futureList":[1,2]}},
          {"Id":"d","Type":7,"Name":"n","DriversLicense":{"LicenseNumber":"\(try enc("D123"))"}},
          {"id":"p","type":8,"name":"n","passport":{"passportNumber":"\(try enc("X9"))"},"bankAccount":{"bankName":"ignored"}}]}
        """.utf8)
        let ciphers = try SyncResponse.decode(sync).ciphers
        #expect(dec(ciphers[0].document?["bankName"]) == "Acorn Bank")
        #expect(ciphers[0].document?["iban"] == nil && ciphers[0].document?["futureList"] == nil)
        #expect(dec(ciphers[1].document?["licenseNumber"]) == "D123", "older Vaultwarden's PascalCase")
        #expect(dec(ciphers[2].document?["passportNumber"]) == "X9", "only the type's own object is read")
    }

    @Test(arguments: [CipherEditor.Kind.bankAccount, .driversLicense, .passport])
    func aNewDocumentHasItsObject(_ kind: CipherEditor.Kind) throws {
        var edit = CipherEdit(name: "Mine")
        let secrets = DocumentField.fields(for: kind).filter(\.secret)
        let field = try #require(secrets.first)
        edit.properties = [field.key: "S3CRET"]
        let body = try #require(JSONSerialization.jsonObject(with: CipherEditor.newCipher(kind: kind, edit: edit, key: key)) as? [String: Any])
        #expect(body["type"] as? Int == kind.rawValue)
        let object = try #require(body[kind.propertyObject!] as? [String: Any])
        #expect(dec(object[field.key]) == "S3CRET")
        #expect(body["login"] == nil && body["identity"] == nil)
    }

    @Test func editingKeepsTheItemKeyUnknownPropertiesAndRevision() throws {
        let raw = Data("""
        {"id":"b","type":6,"key":"2.item|key|wrapped","revisionDate":"2026-11-01T00:00:00Z","name":"\(try enc("Bank"))",
         "bankAccount":{"bankName":"\(try enc("Acorn"))","accountNumber":"\(try enc("111"))","overdraftLimit":"2.opaque|x|y"},
         "passwordHistory":[{"password":"2.old|x|y","lastUsedDate":"2026-01-01T00:00:00Z"}],"future":{"keep":true}}
        """.utf8)
        var edit = CipherEdit()
        edit.properties = ["accountNumber": "222", "bankName": ""]
        let patched = try #require(JSONSerialization.jsonObject(with: CipherEditor.updatedCipher(raw: raw, edit: edit, key: key)) as? [String: Any])
        let object = try #require(patched["bankAccount"] as? [String: Any])
        #expect(dec(object["accountNumber"]) == "222")
        #expect(object["bankName"] is NSNull, "an emptied field is cleared")
        #expect(object["overdraftLimit"] as? String == "2.opaque|x|y")
        #expect(patched["key"] as? String == "2.item|key|wrapped")
        #expect(patched["lastKnownRevisionDate"] as? String == "2026-11-01T00:00:00Z")
        #expect((patched["passwordHistory"] as? [[String: Any]])?.count == 1)
        #expect((patched["future"] as? [String: Any])?["keep"] as? Bool == true)
    }

    @Test func movingToAnOrganizationReencryptsTheDocument() throws {
        let raw: [String: Any] = ["id": "p", "type": 8, "name": try enc("Passport"), "revisionDate": "2026-11-01T00:00:00Z",
                                  "passport": ["passportNumber": try enc("X9"), "visaPages": try enc("48")]]
        let shared = try CipherEditor.sharedCipher(raw: JSONSerialization.data(withJSONObject: raw), key: key,
                                                   organizationKey: orgKey, organizationId: "o1")
        let passport = try #require(shared["passport"] as? [String: Any])
        #expect(dec(passport["passportNumber"], orgKey) == "X9")
        #expect(dec(passport["visaPages"], orgKey) == "48", "a property this client doesn't know moves too")
    }

    @Test func exportAndImportRoundTripTheDocument() throws {
        let sync = try JSONSerialization.data(withJSONObject: [
            "profile": ["id": "u", "email": "synthetic@example.com", "key": ""],
            "ciphers": [["id": "d", "type": 7, "name": try enc("Licence"), "reprompt": 1,
                         "driversLicense": ["licenseNumber": try enc("D123"), "licenseClass": try enc("B"),
                                            "endorsements": try enc("Motorcycle")]]],
        ] as [String: Any])
        let (folders, items) = try VaultExport.plainVault(syncData: sync, userKey: key)
        let exported = try #require(items.first)
        let licence = try #require(exported["driversLicense"] as? [String: Any])
        #expect(licence["licenseNumber"] as? String == "D123" && licence["endorsements"] as? String == "Motorcycle")

        let file = try VaultExport.json(folders: folders, items: items)
        let preview = try VaultImport.preview(file)
        #expect(preview.problems.isEmpty)
        let imported = try #require(preview.items.first)
        #expect(imported.type == 7 && imported.json["reprompt"] as? Int == 1)
        let back = try #require(imported.json["driversLicense"] as? [String: Any])
        #expect(back["licenseClass"] as? String == "B" && back["endorsements"] as? String == "Motorcycle")

        // CSV has no columns for documents: they are counted as skipped, never written half-empty.
        #expect(VaultExport.csv(folders: folders, items: items).skipped == 1)
    }

    @Test func keePassKeepsEveryProperty() throws {
        let items: [[String: Any]] = [
            ["id": "0e3a1f10-2222-4c4c-8888-0000000000b6", "type": 6, "name": "Acorn",
             "bankAccount": ["bankName": "Acorn Bank", "iban": "GB00 0000", "pin": "1234", "overdraft": "500"]],
            ["id": "0e3a1f10-2222-4c4c-8888-0000000000b8", "type": 8, "name": "Passport",
             "passport": ["surname": "Sagi", "passportNumber": "X9"]],
        ]
        let file = try KeePassExport.kdbx(folders: [], items: items, databaseName: "Personal", password: "p",
                                          kdf: KeePassExport.KDF(iterations: 2, memoryMiB: 8, parallelism: 1))
        let db = try KDBXReader.read(file, password: "p")
        let bank = try #require(db.root.entries.first { $0["Title"] == "Acorn" })
        let passport = try #require(db.root.entries.first { $0["Title"] == "Passport" })
        #expect(bank["Bank name"] == "Acorn Bank" && bank["IBAN"] == "GB00 0000" && bank["PIN"] == "1234" && bank["overdraft"] == "500")
        #expect(passport["Surname"] == "Sagi" && passport["Passport number"] == "X9")
        #expect(db.protected.contains("IBAN") && db.protected.contains("Passport number") && !db.protected.contains("Bank name"))
    }

    @Test func searchTokensNameEachType() {
        #expect(SearchToken("type:bank") == .type(.bankAccount))
        #expect(SearchToken("type:bank-account") == .type(.bankAccount))
        #expect(SearchToken("type:licence") == .type(.driversLicense))
        #expect(SearchToken("type:drivers_license") == .type(.driversLicense))
        #expect(SearchToken("type:passport") == .type(.passport))
        #expect(SearchToken.type(.driversLicense).text == "type:license")
        #expect(SearchToken(SearchToken.type(.bankAccount).text) == .type(.bankAccount))
    }

    @Test func subtitlesFollowTheOfficialClients() {
        func values(_ d: [String: String]) -> (String) -> String? { { d[$0] } }
        #expect(DocumentField.subtitle(for: .bankAccount, values(["bankName": "Acorn Bank"])) == "Acorn Bank")
        #expect(DocumentField.subtitle(for: .driversLicense, values(["firstName": "U", "lastName": "Sagi", "issuingState": "CA"])) == "U Sagi, CA")
        #expect(DocumentField.subtitle(for: .passport, values(["givenName": "U", "surname": "Sagi", "issuingCountry": "JP"])) == "U Sagi, JP")
        #expect(DocumentField.subtitle(for: .passport, values([:])) == nil)
    }
}
