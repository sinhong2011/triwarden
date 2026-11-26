#if DEBUG
import AppKit
import SSHAgent
import SwiftUI
import TriCrypto

/// Issue #251, offline: a git-style signature while the vault is locked. Real `ssh-add` and `ssh-keygen` talk to the
/// production agent service over a temporary socket. Isolated accounts, history and permissions; no Touch ID (the
/// unlock for the request is the owner check) and no window is brought forward (the presenter hook records it).
@MainActor
enum SSHLockedSelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest-ssh-locked") else { return }
        AccountStore.namespace = "SSHLockedSelfTest-" + UUID().uuidString
        AutoFillIdentities.isEnabled = false
        let application = NSApplication.shared
        Task { exit(await run() == 0 ? 0 : 1) }
        application.run()
    }

    private static func run() async -> Int {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print(ok ? "PASS" : "FAIL", label)
            if !ok { failures += 1 }
        }
        let root = URL(fileURLWithPath: "/tmp").appending(path: "tw-locked-\(getpid())")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "a.sock")
        let env = ["SSH_AUTH_SOCK": socket.path]

        let pair = SSHKeyPair.generateEd25519(comment: "selftest")
        var key = VaultItem(id: "ssh-1", accountId: "acct", kind: .sshKey, name: "GitHub signing",
                            username: nil, host: nil, password: nil, totp: nil, notes: nil, favorite: false)
        key.properties = ["privateKey": pair.privateKey, "publicKey": pair.publicKey]

        let model = AppModel()
        model.setPreviewAccounts([SavedAccount(id: "acct", email: "alex@example.com", serverKind: "selfHosted",
                                               serverURL: "https://vault.example.com", kdf: .pbkdf2(iterations: 600_000), protectedUserKey: "")])
        let agent = SSHAgentService(model: model, logURL: root.appending(path: "log.json"), allowlistURL: root.appending(path: "allow.json"))
        model.useSSHAgentForSelfTest(agent)
        var presented: [String] = []
        agent.unlockPresenter = { presented.append($0) }
        func unlock() { model.items = [key]; model.previewUnlocked = true; model.phase = .vault }
        func lock() { agent.reset(); model.items = []; model.previewUnlocked = false; model.phase = .locked }

        unlock()
        agent.start(at: socket)
        check(agent.isRunning, "agent starts on an isolated socket")
        let pubBody = String(pair.publicKey.split(separator: " ")[1])
        let unlockedList = await Snapshot.tool("ssh-add", ["-L"], env: env)
        check(unlockedList.status == 0 && unlockedList.output.contains(pubBody), "unlocked: ssh-add lists the key")
        lock()

        // 1. Listing while locked: the remembered public key, nothing private.
        let lockedList = await Snapshot.tool("ssh-add", ["-L"], env: env)
        check(lockedList.status == 0 && lockedList.output.contains(pubBody), "locked: ssh-add still lists the public key")
        let cacheFile = SSHAgentService.publicKeysURL(for: socket)
        let cached = (try? String(contentsOf: cacheFile, encoding: .utf8)) ?? ""
        check(!cached.isEmpty && !cached.contains("PRIVATE KEY") && !cached.contains(String(pair.privateKey.prefix(60).suffix(20))),
              "remembered keys file holds no private key material")

        let pubFile = root.appending(path: "key.pub")
        try? Data((pair.publicKey + "\n").utf8).write(to: pubFile)
        let signers = root.appending(path: "signers")
        try? Data("alex \(pair.publicKey)\n".utf8).write(to: signers)
        let message = Data("tree 1234\nauthor alex\n\nsigned while locked\n".utf8)
        func sign() -> Task<(status: Int32, output: String), Never> {
            Task { await Snapshot.tool("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", pubFile.path, "-q"], env: env, stdin: message) }
        }
        func waitFor(_ what: String, _ condition: () -> Bool) async -> Bool {
            for _ in 0..<100 { if condition() { return true }; try? await Task.sleep(for: .milliseconds(50)) }
            print("  (timed out waiting for \(what))")
            return false
        }

        // 2. Sign while locked → unlock screen asked for, request waits; unlock → approval (no Touch ID) → signature.
        let first = sign()
        check(await waitFor("unlock request") { agent.unlockRequest != nil }, "locked sign request waits instead of failing")
        check(presented == ["acct"], "the unlock screen is asked for once, for the key's account")
        check(agent.unlockRequest?.keyName == "GitHub signing" && agent.unlockRequest?.via == "ssh-keygen",
              "unlock screen names the key and the tool")
        if let request = agent.unlockRequest { renderBanner(request) }
        let second = sign()
        check(await waitFor("second waiter") { agent.unlockRequest?.waiting == 2 }, "a second signature joins the same wait")
        unlock()
        check(await waitFor("approval card") { agent.pending != nil }, "after unlock the usual approval appears")
        check(agent.pending?.confirmedByUnlock == true, "approval knows the unlock already confirmed the owner")
        if let pending = agent.pending { renderCard(pending) }
        if let id = agent.pending?.id { agent.choose(.allow(.once), promptID: id) }
        let signed = await first.value
        let joined = await second.value
        check(signed.status == 0, "the waiting git signature completes after Allow Once (no second Touch ID)")
        check(joined.status == 0, "the joined signature completes too")
        let sigFile = root.appending(path: "sig")
        try? Data(signed.output.utf8).write(to: sigFile)
        let verified = await Snapshot.tool("ssh-keygen", ["-Y", "verify", "-n", "git", "-I", "alex", "-f", signers.path, "-s", sigFile.path],
                                           stdin: message)
        check(verified.status == 0, "the signature verifies against the public key")
        check(agent.unlockRequest == nil, "the unlock line goes away once unlocked")
        check(agent.accessLog.events.first?.outcome == .allowedOnce || agent.accessLog.events.first?.outcome == .reusedTrust,
              "history records the allowed signature")

        // 3. Cancel on the unlock screen refuses the signature and is recorded.
        lock()
        presented = []
        let cancelled = sign()
        check(await waitFor("unlock request") { agent.unlockRequest != nil }, "locked again: request waits")
        agent.cancelUnlockRequest()
        let refused = await cancelled.value
        check(refused.status != 0, "Cancel refuses the signature")
        check(agent.unlockRequest == nil && agent.accessLog.events.first?.outcome == .denied, "Cancel is recorded as denied")

        // 4. Always Allow still asks for Touch ID: not exercised here (it would prompt). Turning the agent off forgets keys.
        agent.stop()
        check(!FileManager.default.fileExists(atPath: cacheFile.path), "turning the agent off removes the remembered public keys")
        print("SSH locked self-test: \(failures) failure(s)")
        return failures
    }

    private static var outDir: URL {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRIWARDEN_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func renderBanner(_ request: SSHUnlockRequest) {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            Snapshot.render(SSHUnlockBanner(request: request) {}.padding(20).frame(width: 520)
                                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light),
                            size: CGSize(width: 520, height: 90), appearance: appearance,
                            to: outDir.appending(path: "ssh-unlock-banner-\(name).png"))
        }
    }

    private static func renderCard(_ prompt: SSHPrompt) {
        Snapshot.render(SSHApprovalView(prompt: prompt, deadline: .now.advanced(by: .seconds(52)), pendingCount: 1,
                                        leadsWithUntilLock: false, choose: { _ in }),
                        size: CGSize(width: 560, height: 660), appearance: .aqua,
                        to: outDir.appending(path: "ssh-approval-after-unlock.png"))
    }
}
#endif
