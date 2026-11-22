import CryptoKit
import Foundation

/// New Ed25519 SSH keys in OpenSSH formats (unencrypted private key, `ssh-ed25519` public key, SHA256 fingerprint).
public struct SSHKeyPair: Sendable, Equatable {
    public let privateKey: String
    public let publicKey: String
    public let fingerprint: String

    public static func generateEd25519(comment: String = "") -> SSHKeyPair {
        ed25519(key: Curve25519.Signing.PrivateKey(), comment: comment)
    }

    /// The same key with a different comment (the comment is stored in both halves).
    public static func ed25519(seed: Data, comment: String = "") throws -> SSHKeyPair {
        try ed25519(key: Curve25519.Signing.PrivateKey(rawRepresentation: seed), comment: comment)
    }

    /// A fresh 32-byte Ed25519 seed, to hold while a comment is still being typed.
    public static func newEd25519Seed() -> Data { Curve25519.Signing.PrivateKey().rawRepresentation }

    static func ed25519(key: Curve25519.Signing.PrivateKey, comment: String) -> SSHKeyPair {
        let pub = key.publicKey.rawRepresentation
        let pubBlob = sshString("ssh-ed25519") + sshString(pub)

        // openssh-key-v1: magic, cipher "none", kdf "none", kdfoptions "", 1 key, public blob, private section.
        var check = UInt32.random(in: .min ... .max).bigEndian
        let checkBytes = Data(bytes: &check, count: 4)
        var priv = checkBytes + checkBytes
        priv += sshString("ssh-ed25519") + sshString(pub) + sshString(key.rawRepresentation + pub) + sshString(Data(comment.utf8))
        var pad: UInt8 = 1
        while priv.count % 8 != 0 { priv.append(pad); pad += 1 }

        var blob = Data("openssh-key-v1".utf8) + Data([0])
        blob += sshString("none") + sshString("none") + sshString(Data()) + uint32(1) + sshString(pubBlob) + sshString(priv)
        let body = blob.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(body)\n-----END OPENSSH PRIVATE KEY-----\n"

        let publicLine = "ssh-ed25519 " + pubBlob.base64EncodedString() + (comment.isEmpty ? "" : " \(comment)")
        let digest = Data(SHA256.hash(data: pubBlob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return SSHKeyPair(privateKey: pem, publicKey: publicLine, fingerprint: "SHA256:" + digest)
    }

    static func uint32(_ v: Int) -> Data {
        var be = UInt32(v).bigEndian
        return Data(bytes: &be, count: 4)
    }
    static func sshString(_ s: String) -> Data { sshString(Data(s.utf8)) }
    static func sshString(_ d: Data) -> Data { uint32(d.count) + d }
}
