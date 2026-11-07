import Foundation
import Testing
@testable import VaultwardenAPI

/// The KeePass export end to end against a seeded server: sync the real vault, export it with the default
/// Argon2id settings, then open the file with the independent reader in KeePassExportTests.
/// `KDBX_DEV_OUT=/path/prefix` also writes each file (`prefix-<port>-personal.kdbx`, …) for other tools.
@Suite(.enabled(if: DevServer.enabled, "set TRIWARDEN_DEV_HOST to run"), .serialized)
struct DevServerKeePassExportTests {
    static let filePassword = "kdbx-file-password"

    static func allEntries(_ g: KDBXReader.Group) -> [KDBXReader.Entry] {
        g.entries + g.groups.flatMap(allEntries)
    }

    static func write(_ file: Data, port: Int, name: String) throws {
        guard let prefix = DevServer.env["KDBX_DEV_OUT"] else { return }
        try file.write(to: URL(filePath: "\(prefix)-\(port)-\(name).kdbx"))
    }

    @Test(arguments: DevServer.ports)
    func personalVaultOpensAsKeePass(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "usagi@chiikawarden.test", password: DevServer.password)
        let vault = try VaultExport.plainVault(syncData: try await client.syncData(), userKey: userKey)
        let file = try KeePassExport.kdbx(folders: vault.folders, items: vault.items, databaseName: "Triwarden",
                                          password: Self.filePassword)
        try Self.write(file, port: port, name: "personal")

        #expect(throws: KDBXReader.Failure.wrongPassword) { try KDBXReader.read(file, password: "wrong") }
        let db = try KDBXReader.read(file, password: Self.filePassword)
        #expect(db.root.name == "Triwarden")
        let entries = Self.allEntries(db.root)
        #expect(entries.count == vault.items.count)
        func entry(_ title: String) throws -> KDBXReader.Entry { try #require(entries.first { $0["Title"] == title }) }

        let github = try entry("GitHub")
        #expect(github["UserName"] == "usagi" && github["Password"] == "m7Kq#vR2!tLp9wZe$Hu")
        #expect(github["URL"] == "https://github.com" && github.tags == "Favorite")
        #expect(github["otp"]?.hasPrefix("otpauth://totp/") == true)
        #expect(github["otp"]?.contains("secret=\(DevServer.totpSecret)") == true)
        #expect(try entry("ちいかわ ショップ")["Password"] == "日本語パスワード🍓")
        #expect(try entry("GitHub recovery")["Notes"] == "abcd-1234\nefgh-5678")
        let visa = try entry("Travel Visa")
        #expect(visa["Number"] == "4111111111111111" && visa["Security code"] == "123" && visa["Expiry year"] == "2029")
        #expect(try entry("Usagi identity")["Email"] == "usagi@chiikawarden.test")
        #expect(db.protected.isSuperset(of: ["Password", "otp", "Number", "Security code"]))
    }

    @Test(arguments: DevServer.ports)
    func organizationVaultOpensAsKeePass(port: Int) async throws {
        let client = try DevServer.client(port: port)
        let userKey = try await client.login(email: "usagi@chiikawarden.test", password: DevServer.password)
        let data = try await client.syncData()
        let org = try #require(try SyncResponse.decode(data).profile.organizations?.first { $0.name == "Chiikawa Family" })
        let vault = try VaultExport.organizationVault(syncData: data, userKey: userKey, organizationId: org.id)
        let file = try KeePassExport.kdbx(collections: vault.collections, items: vault.items, databaseName: "Chiikawa Family",
                                          password: Self.filePassword)
        try Self.write(file, port: port, name: "organization")

        let db = try KDBXReader.read(file, password: Self.filePassword)
        #expect(db.root.name == "Chiikawa Family")
        let shared = try #require(db.root.groups.first { $0.name == "Shared" })
        let netflix = try #require(shared.entries.first { $0["Title"] == "Family Netflix" })
        #expect(netflix["Password"] == "shared-Dev-Only-42!" && netflix["URL"] == "https://netflix.com")
    }
}
