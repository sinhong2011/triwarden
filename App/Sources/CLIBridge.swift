import AppKit
import TriCrypto
import Foundation
import LocalAuthentication
import Observation
import SSHAgent
import UserNotifications
import VaultwardenAPI

/// Answers the `tw` command over a socket in the App Group container. Anything that reveals vault
/// data needs the vault unlocked plus an approval (Touch ID or the Mac password) naming the program.
@MainActor @Observable
final class CLIBridge {
    static var defaultSocket: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AccountStore.appGroup)
            ?? FileManager.default.temporaryDirectory).appending(path: CLISocket.name)
    }

    /// Where the bundled tool lives, for the install command.
    static var toolPath: String { Bundle.main.bundleURL.appending(path: "Contents/MacOS/tw").path }

    private(set) var isRunning = false
    /// A browser whose extension has reached us: when, and for Chromium the extension's id. It is what Settings › Browser
    /// shows as Connected (the app is sandboxed and cannot read the browsers' folders). Kept across launches.
    struct Seen: Codable, Equatable { var date: Date; var extensionID: String? }
    private(set) var seenBrowsers: [String: Seen] = {
        UserDefaults.standard.data(forKey: "browserSeen").flatMap { try? JSONDecoder().decode([String: Seen].self, from: $0) } ?? [:]
    }()

    private func noteBrowser(_ request: CLIRequest) {
        guard let id = request.browser, id.count < 120 else { return }
        let extensionID = request.origin.flatMap { $0.hasPrefix("chrome-extension://") ? String($0.dropFirst(19).dropLast()) : nil }
        // A minute is fine-grained enough for "last used", and keeps the defaults from being written on every request.
        if let seen = seenBrowsers[id], seen.extensionID == extensionID, Date.now.timeIntervalSince(seen.date) < 60 { return }
        seenBrowsers[id] = Seen(date: .now, extensionID: extensionID)
        UserDefaults.standard.set(try? JSONEncoder().encode(seenBrowsers), forKey: "browserSeen")
    }

    private(set) var lastError: String?
    private var server: FramedSocketServer?
    private var approvedUntil: [String: Date] = [:]
    /// Sites whose one-time codes were approved for the browser extension a moment ago, so the code on the screen can
    /// roll over, and the fill that follows, without asking again. In memory only, per site, and dropped on lock.
    private var revealedSites: [String: Date] = [:]
    private static let revealSeconds: TimeInterval = 60
    /// When each login was last filled into a page, so the ones you use come first. In memory only, dropped on lock.
    private var lastFilled: [String: Date] = [:]
    private weak var model: AppModel?
    /// Self-test hook: skip the Touch ID prompt.
    var approveOverride: ((String) -> Bool)?

    /// Logins the browser extension saw you submit, newest last. They wait in the bell, the menu bar panel and a
    /// banner for Save or Not Now; nothing is written until you answer. Kept in memory only and dropped on lock.
    private(set) var pendingSaves: [PendingLoginSave] = []
    /// Site + username pairs you said Not Now to. They stay quiet until the vault locks.
    private var declinedSaves: Set<String> = []
    /// A save arrived since the vault window was last brought forward: bringing it forward opens the bell.
    var revealSavesOnActivate = false

    /// Runs while the command line or the browser extension is turned on.
    func refreshRunning() {
        let wanted = UserDefaults.standard.bool(forKey: Pref.cli) || UserDefaults.standard.bool(forKey: Pref.browser)
        if wanted { start() } else { stop() }
    }

    init(model: AppModel) { self.model = model }

    func start(at socket: URL = defaultSocket) {
        guard server == nil else { return }
        let server = FramedSocketServer(socketURL: socket) { [weak self] request, peer in
            let response: CLIResponse
            if let decoded = try? JSONDecoder().decode(CLIRequest.self, from: request) {
                response = await self?.handle(decoded, peer: peer) ?? .failure("Triwarden is quitting.")
            } else {
                response = .failure("Unreadable request — is tw from the same version as the app?")
            }
            return (try? JSONEncoder().encode(response)) ?? Data()
        }
        do {
            try server.start()
            self.server = server
            isRunning = true
            lastError = nil
        } catch {
            lastError = String(localized: "Couldn't start the command-line bridge: \(String(describing: error))")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    func reset() {
        approvedUntil = [:]
        revealedSites = [:]
        lastFilled = [:]
        LoginSaveNotifier.withdraw(pendingSaves.map(\.id))
        pendingSaves = []
        declinedSaves = []
        revealSavesOnActivate = false
    }

    // MARK: Saving from the browser

    enum SaveDecision: Equatable {
        /// Already in the vault as typed.
        case unchanged
        /// Not worth asking: no username on a site that already has logins, so it is most likely a "confirm your
        /// password" step (GitHub's sudo mode and the like), and there is no telling which login it belongs to.
        case ignore
        case add
        case update(existingID: String, name: String)
    }

    /// What a submitted login means for the vault.
    static func decide(host: String, username: String, password: String, items: [VaultItem]) -> SaveDecision {
        let siteLogins = Self.logins(for: host, in: items)
        guard !username.isEmpty else {
            if siteLogins.contains(where: { $0.password == password }) { return .unchanged }
            return siteLogins.isEmpty ? .add : .ignore
        }
        guard let existing = siteLogins.first(where: { ($0.username ?? "").caseInsensitiveCompare(username) == .orderedSame }) else {
            return .add
        }
        return existing.password == password ? .unchanged : .update(existingID: existing.id, name: existing.name)
    }

    /// Queues a submitted login for you to answer later, without taking the screen. Returns what happened.
    func queueSave(host: String, scheme: String, username: String, password: String, items: [VaultItem]) -> String {
        let existing: (id: String, name: String)?
        switch Self.decide(host: host, username: username, password: password, items: items) {
        case .unchanged: return "unchanged"
        case .ignore: return "ignored"
        case .add: existing = nil
        case .update(let id, let name): existing = (id, name)
        }
        let key = PendingLoginSave.key(host: host, username: username)
        guard !declinedSaves.contains(key) else { return "skipped" }
        // One entry per site and username: a retry after a typo replaces the first attempt instead of piling up.
        let replaced = pendingSaves.filter { $0.key == key }
        if let same = replaced.first, same.password == password, same.existingID == existing?.id { return "pending" }
        pendingSaves.removeAll { $0.key == key }
        LoginSaveNotifier.withdraw(replaced.map(\.id))
        let pending = PendingLoginSave(host: host, scheme: scheme, username: username, password: password,
                                       existingID: existing?.id, existingName: existing?.name)
        pendingSaves.append(pending)
        if pendingSaves.count > Self.maxPendingSaves {
            let dropped = pendingSaves.prefix(pendingSaves.count - Self.maxPendingSaves)
            LoginSaveNotifier.withdraw(dropped.map(\.id))
            pendingSaves.removeFirst(dropped.count)
        }
        revealSavesOnActivate = true
        LoginSaveNotifier.post(pending)
        return "pending"
    }

    private static let maxPendingSaves = 8

    /// Save (or update) a waiting login, or put it away with Not Now. False when it couldn't be written.
    @discardableResult
    func answerSave(_ id: String, save: Bool) async -> Bool {
        guard let index = pendingSaves.firstIndex(where: { $0.id == id }) else { return false }
        let pending = pendingSaves.remove(at: index)
        LoginSaveNotifier.withdraw([pending.id])
        if pendingSaves.isEmpty { revealSavesOnActivate = false }
        guard save else {
            declinedSaves.insert(pending.key)
            return true
        }
        guard let model, model.isUnlocked else { return false }
        let written: Bool
        // The login it would update may have gone since: then it is a new login after all.
        if let existingID = pending.existingID,
           model.items.contains(where: { $0.id == existingID && !$0.isDeleted && !$0.isArchived }) {
            written = await model.updateItem(existingID, edit: CipherEdit(password: pending.password))
        } else {
            let name = pending.host.hasPrefix("www.") ? String(pending.host.dropFirst(4)) : pending.host
            let edit = CipherEdit(name: name, username: pending.username, password: pending.password,
                                  uri: "\(pending.scheme)://\(pending.host)")
            written = await model.createItem(.login, edit: edit)
        }
        // Offline or refused: keep it in the bell to try again, unless the vault locked meanwhile.
        if !written, model.isUnlocked, !pendingSaves.contains(where: { $0.key == pending.key }) {
            pendingSaves.append(pending)
        }
        return written
    }

    private func handle(_ request: CLIRequest, peer: FramedSocketServer.Peer) async -> CLIResponse {
        guard let model else { return .failure("Triwarden is quitting.") }
        let browserCommand = [.match, .fill, .save, .copy].contains(request.command)
        if browserCommand { noteBrowser(request) }
        let enabled = UserDefaults.standard.bool(forKey: browserCommand ? Pref.browser : Pref.cli) || approveOverride != nil
        guard enabled else {
            return .failure(browserCommand ? "Turn on the browser extension in Triwarden › Settings › Browser."
                                           : "Turn on “Answer the tw command” in Triwarden › Settings › Developer.")
        }
        switch request.command {
        case .match:
            // Names, usernames and site icons only, for the page's site, and only for our own extension/host binaries.
            // The one-time codes shown on a code field are secrets like the ones `fill` returns: they wait for the same
            // approval, and a refusal still lists the logins, just without the digits.
            guard Self.isOwnBinary(peer) else { return .failure("Unknown client.") }
            let autoShow = UserDefaults.standard.bool(forKey: Pref.browserAutoShow)
            guard model.isUnlocked else {
                var locked = CLIResponse.failure(Self.locked)
                locked.autoShow = autoShow // the setting is known even while the vault is locked
                return locked
            }
            guard let host = request.url.flatMap(URL.init(string:))?.host()?.lowercased() else {
                return .list([], autoShow: autoShow)
            }
            let matches = Self.logins(for: host, in: model.items)
            // Codes are secrets: they only come when the person asked for them (the icon in the field, the shortcut),
            // never because a field was focused. One approval covers that site for a minute, so a code that rolls over
            // or the fill that follows does not ask again.
            var withCodes = false
            if request.codes == true, request.reveal == true, matches.contains(where: { $0.totp != nil && !$0.reprompt }) {
                if let until = revealedSites[host], until > .now {
                    withCodes = true
                } else if await approve(String(localized: "show one-time codes for \(host)"), peer: peer, browser: true) {
                    revealedSites[host] = .now.addingTimeInterval(Self.revealSeconds)
                    withCodes = true
                }
            }
            // Exact address first, then the logins filled most recently, then by name.
            let ordered = matches.sorted { a, b in
                let ea = a.hosts.contains(host), eb = b.hosts.contains(host)
                if ea != eb { return ea }
                let da = lastFilled[a.id] ?? .distantPast, db = lastFilled[b.id] ?? .distantPast
                if da != db { return da > db }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return .list(ordered.map {
                CLIResponse.Row(id: $0.id, name: $0.name, detail: $0.username ?? "", totpPeriod: $0.totp?.period,
                                icon: Self.iconPNG(for: $0, model: model),
                                code: withCodes && !$0.reprompt ? $0.totp?.code() : nil,
                                exact: $0.hosts.contains(host), passkey: $0.hasPasskey)
            }, autoShow: autoShow)
        case .fill:
            guard model.isUnlocked else { return .failure(Self.locked) }
            guard let item = model.items.first(where: { $0.id == request.query && !$0.isDeleted && !$0.isArchived }) else {
                return .failure("That login is no longer in your vault.")
            }
            let host = request.url.flatMap(URL.init(string:))?.host() ?? ""
            // Only fill a login on the site it belongs to.
            guard Self.logins(for: host.lowercased(), in: [item]).count == 1 else { return .failure("“\(item.name)” isn't for \(host).") }
            // A code reveal a moment ago on this site covers the fill that follows, except for logins that ask for the
            // master password: those are never waved through.
            let revealed = !item.reprompt && (revealedSites[host.lowercased()].map { $0 > .now } ?? false)
            if !revealed {
                guard await approve(String(localized: "fill “\(item.name)” on \(host)"), peer: peer, browser: true) else { return .failure(Self.denied) }
            }
            lastFilled[item.id] = .now
            guard let totp = item.totp else { return .credentials(username: item.username, password: item.password, totp: nil) }
            let fresh = await Self.freshCode(totp)
            return .credentials(username: item.username, password: item.password, totp: fresh.code,
                                totpRemaining: fresh.remaining, totpPeriod: totp.period)
        case .copy:
            guard Self.isOwnBinary(peer) else { return .failure("Unknown client.") }
            guard model.isUnlocked else { return .failure(Self.locked) }
            guard let item = model.items.first(where: { $0.id == request.query && !$0.isDeleted && !$0.isArchived }) else {
                return .failure("That login is no longer in your vault.")
            }
            let host = request.url.flatMap(URL.init(string:))?.host() ?? ""
            guard Self.logins(for: host.lowercased(), in: [item]).count == 1 else { return .failure("“\(item.name)” isn't for \(host).") }
            let field = (request.field ?? "password").lowercased()
            guard ["username", "password", "totp"].contains(field) else { return .failure("Unsupported request.") }
            guard Self.value(field, of: item) != nil else {
                return .failure("“\(item.name)” has no \(field == "totp" ? "one-time code" : field).")
            }
            // A login that asks for the master password is not copied from a browser menu.
            guard !item.reprompt || field == "username" else { return .failure("“\(item.name)” asks for your master password; open it in Triwarden.") }
            let what = field == "totp" ? String(localized: "the one-time code") : field
            guard await approve(String(localized: "copy \(what) of “\(item.name)”"), peer: peer, browser: true) else {
                return .failure(Self.denied)
            }
            lastFilled[item.id] = .now
            switch field {
            case "username": model.copy(item.username ?? "", label: String(localized: "Username"))
            case "totp": if let totp = item.totp { model.copy(totp.code(), label: String(localized: "Code")) }
            default: model.copy(item.password ?? "", label: String(localized: "Password"))
            }
            return .success("copied")
        case .save:
            guard Self.isOwnBinary(peer) else { return .failure("Unknown client.") }
            guard model.isUnlocked else { return .failure(Self.locked) }
            guard let url = request.url.flatMap(URL.init(string:)), let host = url.host()?.lowercased(),
                  let password = request.password, !password.isEmpty else { return .failure("Nothing to save.") }
            let username = (request.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(queueSave(host: host, scheme: url.scheme ?? "https", username: username, password: password,
                                      items: model.items))
        case .status:
            return .success(model.isUnlocked
                ? "unlocked · \(model.sessions.count) account(s) · \(model.items.filter { !$0.isDeleted && !$0.isArchived }.count) items"
                : "locked")
        case .generate:
            var generator = PasswordGenerator.saved
            if let length = request.length { generator.length = min(max(length, 8), 128) }
            return .success(generator.generate())
        case .lock:
            model.lock()
            return .success("locked")
        case .list:
            guard model.isUnlocked else { return .failure(Self.locked) }
            guard await approve(String(localized: "list your vault items"), peer: peer) else { return .failure(Self.denied) }
            let q = request.query ?? ""
            let rows = model.items.filter { !$0.isDeleted && !$0.isArchived && (q.isEmpty || Self.matches($0, q)) }.map {
                CLIResponse.Row(id: $0.id, name: $0.name, detail: $0.username ?? $0.host ?? "")
            }
            return .list(rows)
        case .get, .code:
            guard model.isUnlocked else { return .failure(Self.locked) }
            let item: VaultItem
            switch Self.resolve(request.query ?? "", in: model.items) {
            case .success(let found): item = found
            case .failure(let message): return .failure(message.text)
            }
            let field = request.command == .code ? "totp" : (request.field ?? "password").lowercased()
            guard let value = Self.value(field, of: item) else {
                return .failure("“\(item.name)” has no \(field == "totp" ? "one-time code" : field).")
            }
            let what = field == "totp" ? String(localized: "the one-time code") : field
            guard await approve(String(localized: "read \(what) of “\(item.name)”"), peer: peer) else { return .failure(Self.denied) }
            return .success(value)
        }
    }

    static let locked = "The vault is locked. Unlock Triwarden first."
    static let denied = "Not approved."

    /// `browser`: asked on behalf of the browser extension. It has its own window (Settings › Browser), apart from the
    /// `tw` command's, and its own grants, so approving a browser does not approve the terminal.
    private func approve(_ action: String, peer: FramedSocketServer.Peer, browser: Bool = false) async -> Bool {
        let grant = browser ? "browser:" + peer.processName : peer.processName
        if let until = approvedUntil[grant], until > .now { return true }
        let allowed: Bool
        if let approveOverride {
            allowed = approveOverride(action)
        } else {
            let context = LAContext()
            context.localizedCancelTitle = String(localized: "Deny")
            let reason = String(localized: "allow “\(peer.processName)” to \(action)")
            allowed = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
        }
        let window = UserDefaults.standard.integer(forKey: browser ? Pref.browserApprovalSeconds : Pref.cliApprovalSeconds)
        // 0 asks every time; -1 (browser only) asks once and holds until the vault locks, which clears every grant.
        if allowed, window > 0 { approvedUntil[grant] = .now.addingTimeInterval(TimeInterval(window)) }
        else if allowed, window < 0, browser { approvedUntil[grant] = .distantFuture }
        if allowed { model?.noteActivity() }
        return allowed
    }

    /// The site's icon from the vault list's cache (so only the icon service you already use is asked, and only when
    /// icons are on), as a base64 PNG. A site not cached yet starts loading and appears the next time.
    static func iconPNG(for item: VaultItem, model: AppModel) -> String? {
        guard IconStore.enabled, item.kind == .login, let host = item.host else { return nil }
        let store = IconStore.shared
        store.request(host: host, environment: model.session(for: item.accountId)?.environment ?? store.fallbackEnvironment)
        guard let image = store.image(for: host),
              let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:])?.base64EncodedString()
    }

    /// A code that will still be valid when the page submits it. One with a few seconds left would often expire on
    /// the way, so wait for the next one. (Short periods are left alone: they would always be waiting.)
    static func freshCode(_ totp: TOTP) async -> (code: String, remaining: Int) {
        let margin = 3
        if totp.period > 10, totp.secondsRemaining() <= margin {
            try? await Task.sleep(for: .seconds(Double(totp.secondsRemaining()) + 0.1))
        }
        return (totp.code(), totp.secondsRemaining())
    }

    /// Our Safari extension and the bundled `tw` (Chrome's native-messaging host) live inside the app.
    static func isOwnBinary(_ peer: FramedSocketServer.Peer) -> Bool {
        guard let path = peer.path else { return false }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/")
    }

    /// Logins for `host`: same host or a subdomain/parent of it.
    static func logins(for host: String, in items: [VaultItem]) -> [VaultItem] {
        guard !host.isEmpty else { return [] }
        return items.filter { item in
            guard !item.isDeleted, !item.isArchived, item.kind == .login, item.password != nil else { return false }
            return item.hosts.contains { h in h == host || host.hasSuffix("." + h) || h.hasSuffix("." + host) }
        }
    }

    // MARK: Lookup

    struct Message: Error { let text: String }

    static func matches(_ item: VaultItem, _ q: String) -> Bool {
        item.name.localizedCaseInsensitiveContains(q) || (item.username?.localizedCaseInsensitiveContains(q) ?? false)
            || (item.host?.localizedCaseInsensitiveContains(q) ?? false)
            || item.websites.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Id, then exact name, then a unique partial match.
    static func resolve(_ query: String, in items: [VaultItem]) -> Result<VaultItem, Message> {
        let live = items.filter { !$0.isDeleted && !$0.isArchived }
        if let byID = live.first(where: { $0.id == query }) { return .success(byID) }
        let exact = live.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        if exact.count == 1 { return .success(exact[0]) }
        let partial = exact.isEmpty ? live.filter { matches($0, query) } : exact
        switch partial.count {
        case 1: return .success(partial[0])
        case 0: return .failure(Message(text: "No item matches “\(query)”."))
        default:
            let names = partial.prefix(5).map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
            return .failure(Message(text: "“\(query)” matches \(partial.count) items: \(names). Use the id or a more exact name."))
        }
    }

    static func value(_ field: String, of item: VaultItem) -> String? {
        switch field {
        case "password": return item.password
        case "username": return item.username
        case "uri", "url": return item.uri
        case "notes": return item.notes
        case "totp", "code": return item.totp?.code()
        default:
            return item.customFields.first { $0.name.caseInsensitiveCompare(field) == .orderedSame }?.value
                ?? item.properties.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
        }
    }
}

/// A login the browser extension saw you submit, waiting for Save or Not Now.
struct PendingLoginSave: Identifiable, Equatable, Sendable {
    let id = UUID().uuidString
    let host: String
    let scheme: String
    let username: String
    let password: String
    /// The login whose password this replaces; nil saves a new login.
    let existingID: String?
    let existingName: String?
    let date = Date.now

    var key: String { Self.key(host: host, username: username) }
    static func key(host: String, username: String) -> String { host + "\u{0}" + username.lowercased() }

    var isUpdate: Bool { existingID != nil }
    var title: String {
        if let existingName { return String(localized: "Update the password for “\(existingName)”?") }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return String(localized: "Save the login for \(site)?")
    }
    var detail: String { username.isEmpty ? host : "\(username) · \(host)" }
}

/// The banner for a login waiting to be saved. Save and Not Now answer it right there; a click on the banner opens
/// the bell. It never carries the password.
enum LoginSaveNotifier {
    static let saveCategory = "login-save"
    static let updateCategory = "login-update"
    static let saveAction = "login-save.save"
    static let notNowAction = "login-save.not-now"
    static let userInfoKey = "loginSave"

    /// The banner buttons. Called once at launch.
    static func registerCategories() {
        let notNow = UNNotificationAction(identifier: notNowAction, title: String(localized: "Not Now"), options: [])
        let save = UNNotificationAction(identifier: saveAction, title: String(localized: "Save"), options: [])
        let update = UNNotificationAction(identifier: saveAction, title: String(localized: "Update"), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: saveCategory, actions: [save, notNow], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: updateCategory, actions: [update, notNow], intentIdentifiers: [], options: []),
        ])
    }

    static func post(_ pending: PendingLoginSave) {
        // The self-tests answer saves directly; they shouldn't ask for notification permission or leave banners.
        guard !CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") || $0 == "--snapshot" }) else { return }
        let id = pending.id, title = pending.title, isUpdate = pending.isUpdate
        let body = pending.username.isEmpty
            ? String(localized: "From your browser · \(pending.host)")
            : String(localized: "\(pending.username) · from your browser")
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { add(id: id, title: title, body: body, isUpdate: isUpdate, center: center) }
                }
            case .authorized, .provisional:
                add(id: id, title: title, body: body, isUpdate: isUpdate, center: center)
            default:
                break // The bell and the menu bar panel still show it.
            }
        }
    }

    private static func add(id: String, title: String, body: String, isUpdate: Bool, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = isUpdate ? updateCategory : saveCategory
        content.userInfo = [userInfoKey: id]
        center.add(UNNotificationRequest(identifier: "login-save-" + id, content: content, trigger: nil))
    }

    static func withdraw(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let identifiers = ids.map { "login-save-" + $0 }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
