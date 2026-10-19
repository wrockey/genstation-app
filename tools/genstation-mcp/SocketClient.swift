#if os(macOS)
// SocketClient.swift — genstation-mcp helper (WS-7)
//
// Connects to the GenStation app's Unix domain socket and exchanges
// line-delimited JSON requests/responses. Opens its exact containing app on demand
// and waits for the socket; it never chooses another installed copy by bundle ID.
//
// The helper holds no key material and performs no generation — it is a thin
// proxy between MCP stdio and the app.

import Foundation

enum SocketClientError: Error {
    case appUnreachable(String)
    case connectionLost(String)
}

final class SocketClient {
    /// An embedded demo helper has exactly one destination. It must never fall
    /// back to the shipping app, including when a socket override is present.
    static let enclosingApp: Bundle? = {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let app = executable.resolvingSymlinksInPath().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return nil }
        return Bundle(url: app)
    }()
    static var isDemo: Bool {
        #if GENSTATION_DEMO
        return true
        #else
        return enclosingApp?.bundleIdentifier == "art.genstation.demo"
        #endif
    }
    /// Identity of the containing app. A self-built copy signed under another
    /// developer's bundle ID uses that ID for its sandbox container.
    static var bundleID: String {
        if isDemo { return "art.genstation.demo" }
        if let identifier = enclosingApp?.bundleIdentifier, identifier != "art.genstation.demo" {
            return identifier
        }
        return "art.genstation.app"
    }
    /// Application Support directory holding the socket. Fixed regardless of
    /// bundle ID, matching `StorageContext.agentDirectory` in the app.
    static var storageID: String { isDemo ? "art.genstation.demo" : "art.genstation.app" }
    static let socketPathEnvVar = "GENSTATION_MCP_SOCKET"
    static let launchTimeout: TimeInterval = 30

    /// The shipped stdio mode runs in the app's own sandbox/container. Standalone
    /// protocol fixtures retain their explicit socket override and legacy paths.
    static var runsInApp: Bool {
        CommandLine.arguments.contains("--genstation-mcp")
            && Bundle.main.bundleIdentifier == bundleID
    }

    static var launchArguments: [String]? {
        guard let app = enclosingApp, app.bundleIdentifier == bundleID else { return nil }
        return [app.bundleURL.path]
    }

    private static let connectLock = NSLock()
    private var fd: Int32 = -1
    private var readBuffer = Data()
    private let responseTimeout: TimeInterval?
    init(responseTimeout: TimeInterval? = nil) { self.responseTimeout = responseTimeout }

    /// Candidate socket paths, most likely first. An env override (used by the
    /// smoke-test harness) replaces the list and disables app auto-launch.
    static func candidatePaths() -> [String] {
        if !isDemo, let override = ProcessInfo.processInfo.environment[socketPathEnvVar], !override.isEmpty {
            return [override]
        }
        if runsInApp {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
            return [support.appendingPathComponent(storageID).appendingPathComponent("mcp.sock").path]
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if isDemo {
            guard enclosingApp?.bundleIdentifier == "art.genstation.demo" else { return [] }
            return ["\(home)/Library/Containers/\(bundleID)/Data/Library/Application Support/\(storageID)/mcp.sock"]
        }
        return [
            // Sandboxed app container (the shipping configuration)
            "\(home)/Library/Containers/\(bundleID)/Data/Library/Application Support/\(storageID)/mcp.sock",
            // Non-sandboxed fallback
            "\(home)/Library/Application Support/\(storageID)/mcp.sock",
        ]
    }

    private static var launchAllowed: Bool {
        if isDemo { return enclosingApp?.bundleIdentifier == "art.genstation.demo" }
        return ProcessInfo.processInfo.environment[socketPathEnvVar] == nil
    }

    var isConnected: Bool { fd >= 0 }

    /// Ensures a live connection, launching the app and waiting for its socket
    /// if necessary. Throws SocketClientError.appUnreachable on failure.
    func ensureConnected() throws {
        if fd >= 0 { return }
        if let connected = Self.tryConnectAny() {
            fd = connected
            return
        }
        guard Self.launchAllowed else {
            throw SocketClientError.appUnreachable("GenStation socket is not available at \(Self.candidatePaths().joined(separator: " or ")).")
        }

        guard let arguments = Self.launchArguments else {
            throw SocketClientError.appUnreachable("Use the launcher embedded in GenStation.app; an extracted helper cannot launch the app.")
        }
        logErr("GenStation is not reachable — opening its exact containing app")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = arguments
        do {
            try open.run()
            open.waitUntilExit()
        } catch {
            throw SocketClientError.appUnreachable("Failed to launch GenStation: \(error.localizedDescription)")
        }
        if open.terminationStatus != 0 {
            throw SocketClientError.appUnreachable("Could not open the containing GenStation app (exit \(open.terminationStatus)). Open that exact app and enable Agent Access.")
        }

        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if let connected = Self.tryConnectAny() {
                fd = connected
                return
            }
            usleep(500_000)
        }
        throw SocketClientError.appUnreachable("GenStation launched but its MCP socket did not appear within \(Int(Self.launchTimeout))s. Check that agent access is enabled in the app's General Options.")
    }

    /// Sends one line-delimited JSON request and blocks for the one-line reply.
    /// The app serves this connection serially, so replies arrive in order.
    func roundTrip(_ request: [String: Any]) throws -> [String: Any] {
        try ensureConnected()
        if let responseTimeout {
            var timeout = timeval(tv_sec: Int(responseTimeout), tv_usec: Int32((responseTimeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        }
        var payload = try JSONSerialization.data(withJSONObject: request)
        payload.append(0x0A)

        try payload.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < payload.count {
                let written = write(fd, ptr.baseAddress!.advanced(by: offset), payload.count - offset)
                if written <= 0 {
                    disconnect()
                    throw SocketClientError.connectionLost("Write to GenStation failed (errno \(errno)).")
                }
                offset += written
            }
        }

        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer.subdata(in: readBuffer.startIndex..<newline)
                readBuffer.removeSubrange(readBuffer.startIndex...newline)
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw SocketClientError.connectionLost("GenStation sent an unparseable response.")
                }
                return object
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 {
                disconnect()
                throw SocketClientError.connectionLost("GenStation closed the connection.")
            }
            readBuffer.append(contentsOf: chunk[0..<n])
        }
    }

    func disconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        readBuffer.removeAll()
    }

    // MARK: Connect plumbing

    private static func tryConnectAny() -> Int32? {
        for path in candidatePaths() {
            if let fd = tryConnect(path: path) { return fd }
        }
        return nil
    }

    /// connect(2) to a Unix socket. macOS caps sockaddr_un.sun_path at 104
    /// bytes; the sandbox container path can exceed it, so long paths are
    /// handled by chdir-ing to the socket's directory and connecting to the
    /// bare filename (cwd restored afterwards — this process is single-purpose).
    private static func tryConnect(path: String) -> Int32? {
        // Concurrent wait clients share the process cwd; serialize the long-path
        // chdir/connect/restore sequence across every connection.
        connectLock.lock()
        defer { connectLock.unlock() }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // Prevent a write to a closed app socket from raising SIGPIPE (which would
        // kill the helper); write() returns EPIPE instead, handled as a lost
        // connection in roundTrip.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1

        var target = path
        var restoreCWD: String? = nil
        if path.utf8.count > maxLen {
            let dir = (path as NSString).deletingLastPathComponent
            restoreCWD = FileManager.default.currentDirectoryPath
            guard FileManager.default.changeCurrentDirectoryPath(dir) else {
                close(fd)
                return nil
            }
            target = (path as NSString).lastPathComponent
        }
        defer { if let cwd = restoreCWD { FileManager.default.changeCurrentDirectoryPath(cwd) } }

        let ok: Bool = target.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { raw in
                raw.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { dst in
                    _ = strncpy(dst, cs, maxLen)
                }
            }
            return withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
        }
        guard ok else {
            close(fd)
            return nil
        }
        return fd
    }
}

/// stderr logging (stdout is MCP protocol only).
func logErr(_ message: String) {
    FileHandle.standardError.write(Data("[genstation-mcp] \(message)\n".utf8))
}

#endif
