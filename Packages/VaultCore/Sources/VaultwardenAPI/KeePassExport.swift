import CryptoKit
import Foundation
import TriCrypto

// A KeePass database (KDBX 4), so the vault opens directly in KeePassXC, KeePassium, Strongbox and KeePass.
// The file is encrypted end to end: Argon2id stretches the file password, ChaCha20 encrypts the payload, every
// block carries an HMAC, and passwords and other secrets are encrypted once more inside it, as KeePass expects.
//
// Folders (and collections) become groups, nested on "/" as Bitwarden shows them. Logins keep their URLs, one-time
// codes (as KeePassXC's `otp`), passkeys (KeePassXC's `KPEX_PASSKEY_*`) and password history (as entry history).
// Cards, identities and SSH keys keep every value as named fields.

public enum KeePassExport {
    /// Argon2id settings written into the file; KeePass apps read them back from it.
    public struct KDF: Sendable, Equatable {
        public var iterations: Int
        public var memoryMiB: Int
        public var parallelism: Int
        public init(iterations: Int, memoryMiB: Int, parallelism: Int) {
            self.iterations = iterations; self.memoryMiB = memoryMiB; self.parallelism = parallelism
        }
        /// KeePassXC's default memory; about a quarter second on a recent Mac, still quick to open on a phone.
        public static let standard = KDF(iterations: 10, memoryMiB: 64, parallelism: 2)
    }

    /// The personal vault: folders become groups under one named for the vault.
    public static func kdbx(folders: [[String: Any]], items: [[String: Any]], databaseName: String,
                            password: String, kdf: KDF = .standard) throws -> Data {
        let groups = Dictionary(folders.compactMap { f in (f["id"] as? String).map { ($0, f["name"] as? String ?? "") } },
                                uniquingKeysWith: { a, _ in a })
        return try kdbx(groups: groups, items: items, groupOf: { $0["folderId"] as? String },
                        databaseName: databaseName, password: password, kdf: kdf)
    }

    /// An organization's vault: collections become groups. An item in several collections goes in the first one.
    public static func kdbx(collections: [[String: Any]], items: [[String: Any]], databaseName: String,
                            password: String, kdf: KDF = .standard) throws -> Data {
        let groups = Dictionary(collections.compactMap { c in (c["id"] as? String).map { ($0, c["name"] as? String ?? "") } },
                                uniquingKeysWith: { a, _ in a })
        // Collection order as given, so the choice of "first" is stable.
        let order = Dictionary(collections.enumerated().compactMap { i, c in (c["id"] as? String).map { ($0, i) } },
                               uniquingKeysWith: { a, _ in a })
        return try kdbx(groups: groups, items: items, groupOf: { item in
            (item["collectionIds"] as? [String] ?? []).filter { groups[$0] != nil }.min { order[$0, default: 0] < order[$1, default: 0] }
        }, databaseName: databaseName, password: password, kdf: kdf)
    }

    static func kdbx(groups: [String: String], items: [[String: Any]], groupOf: ([String: Any]) -> String?,
                     databaseName: String, password: String, kdf: KDF) throws -> Data {
        let tree = GroupNode.tree(name: databaseName, groups: groups, items: items, groupOf: groupOf)
        let innerKey = random(64)
        var xml = XMLWriter(protector: InnerStream(key: innerKey))
        xml.document(root: tree, databaseName: databaseName)
        return try encrypt(xml: Data(xml.out.utf8), innerKey: innerKey, password: password, kdf: kdf)
    }

    // MARK: Container

    static let signature: [UInt8] = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5]
    static let chaCha20Cipher = Data([0xD6, 0x03, 0x8A, 0x2B, 0x8B, 0x6F, 0x4C, 0xB5, 0xA5, 0x24, 0x33, 0x9A, 0x31, 0xDB, 0xB5, 0x9A])
    static let argon2idKDF = Data([0x9E, 0x29, 0x8B, 0x19, 0x56, 0xDB, 0x47, 0x73, 0xB2, 0x3D, 0xFC, 0x3E, 0xC6, 0xF0, 0xA1, 0xE6])
    static let blockSize = 1 << 20

    static func encrypt(xml: Data, innerKey: Data, password: String, kdf: KDF) throws -> Data {
        let masterSeed = random(32), iv = random(12), salt = random(32)

        var params = Bytes()
        params.u16(0x0100)
        params.entry(0x42, "$UUID", argon2idKDF)
        params.entry(0x42, "S", salt)
        params.entry(0x04, "P", Bytes.le(UInt32(kdf.parallelism)))
        params.entry(0x05, "M", Bytes.le(UInt64(kdf.memoryMiB) * 1024 * 1024))
        params.entry(0x05, "I", Bytes.le(UInt64(kdf.iterations)))
        params.entry(0x04, "V", Bytes.le(UInt32(0x13)))
        params.data.append(0)

        var header = Bytes()
        header.data.append(contentsOf: signature)
        header.u16(0) // minor
        header.u16(4) // major: KDBX 4.0
        header.field(2, chaCha20Cipher)
        header.field(3, Bytes.le(UInt32(0))) // no compression
        header.field(4, masterSeed)
        header.field(7, iv)
        header.field(11, params.data)
        header.field(0, Data("\r\n\r\n".utf8))

        let composite = Data(SHA256.hash(data: Data(SHA256.hash(data: Data(password.utf8)))))
        let transformed = try TriCrypto.KDF.argon2id(password: composite, salt: salt, iterations: kdf.iterations,
                                                     memoryKiB: kdf.memoryMiB * 1024, parallelism: kdf.parallelism)
        let encryptionKey = Data(SHA256.hash(data: masterSeed + transformed))
        let hmacBase = Data(SHA512.hash(data: masterSeed + transformed + Data([1])))

        var inner = Bytes()
        inner.field(1, Bytes.le(UInt32(3))) // protected values: ChaCha20
        inner.field(2, innerKey)
        inner.field(0, Data())
        var cipher = ChaCha20(key: encryptionKey, nonce: iv)
        let payload = cipher.apply(inner.data + xml)

        var file = header.data
        file.append(Data(SHA256.hash(data: header.data)))
        file.append(hmac(header.data, index: .max, base: hmacBase))
        var index: UInt64 = 0
        var offset = 0
        repeat {
            let chunk = payload.subdata(in: offset..<min(offset + blockSize, payload.count))
            let size = Bytes.le(UInt32(chunk.count))
            file.append(hmac(Bytes.le(index) + size + chunk, index: index, base: hmacBase))
            file.append(size + chunk)
            offset += chunk.count
            index += 1
            if chunk.isEmpty { break }
        } while true
        return file
    }

    /// HMAC-SHA256 with the block's own key: SHA-512(index ‖ base).
    static func hmac(_ data: Data, index: UInt64, base: Data) -> Data {
        let key = SymmetricKey(data: Data(SHA512.hash(data: Bytes.le(index) + base)))
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    static func random(_ count: Int) -> Data {
        var d = Data(count: count)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return d
    }

    struct Bytes {
        var data = Data()
        static func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        mutating func u16(_ v: UInt16) { data.append(Self.le(v)) }
        /// An outer or inner header field: id, 4-byte length, value.
        mutating func field(_ id: UInt8, _ value: Data) {
            data.append(id); data.append(Self.le(UInt32(value.count))); data.append(value)
        }
        /// A VariantDictionary entry: type, key, value.
        mutating func entry(_ type: UInt8, _ key: String, _ value: Data) {
            data.append(type)
            data.append(Self.le(UInt32(key.utf8.count))); data.append(Data(key.utf8))
            data.append(Self.le(UInt32(value.count))); data.append(value)
        }
    }

    /// Encrypts protected values in document order with ChaCha20 keyed from SHA-512 of the inner key.
    struct InnerStream {
        var cipher: ChaCha20
        init(key: Data) {
            let h = Data(SHA512.hash(data: key))
            cipher = ChaCha20(key: h.prefix(32), nonce: h.subdata(in: 32..<44))
        }
        mutating func protect(_ s: String) -> String { cipher.apply(Data(s.utf8)).base64EncodedString() }
    }

    // MARK: Groups

    final class GroupNode {
        var uuid: Data
        let name: String
        var children: [GroupNode] = []
        var items: [[String: Any]] = []
        init(uuid: Data, name: String) { self.uuid = uuid; self.name = name }

        /// Folder "Work/Servers" becomes group Servers inside group Work; the deepest group takes the folder's id.
        static func tree(name: String, groups: [String: String], items: [[String: Any]],
                         groupOf: ([String: Any]) -> String?) -> GroupNode {
            let root = GroupNode(uuid: random(16), name: name)
            var byPath: [String: GroupNode] = [:]
            func node(for path: [String]) -> GroupNode {
                var parent = root
                for depth in path.indices {
                    let key = path[...depth].joined(separator: "/")
                    if let existing = byPath[key] { parent = existing; continue }
                    let child = GroupNode(uuid: random(16), name: path[depth])
                    parent.children.append(child)
                    byPath[key] = child
                    parent = child
                }
                return parent
            }
            var byID: [String: GroupNode] = [:]
            for (id, name) in groups.sorted(by: { $0.value.localizedStandardCompare($1.value) == .orderedAscending }) {
                let path = name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !path.isEmpty else { continue }
                let n = node(for: path)
                if let uuid = uuidBytes(id), !byID.values.contains(where: { $0 === n }) { n.uuid = uuid }
                byID[id] = n
            }
            for item in items {
                (groupOf(item).flatMap { byID[$0] } ?? root).items.append(item)
            }
            return root
        }
    }

    static func uuidBytes(_ id: String?) -> Data? {
        guard let id, let u = UUID(uuidString: id) else { return nil }
        return withUnsafeBytes(of: u.uuid) { Data($0) }
    }

    // MARK: XML

    struct XMLWriter {
        var protector: InnerStream
        var out = ""

        mutating func document(root: GroupNode, databaseName: String) {
            out += #"<?xml version="1.0" encoding="utf-8" standalone="yes"?>"# + "\n<KeePassFile><Meta>"
            element("Generator", "Triwarden")
            element("DatabaseName", databaseName)
            out += "<MemoryProtection>"
            for (k, v) in [("ProtectTitle", false), ("ProtectUserName", false), ("ProtectPassword", true),
                           ("ProtectURL", false), ("ProtectNotes", false)] { element(k, v ? "True" : "False") }
            out += "</MemoryProtection></Meta><Root>"
            group(root)
            out += "</Root></KeePassFile>\n"
        }

        mutating func group(_ g: GroupNode) {
            out += "<Group>"
            element("UUID", g.uuid.base64EncodedString())
            element("Name", g.name)
            times(created: nil, modified: nil)
            element("IsExpanded", "True")
            for item in g.items { entry(item) }
            for child in g.children { group(child) }
            out += "</Group>"
        }

        mutating func entry(_ item: [String: Any]) {
            let uuid = uuidBytes(item["id"] as? String) ?? random(16)
            let fields = EntryFields(item)
            let created = date(item["creationDate"]), modified = date(item["revisionDate"])
            out += "<Entry>"
            element("UUID", uuid.base64EncodedString())
            element("IconID", String(fields.icon))
            if (item["favorite"] as? Bool) == true { element("Tags", "Favorite") }
            times(created: created, modified: modified)
            strings(fields.strings)
            // Older passwords, oldest first, as earlier versions of this entry.
            let history = (item["login"] as? [String: Any])?["passwordHistory"] as? [[String: Any]]
                ?? item["passwordHistory"] as? [[String: Any]] ?? []
            let old = history.compactMap { h -> (password: String, date: Date?)? in
                (h["password"] as? String).map { ($0, date(h["lastUsedDate"])) }
            }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            if !old.isEmpty {
                out += "<History>"
                for h in old {
                    out += "<Entry>"
                    element("UUID", uuid.base64EncodedString())
                    times(created: created, modified: h.date)
                    strings(fields.strings.filter { EntryFields.standard.contains($0.key) }.map { s in
                        s.key == "Password" ? (s.key, h.password, true) : s
                    })
                    out += "</Entry>"
                }
                out += "</History>"
            }
            out += "</Entry>"
        }

        mutating func strings(_ list: [(key: String, value: String, protected: Bool)]) {
            for s in list {
                out += "<String>"
                element("Key", s.key)
                if s.protected {
                    out += #"<Value Protected="True">"# + protector.protect(Self.clean(s.value)) + "</Value>"
                } else {
                    element("Value", s.value)
                }
                out += "</String>"
            }
        }

        mutating func times(created: Date?, modified: Date?) {
            let now = Date()
            let c = Self.time(created ?? modified ?? now), m = Self.time(modified ?? created ?? now)
            out += "<Times>"
            element("CreationTime", c)
            element("LastModificationTime", m)
            element("LastAccessTime", m)
            element("ExpiryTime", m)
            element("Expires", "False")
            element("UsageCount", "0")
            element("LocationChanged", m)
            out += "</Times>"
        }

        mutating func element(_ name: String, _ value: String) {
            out += "<\(name)>\(Self.escape(value))</\(name)>"
        }

        /// KDBX 4 times: seconds since 0001-01-01 UTC, 8 bytes little-endian, base64.
        static func time(_ d: Date) -> String {
            Bytes.le(Int64(d.timeIntervalSince1970.rounded(.down)) + 62_135_596_800).base64EncodedString()
        }

        /// Characters XML 1.0 can't hold (most control characters) are dropped rather than breaking the file.
        static func clean(_ s: String) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.filter { u in
                u.value == 0x9 || u.value == 0xA || u.value == 0xD || (0x20...0xD7FF).contains(u.value)
                    || (0xE000...0xFFFD).contains(u.value) || u.value >= 0x10000
            }))
        }

        static func escape(_ s: String) -> String {
            var r = ""
            for ch in clean(s) {
                switch ch {
                case "&": r += "&amp;"
                case "<": r += "&lt;"
                case ">": r += "&gt;"
                case "\"": r += "&quot;"
                default: r.append(ch)
                }
            }
            return r
        }
    }

    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Item → entry strings

    struct EntryFields {
        static let standard: Set<String> = ["Title", "UserName", "Password", "URL", "Notes"]

        var strings: [(key: String, value: String, protected: Bool)] = []
        var icon = 0

        init(_ item: [String: Any]) {
            let login = item["login"] as? [String: Any] ?? [:]
            let card = item["card"] as? [String: Any] ?? [:]
            let identity = item["identity"] as? [String: Any] ?? [:]
            let ssh = item["sshKey"] as? [String: Any] ?? [:]
            let title = Self.string(item["name"])
            let uris = (login["uris"] as? [[String: Any]] ?? []).compactMap { Self.string($0["uri"]).nilIfEmpty }

            strings = [("Title", title, false),
                       ("UserName", Self.string(item["type"] as? Int == 4 ? identity["username"] : login["username"]), false),
                       ("Password", Self.string(login["password"]), true),
                       ("URL", uris.first ?? "", false),
                       ("Notes", Self.string(item["notes"]), false)]
            var linked: [Int: String] = [100: "{USERNAME}", 101: "{PASSWORD}"]

            // KeePassXC's names for a login's extra URLs.
            for (i, uri) in uris.dropFirst().enumerated() { add(i == 0 ? "KP2A_URL" : "KP2A_URL_\(i)", uri) }
            if let totp = Self.string(login["totp"]).nilIfEmpty { add("otp", Self.otpauth(totp, title: title, username: Self.string(login["username"])), protected: true) }
            if let passkey = (login["fido2Credentials"] as? [[String: Any]])?.first { addPasskey(passkey) }

            switch item["type"] as? Int {
            case 2: icon = 7
            case 3:
                icon = 66
                for (id, key, field, protected) in Self.cardFields {
                    if add(key, Self.string(card[field]), protected: protected) { linked[id] = "{S:\(key)}" }
                }
            case 4:
                icon = 9
                for (id, key, field, protected) in Self.identityFields {
                    if add(key, Self.string(identity[field]), protected: protected) { linked[id] = "{S:\(key)}" }
                }
                linked[413] = "{USERNAME}"
                let full = ["title", "firstName", "middleName", "lastName"].compactMap { Self.string(identity[$0]).nilIfEmpty }
                if !full.isEmpty { linked[418] = full.joined(separator: " ") }
            case 5:
                icon = 29
                add("Private key", Self.string(ssh["privateKey"]), protected: true)
                add("Public key", Self.string(ssh["publicKey"]))
                add("Fingerprint", Self.string(ssh["keyFingerprint"]))
            default: break
            }

            for field in item["fields"] as? [[String: Any]] ?? [] {
                let name = Self.string(field["name"]).nilIfEmpty ?? "Field"
                let type = field["type"] as? Int ?? 0
                let value = type == 3
                    ? (field["linkedId"] as? Int).flatMap { linked[$0] } ?? ""
                    : Self.string(field["value"])
                add(name, value, protected: type == 1, keepEmpty: true)
            }
        }

        /// Adds a field under a key not used yet ("PIN", "PIN (2)", …); empty values are left out unless asked.
        @discardableResult
        mutating func add(_ key: String, _ value: String, protected: Bool = false, keepEmpty: Bool = false) -> Bool {
            guard keepEmpty || !value.isEmpty else { return false }
            var unique = key, n = 2
            while strings.contains(where: { $0.key == unique }) { unique = "\(key) (\(n))"; n += 1 }
            strings.append((unique, value, protected))
            return true
        }

        /// KeePassXC's passkey fields, from Bitwarden's FIDO2 credential.
        mutating func addPasskey(_ p: [String: Any]) {
            let credentialId = Self.string(p["credentialId"])
            let id: String = if credentialId.hasPrefix("b64.") { String(credentialId.dropFirst(4)) }
                else if let bytes = uuidBytes(credentialId) { Self.base64url(bytes) }
                else { credentialId }
            guard let der = Self.fromBase64url(Self.string(p["keyValue"])), !id.isEmpty else { return }
            let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            add("KPEX_PASSKEY_USERNAME", Self.string(p["userName"]))
            add("KPEX_PASSKEY_CREDENTIAL_ID", id)
            add("KPEX_PASSKEY_PRIVATE_KEY_PEM", "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----", protected: true)
            add("KPEX_PASSKEY_RELYING_PARTY", Self.string(p["rpId"]))
            add("KPEX_PASSKEY_USER_HANDLE", Self.string(p["userHandle"]))
        }

        // (Bitwarden linked-field id, KeePass key, Bitwarden field, protected)
        static let cardFields: [(Int, String, String, Bool)] = [
            (300, "Cardholder name", "cardholderName", false), (304, "Brand", "brand", false),
            (305, "Number", "number", true), (301, "Expiry month", "expMonth", false),
            (302, "Expiry year", "expYear", false), (303, "Security code", "code", true),
        ]
        static let identityFields: [(Int, String, String, Bool)] = [
            (400, "Name title", "title", false), (416, "First name", "firstName", false),
            (401, "Middle name", "middleName", false), (417, "Last name", "lastName", false),
            (409, "Company", "company", false), (410, "Email", "email", false), (411, "Phone", "phone", false),
            (402, "Address 1", "address1", false), (403, "Address 2", "address2", false), (404, "Address 3", "address3", false),
            (405, "City", "city", false), (406, "State", "state", false), (407, "Postal code", "postalCode", false),
            (408, "Country", "country", false), (412, "Social Security number", "ssn", true),
            (414, "Passport number", "passportNumber", true), (415, "License number", "licenseNumber", true),
        ]

        /// KeePassXC reads one-time codes as an otpauth:// URI; Bitwarden also stores bare secrets and steam:// ones.
        static func otpauth(_ totp: String, title: String, username: String) -> String {
            if totp.lowercased().hasPrefix("otpauth://") { return totp }
            let label = (title.isEmpty ? "Triwarden" : title) + (username.isEmpty ? "" : ":\(username)")
            let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? "Triwarden"
            if totp.lowercased().hasPrefix("steam://") {
                return "otpauth://totp/\(encodedLabel)?secret=\(totp.dropFirst(8))&issuer=Steam&encoder=steam"
            }
            let secret = totp.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "=", with: "").uppercased()
            return "otpauth://totp/\(encodedLabel)?secret=\(secret)&period=30&digits=6&algorithm=SHA1"
        }

        static func string(_ any: Any?) -> String {
            switch any {
            case let s as String: s
            case let n as NSNumber: n.stringValue
            default: ""
            }
        }

        static func base64url(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        static func fromBase64url(_ s: String) -> Data? {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            b += String(repeating: "=", count: (4 - b.count % 4) % 4)
            return Data(base64Encoded: b)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
