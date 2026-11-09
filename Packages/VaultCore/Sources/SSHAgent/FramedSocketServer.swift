import Darwin
import Foundation

/// A Unix-socket server speaking length-prefixed frames (uint32 big-endian + body), one thread per
/// connection. The socket is `0600` and the peer's process is reported to the handler.
public final class FramedSocketServer: @unchecked Sendable {
    /// The process on the other end of the socket.
    public struct Peer: Sendable {
        public let pid: pid_t
        public let processName: String
        /// Full executable path, when the system reveals it.
        public let path: String?
        public init(pid: pid_t, processName: String, path: String?) { self.pid = pid; self.processName = processName; self.path = path }
    }

    public enum Failure: Error { case pathTooLong, socket(Int32) }

    public let socketURL: URL
    private let handler: @Sendable (Data, Peer) async -> Data
    private let maxFrame: Int
    private let lock = NSLock()
    private var listener: Int32 = -1

    public init(socketURL: URL, maxFrame: Int = 256 * 1024, handler: @escaping @Sendable (Data, Peer) async -> Data) {
        self.socketURL = socketURL
        self.maxFrame = maxFrame
        self.handler = handler
    }

    public var isRunning: Bool { lock.withLock { listener >= 0 } }

    public func start() throws {
        guard !isRunning else { return }
        let path = socketURL.path
        var addr = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.pathTooLong }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: path.utf8)
            buf[path.utf8.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            throw Failure.socket(err)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "socket accept"
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock { () -> Int32 in defer { listener = -1 }; return listener }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(socketURL.path)
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return // listener closed
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in
                self?.serve(client)
                close(client)
            }
            thread.name = "socket connection"
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        let peer = Self.peer(of: fd)
        while let request = Self.readFrame(fd, max: maxFrame) {
            let reply = blocking { await self.handler(request, peer) }
            guard Self.writeFrame(fd, reply) else { return }
        }
    }

    /// Runs async work from a connection thread (never a cooperative-pool thread).
    private func blocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        Task.detached { result = await work(); done.signal() }
        done.wait()
        return result!
    }

    // MARK: Framing (also used by clients)

    private static func readExactly(_ fd: Int32, _ n: Int) -> Data? {
        var out = Data(count: n)
        var got = 0
        while got < n {
            let k = out.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, n - got) }
            if k < 0, errno == EINTR { continue }
            guard k > 0 else { return nil }
            got += k
        }
        return out
    }

    public static func readFrame(_ fd: Int32, max: Int = 256 * 1024) -> Data? {
        guard let header = readExactly(fd, 4) else { return nil }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= max else { return nil }
        return readExactly(fd, length)
    }

    public static func writeFrame(_ fd: Int32, _ body: Data) -> Bool {
        let n = UInt32(body.count)
        let frame = Data([UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) + body
        var sent = 0
        while sent < frame.count {
            let k = frame.withUnsafeBytes { write(fd, $0.baseAddress! + sent, frame.count - sent) }
            if k < 0, errno == EINTR { continue }
            guard k > 0 else { return false }
            sent += k
        }
        return true
    }

    /// Outcome of a client connect: the open fd, or the Darwin errno (`ENOENT`, `ECONNREFUSED`, …).
    public enum ConnectOutcome: Sendable {
        case connected(Int32)
        case failed(errno: Int32)
    }

    /// Connects to a server socket (for clients such as the CLI). Returns the fd or nil.
    public static func connect(to path: String) -> Int32? {
        if case .connected(let fd) = attemptConnect(to: path) { return fd }
        return nil
    }

    /// Like `connect`, but returns the Darwin errno when the connection fails so callers can
    /// distinguish a missing socket (`ENOENT`) from a stale one (`ECONNREFUSED`).
    public static func attemptConnect(to path: String) -> ConnectOutcome {
        var addr = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { return .failed(errno: ENAMETOOLONG) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failed(errno: errno) }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: path.utf8)
            buf[path.utf8.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) } }
        guard ok == 0 else {
            let err = errno
            close(fd)
            return .failed(errno: err)
        }
        return .connected(fd)
    }

    static func peer(of fd: Int32) -> Peer {
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        return Peer(pid: pid, processName: path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "pid \(pid)", path: path)
    }
}
