import Darwin
import Foundation
import os

/// JSON messages between the `tw` command and the app (one frame each way per request).
public struct CLIRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        case status, list, get, code, generate, lock
        /// Browser extension: logins for a page (names/usernames only), fill one, offer to save one.
        case match, fill, save
        /// Browser extension: copy one field of a login (`field`: username, password or totp) to the clipboard. The app
        /// does the copying, so the value never reaches the extension.
        case copy
    }
    public var command: Command
    public var query: String?
    /// Browser extension: the page URL, and the credentials typed into it (`save` only).
    public var url: String?
    public var username: String?
    public var password: String?
    /// For `get`: password (default), username, uri, notes, totp, or a custom field name.
    public var field: String?
    public var length: Int?
    /// `generate` password: charset / rules (same keys as the app Generator's `generator` prefs).
    public var uppercase: Bool?
    public var lowercase: Bool?
    public var digits: Bool?
    public var symbols: Bool?
    public var avoidAmbiguous: Bool?
    public var minNumbers: Int?
    public var minSpecial: Int?
    /// `generate` passphrase: word separator / capitalisation / trailing digit (same as `passphraseGenerator`).
    public var separator: String?
    public var capitalize: Bool?
    public var includeNumber: Bool?
    /// `match`: also return each login's current one-time code. Only a code field asks for this.
    public var codes: Bool?
    /// `match`: the person asked (clicked the icon, pressed the shortcut). A field that merely took focus does not
    /// set this. With `codes`, this also returns the digits.
    public var reveal: Bool?
    /// `match`: the person asked Triwarden to fill (icon, shortcut). While locked, the app brings its window
    /// forward so they can unlock. Background `match` (rebuilding the right-click menu) does not set this.
    public var foreground: Bool?
    /// `match`: rebuilding the right-click menu — do not open unlock while locked.
    public var silent: Bool?
    /// Added by `tw` when a browser started it: that browser's extension origin (`chrome-extension://<id>/`) or, for
    /// Firefox, the add-on id. The app uses it to show which browsers are connected, since a sandboxed app cannot read
    /// their folders. The extension itself never sets it.
    public var origin: String?
    /// Added by `tw` the same way: the bundle id of the browser that started it (com.google.Chrome, ...), so the app
    /// can say which browser is connected.
    public var browser: String?

    public init(command: Command, query: String? = nil, field: String? = nil, length: Int? = nil,
                uppercase: Bool? = nil, lowercase: Bool? = nil, digits: Bool? = nil, symbols: Bool? = nil,
                avoidAmbiguous: Bool? = nil, minNumbers: Int? = nil, minSpecial: Int? = nil,
                separator: String? = nil, capitalize: Bool? = nil, includeNumber: Bool? = nil,
                url: String? = nil, username: String? = nil, password: String? = nil, codes: Bool? = nil,
                reveal: Bool? = nil, foreground: Bool? = nil, silent: Bool? = nil,
                origin: String? = nil, browser: String? = nil) {
        self.command = command; self.query = query; self.field = field; self.length = length
        self.uppercase = uppercase; self.lowercase = lowercase; self.digits = digits; self.symbols = symbols
        self.avoidAmbiguous = avoidAmbiguous; self.minNumbers = minNumbers; self.minSpecial = minSpecial
        self.separator = separator; self.capitalize = capitalize; self.includeNumber = includeNumber
        self.url = url; self.username = username; self.password = password; self.codes = codes; self.reveal = reveal
        self.foreground = foreground; self.silent = silent
        self.origin = origin; self.browser = browser
    }
}

public struct CLIResponse: Codable, Sendable, Equatable {
    public struct Row: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var detail: String
        /// `match`: the length of the login's one-time code period, if it has one. The code itself only comes with
        /// `fill`, after approval; the period lets the extension draw a countdown.
        public var totpPeriod: Int?
        /// `match`: the site's icon as a base64 PNG, when the app already has it (the same cache as the vault list).
        public var icon: String?
        /// `match` with `codes`: the login's current one-time code (not for logins that ask for the master password).
        public var code: String?
        /// `match`: the login's address is exactly this site, not a parent domain or subdomain. Rows come sorted with
        /// these first, then the ones filled most recently.
        public var exact: Bool?
        /// `match`: the login also holds a passkey for the site.
        public var passkey: Bool?
        public init(id: String, name: String, detail: String, totpPeriod: Int? = nil, icon: String? = nil,
                    code: String? = nil, exact: Bool? = nil, passkey: Bool? = nil) {
            self.id = id; self.name = name; self.detail = detail; self.totpPeriod = totpPeriod; self.icon = icon
            self.code = code; self.exact = exact; self.passkey = passkey
        }
    }

    public var ok: Bool
    public var value: String?
    /// `fill`: what to put in the page.
    public var username: String?
    public var password: String?
    public var totp: String?
    /// `fill`: seconds the one-time code stays valid, and the length of its period (for a countdown).
    public var totpRemaining: Int?
    public var totpPeriod: Int?
    public var rows: [Row]?
    public var error: String?
    /// Machine-readable reason when `ok` is false: `app_not_running`, `connection_disabled`, `vault_locked`, …
    public var code: String?
    /// `match`: whether the Browser setting "Show suggestions when a field is focused" is on. The extension keeps it.
    public var autoShow: Bool?
    /// `generate`: echo of the options that produced `value` (length = characters or passphrase words).
    public var length: Int?
    public var uppercase: Bool?
    public var lowercase: Bool?
    public var digits: Bool?
    public var symbols: Bool?
    public var avoidAmbiguous: Bool?
    public var minNumbers: Int?
    public var minSpecial: Int?
    public var separator: String?
    public var capitalize: Bool?
    public var includeNumber: Bool?
    /// `generate`: entropy estimate in bits (same formula as the app strength meter).
    public var entropyBits: Double?

    public init(ok: Bool, value: String? = nil, username: String? = nil, password: String? = nil, totp: String? = nil,
                totpRemaining: Int? = nil, totpPeriod: Int? = nil, rows: [Row]? = nil, error: String? = nil,
                code: String? = nil, autoShow: Bool? = nil, length: Int? = nil, uppercase: Bool? = nil,
                lowercase: Bool? = nil, digits: Bool? = nil, symbols: Bool? = nil, avoidAmbiguous: Bool? = nil,
                minNumbers: Int? = nil, minSpecial: Int? = nil, separator: String? = nil, capitalize: Bool? = nil,
                includeNumber: Bool? = nil, entropyBits: Double? = nil) {
        self.ok = ok; self.value = value; self.username = username; self.password = password; self.totp = totp
        self.totpRemaining = totpRemaining; self.totpPeriod = totpPeriod; self.rows = rows; self.error = error
        self.code = code
        self.autoShow = autoShow; self.length = length; self.uppercase = uppercase; self.lowercase = lowercase
        self.digits = digits; self.symbols = symbols; self.avoidAmbiguous = avoidAmbiguous
        self.minNumbers = minNumbers; self.minSpecial = minSpecial; self.separator = separator
        self.capitalize = capitalize; self.includeNumber = includeNumber; self.entropyBits = entropyBits
    }

    public static func success(_ value: String) -> CLIResponse { CLIResponse(ok: true, value: value) }
    public static func list(_ rows: [Row], autoShow: Bool? = nil) -> CLIResponse {
        CLIResponse(ok: true, rows: rows, autoShow: autoShow)
    }
    public static func failure(_ message: String, code: String? = nil) -> CLIResponse {
        CLIResponse(ok: false, error: message, code: code)
    }
    public static func credentials(username: String?, password: String?, totp: String?,
                                   totpRemaining: Int? = nil, totpPeriod: Int? = nil) -> CLIResponse {
        CLIResponse(ok: true, username: username, password: password, totp: totp,
                    totpRemaining: totpRemaining, totpPeriod: totpPeriod)
    }
}

public enum CLISocket {
    /// File name inside the App Group container.
    public static let name = "cli.sock"
}

/// Shared App Group flags the app writes so sandboxed clients can tell why the bridge is unreachable.
public enum BridgeStatus {
    /// `true` while Settings › Browser or Developer has the bridge on. Kept across quit so a missing
    /// socket means "open Triwarden", not "turn the setting on".
    public static let wantedKey = "cliBridgeWanted"
}

/// One request/response to the running app (used by `tw`, the Chrome host and the Safari extension).
public enum BridgeClient {
    public static let appGroup = "FX3VR69P5K.io.github.sinhong2011.triwarden"
    private static let log = Logger(subsystem: "io.github.sinhong2011.triwarden", category: "bridge")

    /// `~/Library/Group Containers/<group>/cli.sock`, resolved for sandboxed and unsandboxed callers alike.
    public static var defaultSocketPath: String {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return container.appending(path: CLISocket.name).path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/\(appGroup)/\(CLISocket.name)").path
    }

    /// App Group defaults the running app mirrors when Browser/CLI is toggled.
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public static func send(_ request: CLIRequest, socket: String = defaultSocketPath) -> CLIResponse {
        switch connectOrRetry(socket) {
        case .connected(let fd):
            defer { close(fd) }
            guard let body = try? JSONEncoder().encode(request), FramedSocketServer.writeFrame(fd, body),
                  let reply = FramedSocketServer.readFrame(fd, max: 8 * 1024 * 1024),
                  let response = try? JSONDecoder().decode(CLIResponse.self, from: reply) else {
                return .failure("No answer from Triwarden.")
            }
            return response
        case .failed(let err):
            // kill -9 / crash leaves a dead cli.sock (ECONNREFUSED). Drop it so the next probe sees
            // ENOENT; BridgeStatus.wanted still maps that to app_not_running. start() also unlinks
            // before bind. App Group clients (Safari appex, tw) can unlink this path.
            if err == ECONNREFUSED { unlink(socket) }
            return unavailableResponse(errno: err, socket: socket)
        }
    }

    /// One short retry: the app may still be binding `cli.sock` right after launch.
    private static func connectOrRetry(_ socket: String) -> FramedSocketServer.ConnectOutcome {
        switch FramedSocketServer.attemptConnect(to: socket) {
        case .connected(let fd):
            return .connected(fd)
        case .failed(let err):
            guard err == ECONNREFUSED || err == ENOENT else { return .failed(errno: err) }
            usleep(150_000)
            return FramedSocketServer.attemptConnect(to: socket)
        }
    }

    /// Maps a connect errno (+ optional App Group "wanted" flag) to an actionable failure.
    public static func unavailableResponse(errno err: Int32, socket: String? = nil,
                                           bridgeWanted: Bool? = nil) -> CLIResponse {
        let wanted = bridgeWanted ?? {
            let defaults = sharedDefaults
            guard defaults.object(forKey: BridgeStatus.wantedKey) != nil else { return nil }
            return defaults.bool(forKey: BridgeStatus.wantedKey)
        }()
        let response: CLIResponse
        if err == ECONNREFUSED || wanted == true {
            response = .failure(
                "Triwarden isn't running — open Triwarden to use the browser extension.",
                code: "app_not_running")
        } else if wanted == false {
            response = .failure(
                "This connection is turned off in Settings › Browser or Developer.",
                code: "connection_disabled")
        } else {
            // Flag never written (fresh install / older build): prefer the actionable "open the app" path.
            response = .failure(
                "Triwarden isn't running — open Triwarden to use the browser extension.",
                code: "app_not_running")
        }
        let path = socket ?? "(default)"
        log.error("bridge connect failed path=\(path, privacy: .public) errno=\(err) wanted=\(String(describing: wanted), privacy: .public) code=\(response.code ?? "-", privacy: .public)")
        return response
    }
}
