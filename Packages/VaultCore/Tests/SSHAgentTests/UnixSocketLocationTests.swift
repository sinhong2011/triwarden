import Darwin
import Foundation
import Testing
@testable import SSHAgent

struct UnixSocketLocationTests {
    private var groupPrefix: Int {
        "/Users/".utf8.count
            + "/Library/Group Containers/\(UnixSocketLocation.appGroupID)/".utf8.count
    }

    @Test func darwinSunPathCapacityIs104Bytes() {
        #expect(UnixSocketLocation.sunPathCapacity == 104)
        #expect(MemoryLayout.size(ofValue: sockaddr_un().sun_path) == 104)
    }

    @Test func classicGroupContainerPathFailsAt104Bytes() {
        // Fixed prefix + "cli.sock" is 84 bytes; a 20-character account name reaches the limit.
        let borderline = UnixSocketLocation.classicGroupContainerPath(accountName: String(repeating: "a", count: 20), kind: .cli)
        #expect(borderline.utf8.count == 104)
        #expect(!UnixSocketLocation.fits(borderline))

        let email = "john.smith@icloud.com" // 21 characters, the shape reported in issue #254
        let cli = UnixSocketLocation.classicGroupContainerPath(accountName: email, kind: .cli)
        let run = UnixSocketLocation.classicGroupContainerPath(accountName: email, kind: .run)
        let agent = UnixSocketLocation.classicGroupContainerPath(accountName: email, kind: .agent)
        #expect(cli.utf8.count == groupPrefix + email.utf8.count + "cli.sock".utf8.count)
        #expect(cli.utf8.count > 104)
        #expect(!UnixSocketLocation.fits(cli))
        #expect(!UnixSocketLocation.fits(run))
        #expect(!UnixSocketLocation.fits(agent))

        // autotype.sock is longer, so it fails even earlier (16-character names would already fail).
        let autoAt16 = UnixSocketLocation.classicGroupContainerPath(accountName: String(repeating: "b", count: 16), kind: .autotype)
        #expect(!UnixSocketLocation.fits(autoAt16))
        #expect(autoAt16.utf8.count == 104 || autoAt16.utf8.count > 104)
    }

    @Test func classicShortAccountNameStillFits() {
        let name = "niskan516"
        let cli = UnixSocketLocation.classicGroupContainerPath(accountName: name, kind: .cli)
        let agent = UnixSocketLocation.classicGroupContainerPath(accountName: name, kind: .agent)
        let auto = UnixSocketLocation.classicGroupContainerPath(accountName: name, kind: .autotype)
        #expect(cli.utf8.count == 93)
        #expect(UnixSocketLocation.fits(cli))
        #expect(UnixSocketLocation.fits(agent))
        #expect(UnixSocketLocation.fits(auto))
        #expect(UnixSocketLocation.fits(
            UnixSocketLocation.classicGroupContainerPath(accountName: name, kind: .run)))
    }

    @Test func longClassicPathIsRejectedByBind() {
        let path = UnixSocketLocation.classicGroupContainerPath(
            accountName: "john.smith.longname@icloud.com", kind: .cli)
        #expect(path.utf8.count > 104)
        let server = FramedSocketServer(socketURL: URL(fileURLWithPath: path)) { data, _ in data }
        do {
            try server.start()
            server.stop()
            Issue.record("bind should have failed for a \(path.utf8.count)-byte path")
        } catch FramedSocketServer.Failure.pathTooLong {
            // Expected: the length check runs before bind, so no file is created.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func shortPathWorksWithALongEmailStyleAccountName() throws {
        try withIsolatedRoots { roots in
            let longClassic = UnixSocketLocation.classicGroupContainerPath(
                accountName: "john.smith.longname@icloud.com", kind: .cli)
            #expect(longClassic.utf8.count > 104)
            #expect(!UnixSocketLocation.fits(longClassic))

            var planned: [String] = []
            for kind in UnixSocketLocation.Kind.allCases {
                let path = try UnixSocketLocation.prepareBindPath(kind: kind, roots: roots)
                planned.append(path)
                #expect(UnixSocketLocation.fits(path))
                #expect(path.utf8.count < 80, "short socket should stay well under the 104-byte limit, was \(path.utf8.count)")
                #expect(path.hasPrefix(roots.temporary.path))
                #expect(path.hasSuffix("/\(kind.rawValue)"))
            }
            // One directory for every socket, stable across calls.
            let directories = Set(planned.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
            #expect(directories.count == 1)
            #expect(try UnixSocketLocation.prepareBindPath(kind: .cli, roots: roots) == planned[0])

            let path = planned[0]
            let server = FramedSocketServer(socketURL: URL(fileURLWithPath: path)) { data, _ in data }
            try server.start()
            defer { server.stop() }
            try UnixSocketLocation.publish(kind: .cli, socketPath: path, roots: roots)

            let connected = UnixSocketLocation.connectPath(kind: .cli, roots: roots)
            #expect(connected == path)
            switch FramedSocketServer.attemptConnect(to: connected) {
            case .connected(let fd):
                close(fd)
            case .failed(let err):
                Issue.record("connect to short socket failed, errno \(err)")
            }

            // Compatibility symlink: a short classic path still reaches the same socket.
            let classic = UnixSocketLocation.classicPath(kind: .cli, container: roots.container)
            #expect(UnixSocketLocation.fits(classic))
            var info = stat()
            #expect(lstat(classic, &info) == 0)
            #expect((info.st_mode & S_IFMT) == S_IFLNK)
            switch FramedSocketServer.attemptConnect(to: classic) {
            case .connected(let fd):
                close(fd)
            case .failed(let err):
                Issue.record("connect via compatibility symlink failed, errno \(err)")
            }
        }
    }

    @Test func connectPathFallsBackToClassicWhenNoPointerExists() throws {
        try withIsolatedRoots { roots in
            let expected = UnixSocketLocation.classicPath(kind: .agent, container: roots.container)
            #expect(UnixSocketLocation.connectPath(kind: .agent, roots: roots) == expected)
            #expect(UnixSocketLocation.readPointer(kind: .agent, roots: roots) == nil)
        }
    }

    @Test func publishDoesNotNeedASymlinkWhenClassicPathDoesNotFit() throws {
        try withIsolatedRoots { roots in
            // A container path long enough that classic cli.sock itself would miss sun_path.
            let longName = "user-" + String(repeating: "x", count: 80)
            let longContainer = roots.container.appending(path: longName)
            let longRoots = UnixSocketLocation.Roots(container: longContainer, temporary: roots.temporary, uid: roots.uid)
            let classic = UnixSocketLocation.classicPath(kind: .cli, container: longContainer)
            #expect(!UnixSocketLocation.fits(classic))

            let path = try UnixSocketLocation.prepareBindPath(kind: .cli, roots: longRoots)
            #expect(UnixSocketLocation.fits(path))
            let server = FramedSocketServer(socketURL: URL(fileURLWithPath: path)) { data, _ in data }
            try server.start()
            defer { server.stop() }
            try UnixSocketLocation.publish(kind: .cli, socketPath: path, roots: longRoots)
            #expect(UnixSocketLocation.connectPath(kind: .cli, roots: longRoots) == path)
            #expect(!FileManager.default.fileExists(atPath: classic))
        }
    }

    private func withIsolatedRoots(_ body: (UnixSocketLocation.Roots) throws -> Void) throws {
        let fm = FileManager.default
        // Keep this path short: a UUID under /tmp already blows the 104-byte budget once
        // `tw-<uid>-<token>/cli.sock` is appended.
        let stamp = "t254-\(String(getpid(), radix: 16))-\(String(format: "%04x", UInt16.random(in: 0...UInt16.max)))"
        let base = URL(fileURLWithPath: "/tmp", isDirectory: true).appending(path: stamp, directoryHint: .isDirectory)
        // Short container so a compatibility symlink (when the classic path fits) can be exercised.
        // Long App Group paths are checked separately against sun_path; they are not used as the bind directory.
        let container = base.appending(path: "c", directoryHint: .isDirectory)
        let temporary = base.appending(path: "s", directoryHint: .isDirectory)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        let roots = UnixSocketLocation.Roots(container: container, temporary: temporary, uid: getuid())
        defer {
            UnixSocketLocation.Kind.allCases.forEach { UnixSocketLocation.unpublish(kind: $0, roots: roots) }
            try? fm.removeItem(at: base)
        }
        try body(roots)
    }
}
