import Foundation

/// The public half of a vault SSH key: enough to list it, never enough to sign.
public struct SSHPublicIdentity: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var publicBlob: Data
    /// The account that holds the private key, so a sign request knows which account must unlock.
    public var accountID: String
    public init(id: String, name: String, publicBlob: Data, accountID: String) {
        self.id = id
        self.name = name
        self.publicBlob = publicBlob
        self.accountID = accountID
    }
}

/// Public keys remembered across lock, so `ssh` and `git` still find a key while the vault is locked and can
/// ask to sign. A sign request then waits for unlock and approval. Public keys only: no private material.
public struct SSHPublicKeyCache: Codable, Equatable, Sendable {
    public private(set) var entries: [SSHPublicIdentity] = []
    public init(entries: [SSHPublicIdentity] = []) { self.entries = entries }

    /// The current keys of the accounts that are unlocked. Keys of locked accounts stay as they were;
    /// a key deleted or archived in an unlocked account goes.
    public mutating func replace(accounts: Set<String>, with live: [SSHPublicIdentity]) {
        entries.removeAll { accounts.contains($0.accountID) }
        entries.append(contentsOf: live.filter { accounts.contains($0.accountID) })
    }

    public mutating func remove(accountID: String) { entries.removeAll { $0.accountID == accountID } }
    public mutating func removeAll() { entries.removeAll() }

    /// Unlocked keys first, then remembered keys of accounts still locked, one entry per public key.
    public func listing(live: [SSHPublicIdentity], unlocked: Set<String>) -> [SSHPublicIdentity] {
        var seen = Set(live.map(\.publicBlob))
        var list = live
        for entry in entries where !unlocked.contains(entry.accountID) && seen.insert(entry.publicBlob).inserted {
            list.append(entry)
        }
        return list
    }

    public static func load(from url: URL) -> SSHPublicKeyCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(SSHPublicKeyCache.self, from: data) else { return SSHPublicKeyCache() }
        return cache
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// Signature requests that arrived while the vault was locked. They share one wait: unlocking answers all of them,
/// Cancel or the deadline refuses all of them. The app watches for unlock and the deadline, then calls `finish`.
public actor SSHUnlockWait {
    public enum Outcome: Equatable, Sendable { case unlocked, cancelled, timedOut }
    public static let timeout: Duration = .seconds(60)

    private var waiters: [CheckedContinuation<Outcome, Never>] = []

    public init() {}

    public var waiting: Int { waiters.count }

    public func wait() async -> Outcome {
        await withCheckedContinuation { waiters.append($0) }
    }

    public func finish(_ outcome: Outcome) {
        let all = waiters
        waiters = []
        // Resumed off this actor, like SSHApprovalQueue: a waiter may come straight back in.
        for waiter in all { Task.detached { waiter.resume(returning: outcome) } }
    }
}
