#if DEBUG
import TriCrypto
import Foundation
import VaultwardenAPI

/// `--selftest-cloud us|eu` — the self-test against the official Bitwarden cloud, run by a person from
/// their own terminal (`make selftest-cloud`). The account comes from BITWARDEN_ACCOUNT / BITWARDEN_PASSWORD
/// in the environment, never from arguments; emailed device codes and 2FA codes are read from the terminal.
/// Use an empty account made for testing: items are created and deleted.
@MainActor
enum CloudSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest-cloud") else { return }
        let region = i + 1 < args.count ? args[i + 1] : "us"
        let env = ProcessInfo.processInfo.environment
        guard let email = env["BITWARDEN_ACCOUNT"], let password = env["BITWARDEN_PASSWORD"], !email.isEmpty, !password.isEmpty else {
            print("Set BITWARDEN_ACCOUNT and BITWARDEN_PASSWORD (e.g. in .env, used by `make selftest-cloud`).")
            exit(64)
        }
        AccountStore.namespace = "SelfTestCloud"
        AutoFillIdentities.isEnabled = false
        Task {
            var failures = 0
            func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures += 1 } }
            func ask(_ prompt: String) async -> String {
                print(prompt, terminator: " ")
                fflush(stdout)
                return await Task.detached { readLine() ?? "" }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let model = AppModel()
            for account in model.accounts { model.logOut(account.id) }
            model.serverKind = region == "eu" ? .bitwardenEU : .bitwardenUS
            model.email = email
            print("Logging in to \(model.serverKind == .bitwardenEU ? "bitwarden.eu" : "bitwarden.com")…")
            await model.login(password: password)
            if model.phase.id == AppModel.Phase.deviceVerification.id {
                await model.login(password: password, code: await ask("Bitwarden emailed a verification code. Enter it:"))
            }
            if model.phase.id == AppModel.Phase.twoFactor(providers: []).id {
                await model.login(password: password, code: await ask("Two-step login code from your authenticator app:"))
            }
            check(model.isUnlocked, "login, key derivation and sync \(model.errorMessage ?? "")")
            guard model.isUnlocked, let accountId = model.sessions.first?.id else {
                print("SELFTEST FAILED (cannot continue without a session)")
                exit(1)
            }
            print("  vault has \(model.items.count) item(s), \(model.folders.count) folder(s)")

            // Items
            let tag = "triwarden-selftest-\(Int(Date().timeIntervalSince1970))"
            let created = await model.createItem(.login, edit: CipherEdit(name: tag, username: "test", password: "pw-1",
                                                                         totp: "JBSWY3DPEHPK3PXP", uri: "https://example.com"))
            var item = model.items.first { $0.name == tag }
            check(created && item?.totp != nil && item?.host == "example.com", "create login (TOTP, website)")
            if let id = item?.id {
                let edited = await model.updateItem(id, edit: CipherEdit(password: "pw-2"))
                item = model.items.first { $0.id == id }
                check(edited && item?.password == "pw-2" && item?.username == "test", "edit keeps untouched fields")
                if let it = item { await model.toggleFavorite(it) }
                check(model.items.first { $0.id == id }?.favorite == true, "favorite")
                if let it = model.items.first(where: { $0.id == id }) { await model.trash(it) }
                check(model.items.first { $0.id == id }?.isDeleted == true, "move to Trash")
                if let it = model.items.first(where: { $0.id == id }) { await model.restore(it) }
                check(model.items.first { $0.id == id }?.isDeleted == false, "restore")
            }
            var card = CipherEdit(name: tag + "-card")
            card.properties = ["cardholderName": "Test", "number": "4111111111111111", "code": "123"]
            card.customFields = [CustomField(name: "PIN", value: "0000", kind: .hidden)]
            _ = await model.createItem(.card, edit: card)
            let cardItem = model.items.first { $0.name == tag + "-card" }
            check(cardItem?.properties["number"] == "4111111111111111" && cardItem?.customFields.count == 1, "card with custom field")

            // Passkey stored on a login.
            let hash = Data(repeating: 1, count: 32)
            if let reg = try? Passkey.register(rpId: "example.com", userName: "test", userHandle: Data("t".utf8), clientDataHash: hash) {
                var edit = CipherEdit(name: tag + "-passkey", username: "test", uri: "https://example.com")
                edit.passkey = reg.credential
                _ = await model.createItem(.login, edit: edit)
                let pk = model.items.first { $0.name == tag + "-passkey" }?.passkeys.first
                check(pk.flatMap { try? Passkey.assert($0, clientDataHash: hash) }?.credentialID == reg.credentialID, "passkey saved and signs")
            }

            // Folder
            let folderID = await model.createFolder(name: tag, accountId: accountId)
            check(folderID != nil && model.folders.contains { $0.name == tag }, "create folder")
            if let folderID { await model.deleteFolder(folderID) }

            // Send
            let sent = await model.createSend(SendDraft(name: tag, content: .text("hello", hidden: false),
                                                        deletionDate: .now.addingTimeInterval(3_600)), accountId: accountId)
            let send = model.sends.first { $0.name == tag }
            check(sent && send != nil, "Send: create")
            if let send { await model.deleteSend(send) }

            // Attachment (needs Premium on the cloud).
            if let note = model.items.first(where: { $0.name == tag }) {
                let file = FileManager.default.temporaryDirectory.appending(path: "\(tag).txt")
                try? Data("attachment".utf8).write(to: file)
                let attached = await model.addAttachments([file], to: note)
                try? FileManager.default.removeItem(at: file)
                if attached, let a = model.items.first(where: { $0.id == note.id })?.attachments.first {
                    await model.previewAttachment(a, of: note)
                    check(model.previewURL.flatMap { try? Data(contentsOf: $0) } == Data("attachment".utf8), "attachment upload + download")
                } else {
                    print("SKIP attachment (\(model.toast ?? "not available") — free accounts can't add attachments)")
                }
            }

            // Clean up everything we made.
            for it in model.items where it.name.hasPrefix(tag) { await model.deleteForever(it) }
            check(!model.items.contains { $0.name.hasPrefix(tag) }, "clean up test items")

            // Lock, offline unlock, resume with refresh token.
            model.lock()
            await model.unlock(password: password, accountId: accountId)
            check(model.isUnlocked, "offline unlock with the master password")
            try? await model.refresh()
            check(model.errorMessage == nil, "re-sync with the stored session")
            model.logOut(accountId)
            check(AccountStore.load(accountId) == nil && AccountStore.refreshToken(accountId) == nil, "log out erases account and token")
            for rejection in AppModel.serverRejections { check(false, rejection) }

            print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
#endif
