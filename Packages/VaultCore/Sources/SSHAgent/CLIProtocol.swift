import Darwin
import Foundation

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
    /// `match`: also return each login's current one-time code. Only a code field asks for this.
    public var codes: Bool?
    /// `match` with `codes`: the person asked for them (clicked the icon, pressed the shortcut). A field that merely
    /// took focus does not set this, and gets no codes.
    public var reveal: Bool?
    /// Added by `tw` when a browser started it: that browser's extension origin (`chrome-extension://<id>/`) or, for
    /// Firefox, the add-on id. The app uses it to show which browsers are connected, since a sandboxed app cannot read
    /// their folders. The extension itself never sets it.
    public var origin: String?
    /// Added by `tw` the same way: the bundle id of the browser that started it (com.google.Chrome, ...), so the app
    /// can say which browser is connected.
    public var browser: String?

    public init(command: Command, query: String? = nil, field: String? = nil, length: Int? = nil,
                url: String? = nil, username: String? = nil, password: String? = nil, codes: Bool? = nil,
                reveal: Bool? = nil, origin: String? = nil, browser: String? = nil) {
        self.command = command; self.query = query; self.field = field; self.length = length
        self.url = url; self.username = username; self.password = password; self.codes = codes; self.reveal = reveal; self.origin = origin; self.browser = browser
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
    /// `match`: whether the Browser setting "Show suggestions when a field is focused" is on. The extension keeps it.
    public var autoShow: Bool?

    public static func success(_ value: String) -> CLIResponse { CLIResponse(ok: true, value: value) }
    public static func list(_ rows: [Row], autoShow: Bool? = nil) -> CLIResponse {
        CLIResponse(ok: true, rows: rows, autoShow: autoShow)
    }
    public static func failure(_ message: String) -> CLIResponse { CLIResponse(ok: false, error: message) }
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

/// One request/response to the running app (used by `tw`, the Chrome host and the Safari extension).
public enum BridgeClient {
    public static let appGroup = "FX3VR69P5K.io.github.sinhong2011.triwarden"

    /// `~/Library/Group Containers/<group>/cli.sock`, resolved for sandboxed and unsandboxed callers alike.
    public static var defaultSocketPath: String {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return container.appending(path: CLISocket.name).path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/\(appGroup)/\(CLISocket.name)").path
    }

    public static func send(_ request: CLIRequest, socket: String = defaultSocketPath) -> CLIResponse {
        guard let fd = FramedSocketServer.connect(to: socket) else {
            return .failure("Triwarden isn't running, or this connection is turned off in Settings › Browser or Developer.")
        }
        defer { close(fd) }
        guard let body = try? JSONEncoder().encode(request), FramedSocketServer.writeFrame(fd, body),
              let reply = FramedSocketServer.readFrame(fd, max: 8 * 1024 * 1024),
              let response = try? JSONDecoder().decode(CLIResponse.self, from: reply) else {
            return .failure("No answer from Triwarden.")
        }
        return response
    }
}
