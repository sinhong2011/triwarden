import Foundation
import LocalAuthentication
import Observation
import SSHAgent

/// Serves the vault's SSH keys to `ssh`, `git` and friends. A signature names the app that asked,
/// then proves the device owner with Touch ID or the Mac login password. A grant can last 15 seconds,
/// 10 minutes, or until the vault locks. An app on the allowlist signs whenever the vault is unlocked.
///
/// While the vault is locked the agent still lists remembered public keys. A signature then asks the person to
/// unlock (the vault window comes forward and says who is waiting), and continues to the usual approval.
@MainActor @Observable
final class SSHAgentService {
    /// App Group folder for logs, the allowlist and remembered public keys (regular files, not sockets).
    static var appGroupDirectory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)
            ?? FileManager.default.temporaryDirectory
    }

    /// Short `/tmp` socket planned for this Mac; falls back to the classic App Group path.
    static var defaultSocket: URL {
        URL(fileURLWithPath: (try? UnixSocketLocation.plannedPath(kind: .agent))
            ?? UnixSocketLocation.connectPath(kind: .agent))
    }

    static var logURL: URL { appGroupDirectory.appending(path: "ssh-access-log.json") }
    static var allowlistURL: URL { appGroupDirectory.appending(path: "ssh-allowlist.json") }
    /// Public keys remembered for listing while locked. Isolated test sockets keep the file next to
    /// the socket; the managed `/tmp` socket stores it in the App Group.
    static func publicKeysURL(for socket: URL) -> URL {
        if UnixSocketLocation.isManaged(socket) {
            return appGroupDirectory.appending(path: "agent-public-keys.json")
        }
        return socket.deletingLastPathComponent().appending(path: "\(socket.deletingPathExtension().lastPathComponent)-public-keys.json")
    }

    /// How long after unlocking for a waiting signature the unlock also counts as the owner check.
    static let unlockConfirms: TimeInterval = 90

    private(set) var isRunning = false
    private(set) var lastError: String?
    /// Last few uses, newest first, for the menu bar.
    private(set) var recent: [(date: Date, key: String, program: String, allowed: Bool)] = []
    /// The prompt on screen, when a signature is waiting.
    private(set) var pending: SSHPrompt?
    private(set) var pendingCount = 0
    private(set) var accessLog: SSHAccessLog
    /// Apps that may sign whenever the vault is unlocked. Kept across lock and quit.
    private(set) var allowlist: SSHAllowlist
    private(set) var trustedUntilLock: [SSHTrust] = []
    /// A signature waiting for the vault to unlock. The unlock screen names it.
    private(set) var unlockRequest: SSHUnlockRequest?

    private var server: SSHAgentServer?
    private var managesLocation = false
    private var parsed: [String: (pem: String, key: SSHPrivateKey)] = [:]
    private var publicKeys = SSHPublicKeyCache()
    private var publicKeysFile: URL?
    private let unlockWait = SSHUnlockWait()
    private var trust = SSHTrustStore()
    var activeTrusts: [SSHTrust] { trust.entries.filter { $0.until.map { $0 > .now } ?? true } }
    private let prompts = SSHApprovalQueue()
    private var inflight: [String: Task<(Bool, SSHChoice), Never>] = [:]
    private var inflightPrompt: [String: UUID] = [:]
    private var sessionStarted = Date()
    private var watching = false
    private var authenticating = false
    private var authentication: LAContext?
    private var authorizationGeneration = UUID()
    private var pendingDeadline: ContinuousClock.Instant?
    private let approvalPanel = SSHApprovalPanel()
    /// "Details…" in the notch asked for the full card for this prompt.
    private var windowForPrompt: UUID?

    private func hidePrompt() {
        approvalPanel.hide()
        model?.notch?.clearRequest(.ssh)
    }
    private weak var model: AppModel?
    private let accessLogFile: URL
    private let allowlistFile: URL
    /// Self-test hook: skip the card and Touch ID. Arguments stay (key name, peer process name).
    var approveOverride: ((String, String) -> Bool)?
    /// Self-test hook: replaces bringing the vault window forward for a locked signature (argument: account ID).
    var unlockPresenter: ((String) -> Void)?

    private func offerUnlock(_ accountID: String) {
        if let unlockPresenter { unlockPresenter(accountID) } else { model?.offerUnlockForSSH(accountID: accountID) }
    }

    init(model: AppModel? = nil, logURL: URL = SSHAgentService.logURL, allowlistURL: URL = SSHAgentService.allowlistURL) {
        self.model = model
        accessLogFile = logURL; allowlistFile = allowlistURL
        accessLog = SSHAccessLog.load(from: logURL)
        allowlist = SSHAllowlist.load(from: allowlistURL)
    }

    func start(at socket: URL? = nil) {
        guard server == nil else { return }
        let managed = socket == nil
        let url: URL
        if let socket {
            url = socket
        } else {
            do {
                url = URL(fileURLWithPath: try UnixSocketLocation.prepareBindPath(kind: .agent))
            } catch {
                lastError = Self.startError(error)
                return
            }
        }
        let keysFile = Self.publicKeysURL(for: url)
        publicKeysFile = keysFile
        publicKeys = SSHPublicKeyCache.load(from: keysFile)
        let server = SSHAgentServer(
            socketURL: url,
            list: { [weak self] in await self?.list() ?? [] },
            authorize: { [weak self] listed, peer in await self?.authorize(listed, peer) })
        do {
            try server.start()
            if managed {
                try UnixSocketLocation.publish(kind: .agent, socketPath: url.path)
            }
            self.server = server
            self.managesLocation = managed
            isRunning = true
            lastError = nil
            SSHApprovalNotifier.requestPermission()
        } catch {
            server.stop()
            lastError = Self.startError(error)
        }
    }

    private static func startError(_ error: Error) -> String {
        if case FramedSocketServer.Failure.pathTooLong = error {
            return String(localized: "Couldn't start the SSH agent: \(UnixSocketLocation.pathTooLongMessage)")
        }
        if case UnixSocketLocation.Failure.pathTooLong = error {
            return String(localized: "Couldn't start the SSH agent: \(UnixSocketLocation.pathTooLongMessage)")
        }
        return String(localized: "Couldn't start the SSH agent: \(error.localizedDescription)")
    }

    /// Turning the agent off also forgets the remembered public keys.
    func stop() {
        reset()
        cancelUnlockRequest()
        server?.stop()
        server = nil
        if managesLocation {
            UnixSocketLocation.unpublish(kind: .agent)
            managesLocation = false
        }
        isRunning = false
        forgetPublicKeys()
    }

    /// Signing out of an account (nil: every account) forgets its public keys.
    func forgetPublicKeys(accountID: String? = nil) {
        if let accountID { publicKeys.remove(accountID: accountID) } else { publicKeys.removeAll() }
        guard let publicKeysFile else { return }
        if publicKeys.entries.isEmpty {
            try? FileManager.default.removeItem(at: publicKeysFile)
        } else {
            savePublicKeys()
        }
    }

    var socketPath: String { server?.socketURL.path ?? Self.defaultSocket.path }

    /// The first ask in this unlock leads with Allow Once. A later ask leads with Trust Until Lock.
    var pendingLeadsWithUntilLock: Bool {
        guard let pending else { return false }
        return SSHApprovalEmphasis.leadsWithUntilLock(priorAsks: accessLog.priorAsks(trustKey: pending.trustKey, since: sessionStarted))
    }

    func choose(_ choice: SSHChoice, promptID: UUID) {
        guard pending?.id == promptID else { return }
        if case .allow = choice, authenticating { return }
        hidePrompt()
        Task { await prompts.resolve(choice, for: promptID) }
    }

    /// The menu bar or a notification tap brings the waiting card back, or the unlock screen when the vault is locked.
    func reveal() {
        if let unlockRequest, !isUnlocked(unlockRequest.accountID) {
            offerUnlock(unlockRequest.accountID)
            return
        }
        presentPending(reveal: true)
    }

    /// "Cancel" on the unlock screen: every signature waiting for unlock is refused.
    func cancelUnlockRequest() {
        guard unlockRequest != nil else { return }
        unlockRequest = nil
        Task { await unlockWait.finish(.cancelled) }
    }

    func revokeTrust(id: String) {
        trust.revoke(id: id)
        trustedUntilLock = trust.untilLock
    }

    func clearAccessLog() {
        do {
            if FileManager.default.fileExists(atPath: accessLogFile.path) { try FileManager.default.removeItem(at: accessLogFile) }
        } catch { model?.flash(String(localized: "Couldn't clear the SSH history. The records are still listed.")); return }
        accessLog.clear()
        recent = []
    }

    /// Forget approvals and parsed keys (on lock). The access log and remembered public keys stay.
    func reset() {
        _ = list() // remember the keys as they are at lock, so a key deleted just before is not offered
        authorizationGeneration = UUID()
        authentication?.invalidate()
        hidePrompt()
        pending = nil
        pendingCount = 0
        pendingDeadline = nil
        parsed = [:]
        trust.reset()
        trustedUntilLock = []
        sessionStarted = .now
        Task { await prompts.denyAll(); await refreshPending() }
    }

    // MARK: Agent callbacks

    /// SSH key items from every unlocked account, with the account that holds each. Empty while locked.
    private func identities() -> [(identity: SSHAgentServer.Identity, accountID: String)] {
        guard let model else { return [] }
        return model.items.filter { $0.kind == .sshKey && !$0.isDeleted && !$0.isArchived }.compactMap { item in
            guard let pem = item.properties["privateKey"], !pem.isEmpty else { return nil }
            if let cached = parsed[item.id], cached.pem == pem {
                return (SSHAgentServer.Identity(id: item.id, name: item.name, key: cached.key), item.accountId)
            }
            guard let key = try? SSHPrivateKey(pem: pem) else { return nil }
            parsed[item.id] = (pem, key)
            return (SSHAgentServer.Identity(id: item.id, name: item.name, key: key), item.accountId)
        }
    }

    /// Preview and demo vaults are unlocked without account sessions.
    private var unlockedAccounts: Set<String> {
        guard let model, model.isUnlocked else { return [] }
        return model.previewUnlocked ? Set(model.accounts.map(\.id)) : Set(model.sessions.map(\.id))
    }

    private func isUnlocked(_ accountID: String) -> Bool { unlockedAccounts.contains(accountID) }

    /// Unlocked keys, then remembered public keys of locked accounts. Keeps the remembered list current.
    private func list() -> [SSHPublicIdentity] {
        let unlocked = unlockedAccounts
        let live = identities().map {
            SSHPublicIdentity(id: $0.identity.id, name: $0.identity.name, publicBlob: $0.identity.key.publicBlob, accountID: $0.accountID)
        }
        // Accounts with no items yet are still loading after unlock: keep what was remembered for them.
        let loaded = unlocked.filter { id in model?.items.contains { $0.accountId == id } == true }
        var next = publicKeys
        next.replace(accounts: loaded, with: live)
        if let model { next.entries.map(\.accountID).filter { id in !model.accounts.contains { $0.id == id } }.forEach { next.remove(accountID: $0) } }
        if next != publicKeys {
            publicKeys = next
            savePublicKeys()
        }
        return publicKeys.listing(live: live, unlocked: unlocked)
    }

    private func savePublicKeys() {
        guard let publicKeysFile else { return }
        try? publicKeys.save(to: publicKeysFile)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: publicKeysFile.path)
    }

    private func live(_ listed: SSHPublicIdentity) -> SSHAgentServer.Identity? {
        identities().first { $0.identity.id == listed.id && $0.identity.key.publicBlob == listed.publicBlob }?.identity
            ?? identities().first { $0.identity.key.publicBlob == listed.publicBlob }?.identity
    }

    /// A signature for a listed key. While its account is locked, asks to unlock first; then the usual approval.
    private func authorize(_ listed: SSHPublicIdentity, _ peer: SSHAgentServer.Peer) async -> SSHPrivateKey? {
        if let identity = live(listed) {
            return await approve(identity, peer, unlockedAt: nil) ? identity.key : nil
        }
        let requester = SSHProcess.requester(for: peer)
        guard approveOverride == nil, let model, model.accounts.contains(where: { $0.id == listed.accountID }) else {
            record(requester, key: listed.name, outcome: .locked)
            return nil
        }
        switch await waitForUnlock(requester, key: listed) {
        case .unlocked: break
        case .cancelled:
            record(requester, key: listed.name, outcome: .denied)
            return nil
        case .timedOut:
            record(requester, key: listed.name, outcome: .locked)
            return nil
        }
        let unlockedAt = Date.now
        // The account's items arrive just after unlock.
        for _ in 0..<50 where live(listed) == nil && isUnlocked(listed.accountID) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let identity = live(listed) else {
            if isUnlocked(listed.accountID) {
                model.flash(String(localized: "“\(listed.name)” is no longer in the vault, so “\(requester.displayName)” couldn't sign."))
            }
            record(requester, key: listed.name, outcome: .locked)
            return nil
        }
        return await approve(identity, peer, unlockedAt: unlockedAt) ? identity.key : nil
    }

    /// Shows who is waiting on the unlock screen and waits for that account to unlock, Cancel, or the deadline.
    private func waitForUnlock(_ requester: SSHRequester, key: SSHPublicIdentity) async -> SSHUnlockWait.Outcome {
        if var request = unlockRequest {
            request.waiting += 1
            unlockRequest = request
        } else {
            let request = SSHUnlockRequest(id: UUID(), displayName: requester.displayName, via: requester.via, keyName: key.name,
                                           accountID: key.accountID,
                                           deadline: Date.now.addingTimeInterval(NotchStatusController.seconds(SSHUnlockWait.timeout)))
            unlockRequest = request
            SSHApprovalNotifier.armUnlock(request)
            offerUnlock(key.accountID)
            watchUnlock(request)
        }
        return await unlockWait.wait()
    }

    /// Polls rather than hooking every unlock path (password, PIN, Touch ID, an account's own door).
    private func watchUnlock(_ request: SSHUnlockRequest) {
        Task { @MainActor in
            while self.unlockRequest?.id == request.id {
                try? await Task.sleep(for: .milliseconds(200))
                guard self.unlockRequest?.id == request.id else { break }
                if self.isUnlocked(request.accountID) {
                    // Cleared first: a request arriving now finds the key unlocked and never joins a finished wait.
                    self.unlockRequest = nil
                    await self.unlockWait.finish(.unlocked)
                } else if Date.now >= request.deadline {
                    self.unlockRequest = nil
                    await self.unlockWait.finish(.timedOut)
                }
            }
            SSHApprovalNotifier.cancel(request.id)
        }
    }

    /// `unlockedAt`: the vault was unlocked for this signature, which proves the owner is here.
    private func approve(_ identity: SSHAgentServer.Identity, _ peer: SSHAgentServer.Peer, unlockedAt: Date?) async -> Bool {
        if let approveOverride {
            let allowed = approveOverride(identity.name, peer.processName)
            recent.insert((.now, identity.name, peer.processName, allowed), at: 0)
            if recent.count > 8 { recent.removeLast() }
            return allowed
        }
        let requester = SSHProcess.requester(for: peer)
        guard model?.isUnlocked == true else {
            record(requester, key: identity.name, outcome: .locked)
            return false
        }
        trust.expire(now: .now)
        trustedUntilLock = trust.untilLock
        if trust.allows(trustKey: requester.trustKey, keyID: identity.id, now: .now) != nil {
            record(requester, key: identity.name, outcome: .reusedTrust)
            model?.noteActivity()
            return true
        }
        if allowlist.contains(requester.trustKey) {
            record(requester, key: identity.name, outcome: .allowlisted)
            model?.noteActivity()
            return true
        }

        let pair = "\(requester.trustKey)|\(identity.id)"
        if let existing = inflight[pair] {
            if let id = inflightPrompt[pair] {
                await prompts.noteJoined(id)
                await refreshPending()
            }
            let (ok, choice) = await existing.value
            record(requester, key: identity.name, outcome: Self.outcome(ok: ok, choice: choice))
            if ok { model?.noteActivity() }
            return ok
        }

        let prompt = SSHPrompt(id: UUID(), trustKey: requester.trustKey, displayName: requester.displayName,
                               via: requester.via, path: requester.peerPath, keyID: identity.id, keyName: identity.name,
                               appPath: requester.appPath, confirmedByUnlock: unlockedAt != nil)
        let generation = authorizationGeneration
        let task = Task { @MainActor in
            async let choice = self.prompts.ask(prompt)
            await Task.yield()
            await self.refreshPending()
            SSHApprovalNotifier.arm(prompt)
            let decided = await choice
            SSHApprovalNotifier.cancel(prompt.id)
            let ok = await self.authenticate(decided, requester: requester, identity: identity, generation: generation,
                                             unlockedAt: unlockedAt)
            await self.refreshPending()
            return (ok, decided)
        }
        inflight[pair] = task
        inflightPrompt[pair] = prompt.id
        let (ok, choice) = await task.value
        inflight[pair] = nil
        inflightPrompt[pair] = nil
        record(requester, key: identity.name, outcome: Self.outcome(ok: ok, choice: choice))
        if ok { model?.noteActivity() }
        return ok
    }

    private func authenticate(_ choice: SSHChoice, requester: SSHRequester, identity: SSHAgentServer.Identity, generation: UUID,
                              unlockedAt: Date? = nil) async -> Bool {
        guard case .allow(let grant) = choice, !authenticating, generation == authorizationGeneration,
              model?.isUnlocked == true else { return false }
        // Unlocking for this very signature already proved the owner. Always Allow still asks: it outlives the unlock.
        let confirmed = grant != .always && unlockedAt.map { Date.now.timeIntervalSince($0) < Self.unlockConfirms } == true
        if !confirmed {
            authenticating = true
            hidePrompt()
            defer { authenticating = false; authentication = nil }
            let context = LAContext()
            authentication = context
            context.localizedCancelTitle = String(localized: "Deny")
            let reason = String(localized: "allow “\(requester.displayName)” to sign with the SSH key “\(identity.name)”")
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
            guard ok else { return false }
        }
        guard model?.isUnlocked == true, generation == authorizationGeneration else { return false }
        if grant == .always {
            var list = allowlist
            list.add(SSHAllowlistEntry(trustKey: requester.trustKey, displayName: requester.displayName))
            allowlist = list
            try? allowlist.save(to: allowlistFile)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: allowlistFile.path)
            return true
        }
        let until: Date? = switch grant {
        case .once: Date.now.addingTimeInterval(15)
        case .tenMinutes: Date.now.addingTimeInterval(600)
        case .untilLock, .always: nil
        }
        trust.grant(SSHTrust(trustKey: requester.trustKey, keyID: identity.id, displayName: requester.displayName,
                             keyName: identity.name, until: until))
        trustedUntilLock = trust.untilLock
        return true
    }

    func revokeAllowlist(trustKey: String) {
        var list = allowlist
        list.remove(trustKey: trustKey)
        do { try list.save(to: allowlistFile) }
        catch { model?.flash(String(localized: "Couldn't save the SSH permission change. The permission is still listed.")); return }
        allowlist = list
        // Removing permanent permission also ends this caller's cached temporary trust.
        trust.revoke(trustKey: trustKey)
        trustedUntilLock = trust.untilLock
    }

    private func refreshPending() async {
        let snap = await prompts.snapshot()
        pending = snap.current
        pendingCount = snap.count
        pendingDeadline = snap.deadline
        if pending != nil { ensureWatch() }
        presentPending()
    }

    private func presentPending(reveal: Bool = false) {
        guard !authenticating, let prompt = pending, let deadline = pendingDeadline else {
            hidePrompt()
            return
        }
        if windowForPrompt != prompt.id, let notch = model?.notchForApprovals {
            approvalPanel.hide()
            let promptID = prompt.id
            notch.present(NotchRequest(id: promptID, kind: .ssh, symbol: "key.fill", title: prompt.displayName,
                subtitle: String(localized: "wants to sign with \(prompt.keyName)"),
                detail: [prompt.via, (model?.sessions.count ?? 0) > 1
                    ? model?.items.first { $0.id == prompt.keyID }.flatMap { item in model?.accounts.first { $0.id == item.accountId }?.email }
                    : nil].compactMap { $0 }.joined(separator: " · "),
                deadline: Date.now.addingTimeInterval(NotchStatusController.seconds(ContinuousClock.now.duration(to: deadline))),
                waiting: pendingCount, leadsWithUntilLock: pendingLeadsWithUntilLock) { [weak self] choice in
                    guard let self else { return }
                    switch choice {
                    case .deny: choose(.deny, promptID: promptID)
                    case .once: choose(.allow(.once), promptID: promptID)
                    case .tenMinutes: choose(.allow(.tenMinutes), promptID: promptID)
                    case .untilLock: choose(.allow(.untilLock), promptID: promptID)
                    case .review:
                        windowForPrompt = promptID
                        model?.notch?.clearRequest(.ssh)
                        presentPending(reveal: true)
                    }
                })
            return
        }
        model?.notch?.clearRequest(.ssh)
        approvalPanel.show(prompt, deadline: deadline, pendingCount: pendingCount,
                           leadsWithUntilLock: pendingLeadsWithUntilLock, reveal: reveal) { [weak self] choice in
            self?.choose(choice, promptID: prompt.id)
        }
    }

    private func ensureWatch() {
        guard !watching else { return }
        watching = true
        Task { @MainActor in
            while self.pendingCount > 0 {
                try? await Task.sleep(for: .seconds(1))
                await self.prompts.expire(now: .now)
                await self.refreshPending()
            }
            self.watching = false
        }
    }

    private func record(_ requester: SSHRequester, key: String, outcome: SSHAccessOutcome) {
        let allowed = switch outcome {
        case .allowedOnce, .allowedForTenMinutes, .allowedUntilLock, .allowlisted, .reusedTrust: true
        default: false
        }
        recent.insert((.now, key, requester.displayName, allowed), at: 0)
        if recent.count > 8 { recent.removeLast() }
        accessLog.append(SSHAccessEvent(id: UUID(), date: .now, appName: requester.displayName, via: requester.via,
                                         path: requester.peerPath, keyName: key, outcome: outcome, trustKey: requester.trustKey))
        try? accessLog.save(to: accessLogFile)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: accessLogFile.path)
    }

    private static func outcome(ok: Bool, choice: SSHChoice) -> SSHAccessOutcome {
        if case .timedOut = choice { return .timedOut }
        guard ok else { return .denied }
        switch choice {
        case .allow(.once): return .allowedOnce
        case .allow(.tenMinutes): return .allowedForTenMinutes
        case .allow(.untilLock): return .allowedUntilLock
        case .allow(.always): return .allowlisted
        case .deny, .timedOut: return .denied
        }
    }
}

/// A signature waiting for the vault to unlock, as the unlock screen shows it. No key material.
struct SSHUnlockRequest: Equatable {
    var id: UUID
    var displayName: String
    var via: String
    var keyName: String
    var accountID: String
    var deadline: Date
    var waiting = 1
}
