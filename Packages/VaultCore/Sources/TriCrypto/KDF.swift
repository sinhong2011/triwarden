import argon2
import CommonCrypto
import CryptoKit
import Foundation

/// Key-derivation settings returned by the server's prelogin endpoint.
public enum KDFConfig: Sendable, Equatable, Codable {
    case pbkdf2(iterations: Int)
    case argon2id(iterations: Int, memoryMiB: Int, parallelism: Int)

    // Bounds guard against a malicious or misconfigured server downgrading the KDF.
    static let pbkdf2Iterations = 600_000...2_000_000
    /// Password-protected export files: whatever Bitwarden's clients write, including accounts from before the
    /// 600,000 default (100,000 was the old one). There's no server to downgrade anything; the user chose the password.
    static let filePBKDF2Iterations = 5_000...2_000_000
    static let argon2Iterations = 2...10
    static let argon2MemoryMiB = 16...1024
    static let argon2Parallelism = 1...16

    public func validate(forFile: Bool = false) throws(CryptoError) {
        switch self {
        case .pbkdf2(let iterations):
            guard (forFile ? Self.filePBKDF2Iterations : Self.pbkdf2Iterations).contains(iterations) else {
                throw .kdfOutOfBounds("PBKDF2 iterations \(iterations)")
            }
        case .argon2id(let iterations, let memory, let parallelism):
            guard Self.argon2Iterations.contains(iterations),
                  Self.argon2MemoryMiB.contains(memory),
                  Self.argon2Parallelism.contains(parallelism)
            else {
                throw .kdfOutOfBounds("Argon2id t=\(iterations) m=\(memory)MiB p=\(parallelism)")
            }
        }
    }
}

public enum KDF {
    /// Derives the 32-byte master key from the master password and account email.
    public static func masterKey(password: String, email: String, config: KDFConfig) throws(CryptoError) -> Data {
        try config.validate()
        let salt = Data(normalizedEmail(email).utf8)
        switch config {
        case .pbkdf2(let iterations):
            return try pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations, length: 32)
        case .argon2id(let iterations, let memoryMiB, let parallelism):
            // Bitwarden salts Argon2 with SHA-256(email).
            let saltHash = Data(SHA256.hash(data: salt))
            return try argon2id(password: Data(password.utf8), salt: saltHash,
                                iterations: iterations, memoryKiB: memoryMiB * 1024, parallelism: parallelism)
        }
    }

    /// A key from a password and a salt used exactly as given (no email normalisation), stretched for
    /// encryption — Bitwarden's password-protected export key (`makePinKey(password, salt, kdf)`).
    public static func passwordKey(password: String, salt: String, config: KDFConfig) throws(CryptoError) -> SymmetricKeyPair {
        try config.validate(forFile: true)
        let raw: Data
        switch config {
        case .pbkdf2(let iterations):
            raw = try pbkdf2SHA256(password: Data(password.utf8), salt: Data(salt.utf8), iterations: iterations, length: 32)
        case .argon2id(let iterations, let memoryMiB, let parallelism):
            raw = try argon2id(password: Data(password.utf8), salt: Data(SHA256.hash(data: Data(salt.utf8))),
                               iterations: iterations, memoryKiB: memoryMiB * 1024, parallelism: parallelism)
        }
        return try SymmetricKeyPair.stretched(masterKey: raw)
    }

    /// The hash sent to the server as the login secret: PBKDF2(masterKey, password, 1).
    public static func masterPasswordHash(masterKey: Data, password: String) throws(CryptoError) -> String {
        try pbkdf2SHA256(password: masterKey, salt: Data(password.utf8), iterations: 1, length: 32)
            .base64EncodedString()
    }

    public static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Raw Argon2id with a 32-byte output and no bounds check: callers choose and check their own parameters.
    public static func argon2id(password: Data, salt: Data, iterations: Int, memoryKiB: Int, parallelism: Int) throws(CryptoError) -> Data {
        var out = Data(count: 32)
        let rc = out.withUnsafeMutableBytes { o in
            password.withUnsafeBytes { p in
                salt.withUnsafeBytes { s in
                    argon2id_hash_raw(UInt32(iterations), UInt32(memoryKiB), UInt32(parallelism),
                                      p.baseAddress, password.count, s.baseAddress, salt.count,
                                      o.baseAddress, 32)
                }
            }
        }
        guard rc == ARGON2_OK.rawValue else { throw .commonCrypto(rc) }
        return out
    }

    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, length: Int) throws(CryptoError) -> Data {
        var derived = Data(count: length)
        let status = derived.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw .commonCrypto(status) }
        return derived
    }
}
