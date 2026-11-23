import Foundation
import Testing
@testable import TriCrypto

/// Vectors generated independently with Python `hashlib` + `cryptography`.
@Suite struct CryptoVectorTests {
    let password = "correct horse battery staple"
    let email = "Usagi@Example.com "

    @Test func masterKeyAndHash() throws {
        let mk = try KDF.masterKey(password: password, email: email, config: .pbkdf2(iterations: 600_000))
        #expect(mk.hex == "3898203f6009bc75069cef1c27d71969bf108de2bec508cdb1ac07560101cfdc")
        #expect(try KDF.masterPasswordHash(masterKey: mk, password: password)
            == "tM3u7z89mYXDV19ySBwfDaI4vqo34N/6uwOJpzt8STU=")
    }

    @Test func argon2idMasterKey() throws {
        // Python argon2-cffi: Argon2id(pw, SHA256(email), t=3, m=64MiB, p=4).
        let mk = try KDF.masterKey(password: password, email: "usagi@example.com",
                                   config: .argon2id(iterations: 3, memoryMiB: 64, parallelism: 4))
        #expect(mk.hex == "e9ff586b6f91d9a01a3f44615bff852c3858e680b1c817fea514081e4e779787")
    }

    @Test func stretchAndUnwrapUserKey() throws {
        let mk = Data(hex: "3898203f6009bc75069cef1c27d71969bf108de2bec508cdb1ac07560101cfdc")
        let stretched = try SymmetricKeyPair.stretched(masterKey: mk)
        #expect(stretched.encryptionKey.hex == "adea54e90448cc15d2e8b88c6f002349f9040405675044d16c5fb3b9b18e531e")
        #expect(stretched.macKey.hex == "271a61ce4037d9716749948001776d6948a9b95b9bb2f213e973c72e9bced896")

        let protectedKey = try EncString("2.ZGVmZ2hpamtsbW5vcHFycw==|jZ6MneNz7c3XjtcxcOu6sfZ44ehOnOQMv+MKsW4grVKhTI9Zki3l3V4g2C4nMERCrVdQnnV0IR8H1F7unUPmqKvC1mEPP8xlcOmnuqTurQ0=|2w5uJV1rPnBTSMQdZFLZIskgpte24FNQqJbBbG0+7io=")
        let userKey = try SymmetricKeyPair(combined: protectedKey.decrypt(with: stretched))
        #expect(userKey.encryptionKey == Data(0..<32))

        let name = try EncString("2.AAECAwQFBgcICQoLDA0ODw==|jKfvVupjU0mVa5/2hY3AJg==|GLOSjVfpNbfRdI1N1eJ92VmXUEj9BFR7r79rZ8d6dJA=")
        #expect(try name.decryptString(with: userKey) == "GitHub")
    }

    @Test func tamperedMacIsRejected() throws {
        let key = try SymmetricKeyPair(combined: Data(0..<64))
        let good = try EncString.encrypt(Data("hi".utf8), with: key)
        var mac = good.mac
        mac[0] ^= 1
        let bad = EncString(iv: good.iv, ciphertext: good.ciphertext, mac: mac)
        #expect(throws: CryptoError.macMismatch) { try bad.decrypt(with: key) }
    }

    @Test func roundTripAndSerialization() throws {
        let key = try SymmetricKeyPair(combined: Data((0..<64).reversed()))
        let enc = try EncString.encrypt(Data("ちいかわ".utf8), with: key)
        #expect(try EncString(enc.description).decryptString(with: key) == "ちいかわ")
    }

    @Test(arguments: [
        KDFConfig.pbkdf2(iterations: 5_000),
        .argon2id(iterations: 1, memoryMiB: 64, parallelism: 4),
        .argon2id(iterations: 3, memoryMiB: 4, parallelism: 4),
    ])
    func kdfDowngradeIsRejected(config: KDFConfig) {
        #expect(throws: CryptoError.self) { try config.validate() }
    }

    @Test func legacyEncTypesAreRejected() {
        #expect(throws: CryptoError.unsupportedEncType(0)) { try EncString("0.AAAA|BBBB") }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init(hex: String) {
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        self.init(bytes)
    }
}

/// RFC 6238 Appendix B vectors (SHA-1, 8 digits).
@Suite struct TOTPTests {
    @Test(arguments: [(59.0, "94287082"), (1111111109.0, "07081804"), (2000000000.0, "69279037")])
    func rfcVectors(time: Double, expected: String) {
        let totp = TOTP("otpauth://totp/x?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8")!
        #expect(totp.code(at: Date(timeIntervalSince1970: time)) == expected)
    }

    @Test func rawSecretDefaults() {
        let totp = TOTP("jbsw y3dp ehpk 3pxp")!
        #expect(totp.digits == 6 && totp.period == 30)
        #expect(TOTP("not base32 !") == nil)
    }
}

@Suite struct PasswordGeneratorTests {
    @Test func respectsLengthAndClasses() {
        var g = PasswordGenerator()
        g.length = 32
        for _ in 0..<200 {
            let p = g.generate()
            #expect(p.count == 32)
            let hasAll = p.contains(where: \.isUppercase) && p.contains(where: \.isLowercase) && p.contains(where: \.isNumber)
            let hasSymbol = p.contains { "!@#$%^&*-_=+?".contains($0) }
            let hasAmbiguous = p.contains { "0O1lI".contains($0) }
            #expect(hasAll && hasSymbol && !hasAmbiguous)
        }
    }

    @Test func digitsOnlyPIN() {
        var g = PasswordGenerator()
        (g.uppercase, g.lowercase, g.symbols, g.length) = (false, false, false, 6)
        let pin = g.generate()
        let digitsOnly = pin.allSatisfy(\.isNumber)
        #expect(digitsOnly)
    }

    @Test func uniformIsUnbiased() {
        var counts = [Int](repeating: 0, count: 7)
        for _ in 0..<70_000 { counts[PasswordGenerator.uniform(upTo: 7)] += 1 }
        let even = counts.allSatisfy { abs($0 - 10_000) < 600 }
        #expect(even)
    }
}

@Suite struct SSHKeyTests {
    /// The generated key must be accepted by OpenSSH itself: ssh-keygen derives the same public key and fingerprint.
    @Test func ed25519RoundTripsThroughSSHKeygen() throws {
        let pair = SSHKeyPair.generateEd25519(comment: "test@triwarden")
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keyURL = dir.appending(path: "id_ed25519")
        try pair.privateKey.write(to: keyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)

        func run(_ args: [String]) throws -> String {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/ssh-keygen")
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            try p.run()
            p.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let derivedPublic = try run(["-y", "-f", keyURL.path]).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(derivedPublic.hasPrefix(pair.publicKey.split(separator: " ").prefix(2).joined(separator: " ")))
        let fingerprint = try run(["-l", "-E", "sha256", "-f", keyURL.path])
        #expect(fingerprint.contains(pair.fingerprint))
    }

    /// Changing the comment (the Generator page's field) keeps the same key.
    @Test func ed25519SeedKeepsTheKeyAcrossComments() throws {
        let seed = SSHKeyPair.newEd25519Seed()
        #expect(seed.count == 32)
        let a = try SSHKeyPair.ed25519(seed: seed, comment: "laptop")
        let b = try SSHKeyPair.ed25519(seed: seed, comment: "")
        #expect(a.fingerprint == b.fingerprint)
        #expect(a.publicKey == b.publicKey + " laptop")
        #expect(SSHKeyPair.generateEd25519().fingerprint != a.fingerprint)
    }
}
