import CryptoKit
import Darwin
import Foundation
import Security
import Testing
@testable import SSHAgent

@Suite(.serialized) struct SSHAgentTests {
    static let dir = FileManager.default.temporaryDirectory.appending(path: "triwarden-agent-\(getpid())")
    static let keyTypes: [(String, [String])] = [
        ("ed25519", ["-t", "ed25519"]), ("ecdsa256", ["-t", "ecdsa", "-b", "256"]), ("ecdsa384", ["-t", "ecdsa", "-b", "384"]),
        ("ecdsa521", ["-t", "ecdsa", "-b", "521"]), ("rsa2048", ["-t", "rsa", "-b", "2048"]), ("rsa3072", ["-t", "rsa", "-b", "3072"]),
    ]

    @discardableResult
    static func run(_ tool: String, _ args: [String], env: [String: String] = [:], stdin: Data? = nil) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(filePath: tool.hasPrefix("/") ? tool : "/usr/bin/\(tool)")
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let out = Pipe(), input = Pipe()
        p.standardOutput = out; p.standardError = out; p.standardInput = input
        try p.run()
        if let stdin { input.fileHandleForWriting.write(stdin) }
        try input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func makeKey(_ name: String, _ args: [String]) throws -> (pem: String, pub: String, path: URL) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: name)
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: path.appendingPathExtension("pub"))
        try run("ssh-keygen", args + ["-q", "-N", "", "-C", "\(name)@test", "-f", path.path])
        return (try String(contentsOf: path, encoding: .utf8),
                try String(contentsOf: path.appendingPathExtension("pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), path)
    }

    @Test func bigMod() {
        #expect(BigMod.mod(Data([0x01, 0x00, 0x00]), Data([0x07])) == Data([0x02])) // 65536 mod 7
        #expect(BigMod.mod(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), Data([0x01, 0x00, 0x01])) == Data([0xff]))
        #expect(BigMod.minusOne(Data([0x01, 0x00])) == Data([0xFF]))
    }

    @Test func parsesEveryKeyType() throws {
        for (name, args) in Self.keyTypes {
            let k = try Self.makeKey(name, args)
            let key = try SSHPrivateKey(pem: k.pem)
            #expect(key.authorizedKey == k.pub, "\(name)")
        }
    }

    @Test func rejectsEncryptedKeys() throws {
        let k = try Self.makeKey("enc", ["-t", "ed25519"])
        try Self.run("ssh-keygen", ["-p", "-q", "-N", "secret", "-P", "", "-f", k.path.path])
        let pem = try String(contentsOf: k.path, encoding: .utf8)
        #expect(throws: SSHPrivateKey.Failure.encrypted) { try SSHPrivateKey(pem: pem) }
    }

    @Test func servesSshAddAndSignsForSshKeygen() async throws {
        let keys = try Self.keyTypes.map { name, args in
            let k = try Self.makeKey(name, args)
            return (SSHAgentServer.Identity(id: name, name: "\(name)@test", key: try SSHPrivateKey(pem: k.pem)), k)
        }
        let socket = Self.dir.appending(path: "agent.sock")
        let approvals = Approvals()
        let agent = SSHAgentServer(socketURL: socket, identities: { keys.map(\.0) },
                                   approve: { identity, peer in await approvals.record(identity.id, peer.processName) })
        try agent.start()
        defer { agent.stop() }
        let env = ["SSH_AUTH_SOCK": socket.path]

        let (status, listed) = try Self.run("ssh-add", ["-L"], env: env)
        #expect(status == 0)
        for (_, k) in keys { #expect(listed.contains(k.pub)) }

        let message = Data("tree 1234\nauthor usagi\n\nsigned commit\n".utf8)
        for (identity, k) in keys {
            let (signStatus, sigOutput) = try Self.run("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", k.path.path + ".pub", "-q"],
                                                       env: env, stdin: message)
            #expect(signStatus == 0, "\(identity.id): \(sigOutput)")
            let sigFile = Self.dir.appending(path: "\(identity.id).sig")
            try Data(sigOutput.utf8).write(to: sigFile)
            let signers = Self.dir.appending(path: "allowed_signers")
            try Data("usagi@test \(k.pub)\n".utf8).write(to: signers)
            let (verify, verifyOut) = try Self.run("ssh-keygen", ["-Y", "verify", "-n", "git", "-I", "usagi@test", "-f", signers.path,
                                                                  "-s", sigFile.path], stdin: message)
            #expect(verify == 0, "\(identity.id): \(verifyOut)")
        }
        let asked = await approvals.asked
        #expect(asked.count == keys.count && asked.allSatisfy { $0.1 == "ssh-keygen" })

        // Denied → the client gets a failure.
        await approvals.deny()
        let (denied, _) = try Self.run("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", keys[0].1.path.path + ".pub", "-q"],
                                       env: env, stdin: message)
        #expect(denied != 0)
    }

    /// Issue #251: the vault is locked. `ssh-add -L` still lists the remembered public key, and `ssh-keygen -Y sign`
    /// (git commit signing) waits while the app asks to unlock, then signs once the key is handed over.
    @Test func lockedVaultListsPublicKeysAndSignsAfterUnlock() async throws {
        let k = try Self.makeKey("lockedsign", ["-t", "ed25519"])
        let key = try SSHPrivateKey(pem: k.pem)
        let other = try SSHPrivateKey(pem: try Self.makeKey("lockedother", ["-t", "ed25519"]).pem)
        let listed = SSHPublicIdentity(id: "item-1", name: "GitHub", publicBlob: key.publicBlob, accountID: "acct")
        let socket = Self.dir.appending(path: "locked.sock")
        let unlock = SSHUnlockWait()
        let handOver = LockedVault()
        let agent = SSHAgentServer(socketURL: socket, list: { [listed] },
                                   authorize: { identity, _ in
                                       guard await unlock.wait() == .unlocked else { return nil }
                                       return await handOver.key(identity.id == "item-1" ? key : nil, wrong: other)
                                   })
        try agent.start()
        defer { agent.stop() }
        let env = ["SSH_AUTH_SOCK": socket.path]

        let (status, out) = try Self.run("ssh-add", ["-L"], env: env)
        #expect(status == 0 && out.contains(k.pub.split(separator: " ")[1]))

        let message = Data("signed while locked\n".utf8)
        func sign() async throws -> Int32 {
            try await Task.detached {
                try Self.run("ssh-keygen", ["-Y", "sign", "-n", "git", "-f", k.path.path + ".pub", "-q"], env: env, stdin: message).0
            }.value
        }
        func waitForWaiter() async throws {
            for _ in 0..<100 where await unlock.waiting == 0 { try await Task.sleep(for: .milliseconds(20)) }
            #expect(await unlock.waiting == 1)
        }

        async let unlocked = sign()
        try await waitForWaiter()
        await unlock.finish(.unlocked)
        let unlockedStatus = try await unlocked
        #expect(unlockedStatus == 0)

        async let cancelled = sign()
        try await waitForWaiter()
        await unlock.finish(.cancelled)
        let cancelledStatus = try await cancelled
        #expect(cancelledStatus != 0)

        // A different key handed back (the item was edited while waiting) never signs in its place.
        await handOver.handBackWrongKey()
        async let swapped = sign()
        try await waitForWaiter()
        await unlock.finish(.unlocked)
        let swappedStatus = try await swapped
        #expect(swappedStatus != 0)
    }

    // MARK: RSA SHA-2 flags, over the socket

    /// What `ssh` sends: SSH_AGENTC_SIGN_REQUEST with flags 2 (rsa-sha2-256), 4 (rsa-sha2-512) or none
    /// (legacy ssh-rsa). Each signature is checked with Security.framework against the public key from
    /// ssh-keygen's .pub file, not the agent's own key.
    @Test func signsRSAWithRequestedHash() async throws {
        let k = try Self.makeKey("rsaflags", ["-t", "rsa", "-b", "3072"])
        let key = try SSHPrivateKey(pem: k.pem)
        let ed = try Self.makeKey("edflags", ["-t", "ed25519"])
        let edKey = try SSHPrivateKey(pem: ed.pem)
        let approvals = Approvals()
        let agent = try Self.startAgent("flags.sock", [key, edKey], approvals)
        defer { agent.stop() }

        let blob = try #require(Data(base64Encoded: String(k.pub.split(separator: " ")[1])))
        let publicKey = try Self.rsaPublicKey(blob)
        let data = Data("session id + userauth request".utf8)
        let cases: [(UInt32?, String, SecKeyAlgorithm)] = [
            (2, "rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256),
            (4, "rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512),
            (0, "ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1),
            (nil, "ssh-rsa", .rsaSignatureMessagePKCS1v15SHA1), // flags field omitted entirely
        ]
        for (flags, expected, algorithm) in cases {
            let (name, sig) = try Self.agentSign(agent.socketURL, blob: blob, data: data, flags: flags)
            #expect(name == expected, "flags \(String(describing: flags))")
            var error: Unmanaged<CFError>?
            #expect(SecKeyVerifySignature(publicKey, algorithm, data as CFData, sig as CFData, &error), "\(expected)")
            #expect(!SecKeyVerifySignature(publicKey, algorithm, Data("tampered".utf8) as CFData, sig as CFData, nil))
        }

        // RSA flags mean nothing to Ed25519: still a plain ssh-ed25519 signature.
        let edBlob = edKey.publicBlob
        let (edName, edSig) = try Self.agentSign(agent.socketURL, blob: edBlob, data: data, flags: 4)
        #expect(edName == "ssh-ed25519")
        var r = SSHReader(edBlob)
        _ = try r.string()
        #expect(try Curve25519.Signing.PublicKey(rawRepresentation: r.string()).isValidSignature(edSig, for: data))

        // A key the agent doesn't hold → SSH_AGENT_FAILURE, and nobody is asked.
        let before = await approvals.asked.count
        let other = try Self.makeKey("rsaother", ["-t", "rsa", "-b", "2048"])
        let otherBlob = try #require(Data(base64Encoded: String(other.pub.split(separator: " ")[1])))
        #expect(try Self.agentRequest(agent.socketURL, Self.signRequest(blob: otherBlob, data: data, flags: 2)) == Data([5]))
        #expect(await approvals.asked.count == before)

        // Denied → SSH_AGENT_FAILURE.
        await approvals.deny()
        #expect(try Self.agentRequest(agent.socketURL, Self.signRequest(blob: blob, data: data, flags: 4)) == Data([5]))
    }

    // MARK: git commit -S, end to end

    static let hasGit = FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
        && (try? run("xcode-select", ["-p"]).0) == 0 // /usr/bin/git is only a shim without developer tools

    @Test(.enabled(if: hasGit, "git isn't installed")) func signsGitCommits() async throws {
        for (name, args) in [("git-ed25519", ["-t", "ed25519"]), ("git-rsa", ["-t", "rsa", "-b", "3072"])] {
            let k = try Self.makeKey(name, args)
            try FileManager.default.removeItem(at: k.path) // only the agent can sign
            let approvals = Approvals()
            let agent = try Self.startAgent("\(name).sock", [try SSHPrivateKey(pem: k.pem)], approvals)
            defer { agent.stop() }

            let repo = Self.dir.appending(path: "\(name)-repo")
            try? FileManager.default.removeItem(at: repo)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            let signers = Self.dir.appending(path: "\(name)-allowed_signers")
            try Data("usagi@test \(k.pub)\n".utf8).write(to: signers)
            // Keep the user's own git config (and any gpg.ssh.program it names) out of it.
            let env = ["SSH_AUTH_SOCK": agent.socketURL.path, "HOME": repo.path,
                       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
            func git(_ args: [String]) throws -> (Int32, String) { try Self.run("git", ["-C", repo.path] + args, env: env) }

            #expect(try git(["init", "-q"]).0 == 0)
            for (key, value) in [("user.name", "Usagi"), ("user.email", "usagi@test"), ("gpg.format", "ssh"),
                                 ("user.signingkey", k.path.path + ".pub"), ("gpg.ssh.allowedSignersFile", signers.path)] {
                #expect(try git(["config", key, value]).0 == 0)
            }
            try Data("hello\n".utf8).write(to: repo.appending(path: "README"))
            #expect(try git(["add", "README"]).0 == 0)
            let (commit, commitOut) = try git(["commit", "-q", "-S", "-m", "signed by the vault"])
            #expect(commit == 0, "\(name): \(commitOut)")
            let (verify, verifyOut) = try git(["verify-commit", "HEAD"])
            #expect(verify == 0, "\(name): \(verifyOut)")
            #expect(verifyOut.contains("Good \"git\" signature for usagi@test"), "\(name): \(verifyOut)")
            #expect(await approvals.asked.map(\.1) == ["ssh-keygen"])

            await approvals.deny()
            let (denied, deniedOut) = try git(["commit", "-q", "-S", "--allow-empty", "-m", "should not sign"])
            #expect(denied != 0, "\(name): \(deniedOut)")
            #expect(try git(["rev-list", "--count", "HEAD"]).1.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        }
    }

    // MARK: ssh login against a throwaway sshd

    static let hasSSHD = FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd")

    /// A real `ssh` login through the agent: an unprivileged sshd on a free loopback port, with its own
    /// host key and authorized_keys (`UsePAM no` and `StrictModes no` let it run without root).
    @Test(.enabled(if: hasSSHD, "sshd isn't installed")) func logsInWithSSH() async throws {
        let keys = try [("login-ed25519", ["-t", "ed25519"]), ("login-rsa", ["-t", "rsa", "-b", "3072"])].map { name, args in
            let k = try Self.makeKey(name, args)
            try FileManager.default.removeItem(at: k.path) // only the agent can sign
            return (name, k)
        }
        let host = try Self.makeKey("login-host", ["-t", "ed25519"])
        let authorized = Self.dir.appending(path: "authorized_keys")
        try Data(keys.map { $0.1.pub + "\n" }.joined().utf8).write(to: authorized)
        let port = try Self.freePort()
        let config = Self.dir.appending(path: "sshd_config")
        try Data("""
            Port \(port)
            ListenAddress 127.0.0.1
            HostKey \(host.path.path)
            AuthorizedKeysFile \(authorized.path)
            PidFile \(Self.dir.appending(path: "sshd.pid").path)
            UsePAM no
            StrictModes no
            PasswordAuthentication no
            KbdInteractiveAuthentication no

            """.utf8).write(to: config)
        let sshd = Process()
        sshd.executableURL = URL(filePath: "/usr/sbin/sshd")
        sshd.arguments = ["-D", "-e", "-f", config.path]
        sshd.standardError = FileHandle.nullDevice
        try sshd.run()
        defer { sshd.terminate(); sshd.waitUntilExit() }
        try Self.waitForPort(port)

        let approvals = Approvals()
        let agent = try Self.startAgent("login.sock", try keys.map { try SSHPrivateKey(pem: $0.1.pem) }, approvals)
        defer { agent.stop() }
        func ssh(_ pub: URL, _ extra: [String] = []) throws -> (Int32, String) {
            try Self.run("ssh", ["-F", "/dev/null", "-o", "IdentityAgent=\(agent.socketURL.path)", "-o", "IdentitiesOnly=yes",
                                 "-i", pub.path, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
                                 "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-p", "\(port)"]
                             + extra + ["\(NSUserName())@127.0.0.1", "echo logged-in"])
        }

        for (name, k) in keys {
            let pub = k.path.appendingPathExtension("pub")
            let (status, out) = try ssh(pub)
            #expect(status == 0 && out.contains("logged-in"), "\(name): \(out)")
        }
        // Force the older SHA-2 variant too (ssh defaults to rsa-sha2-512).
        let rsaPub = keys[1].1.path.appendingPathExtension("pub")
        let (sha256, sha256Out) = try ssh(rsaPub, ["-o", "PubkeyAcceptedAlgorithms=rsa-sha2-256"])
        #expect(sha256 == 0 && sha256Out.contains("logged-in"), "rsa-sha2-256: \(sha256Out)")
        #expect(await approvals.asked.map(\.0) == ["0", "1", "1"])
        #expect(await approvals.asked.allSatisfy { $0.1 == "ssh" })

        await approvals.deny()
        let (denied, deniedOut) = try ssh(keys[0].1.path.appendingPathExtension("pub"))
        #expect(denied != 0 && !deniedOut.contains("logged-in"))
    }

    // MARK: Helpers

    static func startAgent(_ socketName: String, _ keys: [SSHPrivateKey], _ approvals: Approvals) throws -> SSHAgentServer {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let identities = keys.enumerated().map { SSHAgentServer.Identity(id: "\($0)", name: $1.comment, key: $1) }
        let agent = SSHAgentServer(socketURL: dir.appending(path: socketName), identities: { identities },
                                   approve: { identity, peer in await approvals.record(identity.id, peer.processName) })
        try agent.start()
        return agent
    }

    static func signRequest(blob: Data, data: Data, flags: UInt32?) -> Data {
        var w = SSHWriter()
        w.uint8(SSHAgentServer.Message.signRequest)
        w.string(blob); w.string(data)
        if let flags { w.uint32(flags) }
        return w.data
    }

    /// Sends a sign request and returns the signature's algorithm name and raw bytes.
    static func agentSign(_ socket: URL, blob: Data, data: Data, flags: UInt32?) throws -> (String, Data) {
        var r = SSHReader(try agentRequest(socket, signRequest(blob: blob, data: data, flags: flags)))
        try #require(try r.uint8() == SSHAgentServer.Message.signResponse)
        var sig = SSHReader(try r.string())
        return (try sig.text(), try sig.string())
    }

    /// One framed request/response on the agent socket, as an ssh client would send it.
    static func agentRequest(_ socket: URL, _ body: Data) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: socket.path.utf8)
            buf[socket.path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(connected == 0)
        var w = SSHWriter()
        w.string(body)
        try #require(w.data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == w.data.count)
        func read(_ n: Int) throws -> Data {
            var out = Data()
            while out.count < n {
                var chunk = [UInt8](repeating: 0, count: n - out.count)
                let got = Darwin.read(fd, &chunk, chunk.count)
                try #require(got > 0)
                out.append(contentsOf: chunk.prefix(got))
            }
            return out
        }
        var header = SSHReader(try read(4))
        return try read(Int(try header.uint32()))
    }

    /// `ssh-rsa` public blob (string type, mpint e, mpint n) → SecKey.
    static func rsaPublicKey(_ blob: Data) throws -> SecKey {
        var r = SSHReader(blob)
        _ = try r.string()
        let e = try r.mpint(), n = try r.mpint()
        func der(_ tag: UInt8, _ content: Data) -> Data {
            let n = content.count
            let length = n < 0x80 ? Data([UInt8(n)])
                : { let l = withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) }.drop { $0 == 0 }; return Data([0x80 | UInt8(l.count)]) + l }()
            return Data([tag]) + length + content
        }
        func integer(_ m: Data) -> Data { der(0x02, m.first.map { $0 & 0x80 != 0 } == true ? Data([0]) + m : m) }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        return try #require(SecKeyCreateWithData(der(0x30, integer(n) + integer(e)) as CFData, attributes as CFDictionary, nil))
    }

    static func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &addr) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try #require(bind(fd, $0, size) == 0 && getsockname(fd, $0, &size) == 0)
            }
        }
        return UInt16(bigEndian: addr.sin_port)
    }

    static func waitForPort(_ port: UInt16) throws {
        for _ in 0..<100 {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            } == 0
            close(fd)
            if ok { return }
            usleep(50_000)
        }
        Issue.record("sshd never listened on \(port)")
    }
}

actor Approvals {
    private(set) var asked: [(String, String)] = []
    private var allow = true
    func record(_ id: String, _ process: String) -> Bool { asked.append((id, process)); return allow }
    func deny() { allow = false }
}

actor LockedVault {
    private var wrong = false
    func handBackWrongKey() { wrong = true }
    func key(_ right: SSHPrivateKey?, wrong other: SSHPrivateKey) -> SSHPrivateKey? { wrong ? other : right }
}
