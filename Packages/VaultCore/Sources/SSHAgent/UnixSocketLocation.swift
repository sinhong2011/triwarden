import Darwin
import Foundation

/// Unix-domain sockets on macOS must fit in `sockaddr_un.sun_path` (104 bytes, including the
/// trailing NUL, so the path itself must be shorter than 104). The App Group container path is
/// already 84 bytes plus the account name, so an email-style macOS user name makes `cli.sock`,
/// `run.sock` or `agent.sock` unbindable, and `autotype.sock` fails even sooner.
///
/// Sockets therefore live in a uid-owned `0700` directory under `/tmp`, with a stable
/// unpredictable suffix stored in the App Group. The concrete path is also written to a
/// pointer file there (regular files are limited by `PATH_MAX`, not `sun_path`) so the app,
/// `tw` and the Safari appex all agree. Coordination files (SSH logs, allowlists, Secrets
/// profiles) stay in the App Group.
public enum UnixSocketLocation: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case cli = "cli.sock"
        case agent = "agent.sock"
        case run = "run.sock"
        case autotype = "autotype.sock"

        public var pointerName: String { rawValue + ".path" }
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case pathTooLong
        case unsafeDirectory
        case io(Int32)

        public var errorDescription: String? {
            switch self {
            case .pathTooLong: return UnixSocketLocation.pathTooLongMessage
            case .unsafeDirectory: return "Couldn't create a private directory for the Unix socket."
            case .io(let err): return "Couldn't prepare the Unix socket (errno \(err))."
            }
        }
    }

    public static let appGroupID = "FX3VR69P5K.io.github.sinhong2011.triwarden"
    public static let tokenFileName = "socket-dir.id"
    /// Darwin `sun_path` capacity in bytes. The path passed to bind/connect must be strictly shorter.
    public static var sunPathCapacity: Int { MemoryLayout.size(ofValue: sockaddr_un().sun_path) }

    public static var pathTooLongMessage: String {
        "The Unix socket path is longer than macOS allows (\(sunPathCapacity) bytes). This happens with very long user names."
    }

    public static func fits(_ path: String) -> Bool {
        path.utf8.count < sunPathCapacity
    }

    /// Locations a server or client uses to agree on a socket. Tests inject a private container
    /// and temporary root so they never touch the running app's sockets.
    public struct Roots: Sendable {
        public var container: URL
        public var temporary: URL
        public var uid: uid_t

        public init(container: URL, temporary: URL, uid: uid_t) {
            self.container = container
            self.temporary = temporary
            self.uid = uid
        }
    }

    public static func defaultRoots() -> Roots {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Group Containers/\(appGroupID)")
        return Roots(container: container, temporary: URL(fileURLWithPath: "/tmp", isDirectory: true), uid: getuid())
    }

    /// Historic App Group path, for fallback when no pointer has been published (an older app)
    /// and for a compatibility symlink when the path still fits in `sun_path`.
    public static func classicPath(kind: Kind, container: URL) -> String {
        container.appending(path: kind.rawValue).path
    }

    /// The App Group path a given macOS account name would have produced, for tests and messages.
    public static func classicGroupContainerPath(accountName: String, kind: Kind) -> String {
        "/Users/\(accountName)/Library/Group Containers/\(appGroupID)/\(kind.rawValue)"
    }

    /// The short path this user should bind, without creating the `/tmp` directory yet.
    public static func plannedPath(kind: Kind, roots: Roots = defaultRoots()) throws -> String {
        let path = shortPath(kind: kind, roots: roots, token: try token(in: roots.container))
        guard fits(path) else { throw Failure.pathTooLong }
        return path
    }

    /// Creates the private `/tmp` directory if needed and returns the short socket path to bind.
    public static func prepareBindPath(kind: Kind, roots: Roots = defaultRoots()) throws -> String {
        let token = try token(in: roots.container)
        let directory = directoryURL(roots: roots, token: token)
        let path = directory.appending(path: kind.rawValue).path
        guard fits(path) else { throw Failure.pathTooLong }
        try ensurePrivateDirectory(directory, uid: roots.uid)
        return path
    }

    /// Path a client should connect to: the pointer file if it looks safe, otherwise the classic
    /// App Group path so an older app that still binds there keeps working.
    public static func connectPath(kind: Kind, roots: Roots = defaultRoots()) -> String {
        if let published = readPointer(kind: kind, roots: roots), isAcceptable(published, roots: roots) {
            return published
        }
        return classicPath(kind: kind, container: roots.container)
    }

    /// After a successful bind, record the path in the App Group and, when the classic path
    /// still fits in `sun_path`, leave a symlink so existing `SSH_AUTH_SOCK` values keep working.
    public static func publish(kind: Kind, socketPath: String, roots: Roots = defaultRoots()) throws {
        guard isAcceptable(socketPath, roots: roots) else { throw Failure.unsafeDirectory }
        try FileManager.default.createDirectory(at: roots.container, withIntermediateDirectories: true)
        try writeAtomically(Data(socketPath.utf8), to: roots.container.appending(path: kind.pointerName))
        let classic = classicPath(kind: kind, container: roots.container)
        guard fits(classic), classic != socketPath else { return }
        unlink(classic)
        guard symlink(socketPath, classic) == 0 else { throw Failure.io(errno) }
    }

    /// Drop the pointer and compatibility symlink. The server is expected to have unlinked the socket itself.
    public static func unpublish(kind: Kind, roots: Roots = defaultRoots()) {
        unlink(roots.container.appending(path: kind.pointerName).path)
        let classic = classicPath(kind: kind, container: roots.container)
        var info = stat()
        if lstat(classic, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
            unlink(classic)
        }
        if let token = try? readToken(in: roots.container) {
            rmdir(directoryURL(roots: roots, token: token).path)
        }
    }

    public static func readPointer(kind: Kind, roots: Roots = defaultRoots()) -> String? {
        let url = roots.container.appending(path: kind.pointerName)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == roots.uid, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= 1024 else { return nil }
        let data = readAll(fd, limit: 1024)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Whether this URL is one of the managed short sockets (so logs and key caches stay in the App Group).
    public static func isManaged(_ url: URL, roots: Roots = defaultRoots()) -> Bool {
        isAcceptable(url.path, roots: roots)
    }

    // MARK: - Internals

    private static func shortPath(kind: Kind, roots: Roots, token: String) -> String {
        directoryURL(roots: roots, token: token).appending(path: kind.rawValue).path
    }

    private static func directoryURL(roots: Roots, token: String) -> URL {
        roots.temporary.appending(path: "tw-\(roots.uid)-\(token)", directoryHint: .isDirectory)
    }

    private static func isAcceptable(_ path: String, roots: Roots) -> Bool {
        guard fits(path), path.hasPrefix("/"), !path.contains("\0") else { return false }
        let url = URL(fileURLWithPath: path)
        guard Kind(rawValue: url.lastPathComponent) != nil else { return false }
        let folder = url.deletingLastPathComponent().lastPathComponent
        let expected = "tw-\(roots.uid)-"
        guard folder.hasPrefix(expected), folder.count == expected.count + 32,
              folder.dropFirst(expected.count).unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789abcdef").contains($0)
              }) else { return false }
        let directory = url.deletingLastPathComponent().path
        return prefixes(for: roots).contains { base in
            let prefix = base.hasSuffix("/") ? String(base.dropLast()) : base
            return directory == prefix || directory.hasPrefix(prefix + "/")
        }
    }

    private static func prefixes(for roots: Roots) -> [String] {
        var list = [normalized(roots.temporary.path), "/tmp", "/private/tmp"]
        if list[0] == "/tmp" { list.append("/private/tmp") }
        return Array(Set(list))
    }

    private static func normalized(_ path: String) -> String {
        if path.count > 1, path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }

    private static func token(in container: URL) throws -> String {
        if let existing = try? readToken(in: container) { return existing }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 16)
        arc4random_buf(&bytes, bytes.count)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try writeAtomically(Data(token.utf8), to: container.appending(path: tokenFileName))
        return try readToken(in: container) ?? token
    }

    private static func readToken(in container: URL) throws -> String? {
        let url = container.appending(path: tokenFileName)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size == 32 else {
            throw Failure.unsafeDirectory
        }
        let text = String(data: readAll(fd, limit: 32), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.count == 32, text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
            throw Failure.unsafeDirectory
        }
        return text
    }

    private static func ensurePrivateDirectory(_ url: URL, uid: uid_t) throws {
        let path = url.path
        if mkdir(path, 0o700) != 0, errno != EEXIST { throw Failure.io(errno) }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw Failure.io(errno) }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == uid else { throw Failure.unsafeDirectory }
        if (info.st_mode & 0o777) != 0o700, chmod(path, 0o700) != 0 { throw Failure.io(errno) }
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.io(errno) }
        defer { close(fd); unlink(temporary.path) }
        let written: Int = data.withUnsafeBytes { raw in
            var sent = 0
            let base = raw.bindMemory(to: UInt8.self)
            while sent < data.count {
                let n = Darwin.write(fd, base.baseAddress! + sent, data.count - sent)
                if n < 0 { if errno == EINTR { continue }; return -1 }
                sent += n
            }
            return sent
        }
        guard written == data.count, fchmod(fd, 0o600) == 0, fsync(fd) == 0,
              rename(temporary.path, url.path) == 0 else {
            throw Failure.io(errno)
        }
    }

    private static func readAll(_ fd: Int32, limit: Int) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(limit, 256))
        while data.count < limit {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            data.append(contentsOf: buffer.prefix(n))
        }
        return data
    }
}
