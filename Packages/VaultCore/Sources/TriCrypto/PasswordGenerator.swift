import Foundation
import Security

/// Random passwords from the system CSPRNG, with rejection sampling (no modulo bias) and at least
/// one character from every selected class.
public struct PasswordGenerator: Sendable, Equatable, Codable {
    public var length = 20
    public var uppercase = true
    public var lowercase = true
    public var digits = true
    public var symbols = true
    /// Drops look-alikes such as 0/O, 1/l/I.
    public var avoidAmbiguous = true
    /// At least this many digits / symbols (when those classes are on).
    public var minNumbers = 1
    public var minSpecial = 1

    public static let lengthRange = 5...128

    public init() {}

    enum CodingKeys: String, CodingKey { case length, uppercase, lowercase, digits, symbols, avoidAmbiguous, minNumbers, minSpecial }

    // Settings saved by older versions lack the newer keys; keep what's there.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 20
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase) ?? true
        lowercase = try c.decodeIfPresent(Bool.self, forKey: .lowercase) ?? true
        digits = try c.decodeIfPresent(Bool.self, forKey: .digits) ?? true
        symbols = try c.decodeIfPresent(Bool.self, forKey: .symbols) ?? true
        avoidAmbiguous = try c.decodeIfPresent(Bool.self, forKey: .avoidAmbiguous) ?? true
        minNumbers = try c.decodeIfPresent(Int.self, forKey: .minNumbers) ?? 1
        minSpecial = try c.decodeIfPresent(Int.self, forKey: .minSpecial) ?? 1
    }

    static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), lower = Array("abcdefghijklmnopqrstuvwxyz")
    static let numbers = Array("0123456789"), symbolSet = Array("!@#$%^&*-_=+?")
    static let ambiguous = Set("0O1lI")

    var classes: [[Character]] {
        [uppercase ? Self.upper : [], lowercase ? Self.lower : [], digits ? Self.numbers : [], symbols ? Self.symbolSet : []]
            .map { avoidAmbiguous ? $0.filter { !Self.ambiguous.contains($0) } : $0 }
            .filter { !$0.isEmpty }
    }

    public func generate() -> String {
        let classes = self.classes.isEmpty ? [Self.lower] : self.classes
        let all = classes.flatMap { $0 }
        let digitSet = classes.first { $0.contains("2") }
        let symbolSet = classes.first { $0.contains("!") }
        // Required picks: the minimum digits and symbols, and one from every other class.
        var chars: [Character] = []
        if let digitSet { chars += (0..<max(minNumbers, 1)).map { _ in digitSet[Self.uniform(upTo: digitSet.count)] } }
        if let symbolSet { chars += (0..<max(minSpecial, 1)).map { _ in symbolSet[Self.uniform(upTo: symbolSet.count)] } }
        for set in classes where set != digitSet && set != symbolSet { chars.append(set[Self.uniform(upTo: set.count)]) }
        let length = max(Self.lengthRange.clamp(self.length), chars.count)
        while chars.count < length { chars.append(all[Self.uniform(upTo: all.count)]) }
        for i in stride(from: chars.count - 1, to: 0, by: -1) { chars.swapAt(i, Self.uniform(upTo: i + 1)) }
        return String(chars)
    }

    /// Entropy in bits, for the strength meter.
    public var entropyBits: Double { Double(max(length, 1)) * log2(Double(max(classes.flatMap { $0 }.count, 2))) }

    /// Uniform integer in 0..<n via rejection sampling.
    static func uniform(upTo n: Int) -> Int {
        precondition(n > 0)
        let limit = UInt32.max - UInt32.max % UInt32(n)
        while true {
            var r: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &r) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
            if r < limit { return Int(r % UInt32(n)) }
        }
    }
}

extension ClosedRange where Bound == Int {
    func clamp(_ v: Int) -> Int { Swift.min(Swift.max(v, lowerBound), upperBound) }
}

/// Diceware-style passphrases from the EFF Large Wordlist (7,776 words, ~12.9 bits each).
public struct PassphraseGenerator: Sendable, Equatable, Codable {
    public var words = 6
    public var separator = "-"
    public var capitalize = false
    public var includeNumber = false

    public static let wordRange = 3...20

    public init() {}

    /// The EFF Large Wordlist, bundled with TriCrypto.
    public static let wordList: [String] = {
        guard let url = Bundle.module.url(forResource: "eff_large_wordlist", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { $0.split(separator: "\t").last.map(String.init) }
    }()

    public func generate() -> String {
        let list = Self.wordList
        guard !list.isEmpty else { return "" }
        let count = Self.wordRange.clamp(words)
        var picked = (0..<count).map { _ in list[PasswordGenerator.uniform(upTo: list.count)] }
        if capitalize { picked = picked.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        if includeNumber {
            let i = PasswordGenerator.uniform(upTo: picked.count)
            picked[i] += String(PasswordGenerator.uniform(upTo: 10))
        }
        return picked.joined(separator: separator)
    }

    public var entropyBits: Double {
        let count = Double(Self.wordRange.clamp(words))
        return count * log2(Double(max(Self.wordList.count, 2))) + (includeNumber ? log2(10) + log2(count) : 0)
    }
}

/// Usernames: a random word, a plus-addressed email, or a random address at a catch-all domain.
public struct UsernameGenerator: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable { case randomWord, plusAddressed, catchAll }

    public var kind = Kind.randomWord
    public var capitalize = false
    public var includeNumber = false
    /// Plus-addressed: the mailbox to add a tag to (e.g. you@example.com → you+k3x9q2@example.com).
    public var email = ""
    /// Catch-all: the domain that accepts any address.
    public var domain = ""

    public init() {}

    static let tagAlphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")

    static func tag(_ n: Int) -> String {
        String((0..<n).map { _ in tagAlphabet[PasswordGenerator.uniform(upTo: tagAlphabet.count)] })
    }

    /// Nil when the chosen kind is missing its email or domain.
    public func generate() -> String? {
        switch kind {
        case .randomWord:
            let list = PassphraseGenerator.wordList
            guard !list.isEmpty else { return nil }
            var word = list[PasswordGenerator.uniform(upTo: list.count)]
            if capitalize { word = word.prefix(1).uppercased() + word.dropFirst() }
            if includeNumber { word += String(format: "%04d", PasswordGenerator.uniform(upTo: 10_000)) }
            return word
        case .plusAddressed:
            let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@")
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return nil }
            let local = parts[0].split(separator: "+").first.map(String.init) ?? String(parts[0])
            return "\(local)+\(Self.tag(8))@\(parts[1])"
        case .catchAll:
            let d = domain.trimmingCharacters(in: CharacterSet(charactersIn: " @"))
            guard d.contains("."), !d.contains(" ") else { return nil }
            return "\(Self.tag(10))@\(d)"
        }
    }
}

/// Numeric PINs (device unlock, cards, door codes). Digits only, from the same CSPRNG as passwords.
public struct PINGenerator: Sendable, Equatable, Codable {
    public var length = 6
    /// Rejects PINs people guess first: a digit three times in a row (`777`) or a run of three (`123`, `987`).
    public var avoidPatterns = true

    public static let lengthRange = 4...16

    public init() {}

    enum CodingKeys: String, CodingKey { case length, avoidPatterns }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 6
        avoidPatterns = try c.decodeIfPresent(Bool.self, forKey: .avoidPatterns) ?? true
    }

    public func generate() -> String {
        let count = Self.lengthRange.clamp(length)
        while true {
            let digits = (0..<count).map { _ in PasswordGenerator.uniform(upTo: 10) }
            if !avoidPatterns || !Self.hasPattern(digits) { return digits.map(String.init).joined() }
        }
    }

    /// Three in a row of the same digit, or three ascending / descending by one.
    static func hasPattern(_ digits: [Int]) -> Bool {
        guard digits.count >= 3 else { return false }
        for i in 2..<digits.count {
            let a = digits[i - 2], b = digits[i - 1], c = digits[i]
            if a == b && b == c { return true }
            if b - a == c - b && abs(b - a) == 1 { return true }
        }
        return false
    }

    /// Every possible PIN of this length (an upper bound when patterns are avoided).
    public var combinations: Double { pow(10, Double(Self.lengthRange.clamp(length))) }
}
