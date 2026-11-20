import Foundation
import CryptoKit
import Darwin

public struct Packet: Codable {
    public var version: Int = 1
    public var kind: String
    public var id: String
    public var path: String?
    public var data: Data?
    public var code: Int32?
    public var message: String?
    public init(_ kind: String, id: String = "", path: String? = nil, data: Data? = nil,
                code: Int32? = nil, message: String? = nil) {
        self.kind = kind; self.id = id; self.path = path; self.data = data
        self.code = code; self.message = message
    }
}

public final class Connection {
    public let fd: Int32
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var stopped = false
    public init(_ fd: Int32) throws {
        self.fd = fd
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
            Darwin.close(fd)
            throw NanoError.message("Socket peer is not the current user.")
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
    }
    deinit { Darwin.close(fd) }
    public func shutdown() {
        stateLock.lock(); stopped = true; stateLock.unlock()
        Darwin.shutdown(fd, SHUT_RDWR)
    }
    public func timeout(_ seconds: Int) {
        var value = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
    }
    public func send(_ packet: Packet) throws {
        stateLock.lock(); let isStopped = stopped; stateLock.unlock()
        guard !isStopped else { throw NanoError.message("Connection is closed.") }
        let data = try JSONEncoder().encode(packet)
        guard data.count <= 128 * 1024 else { throw NanoError.message("IPC frame is too large.") }
        var size = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }; frame.append(data)
        writeLock.lock(); defer { writeLock.unlock() }
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw NanoError.message("Connection lost while sending to iA Nano.") }
                offset += count
            }
        }
    }
    public func sendData(_ data: Data, id: String) throws {
        for start in stride(from: 0, to: data.count, by: 48 * 1024) {
            try send(Packet("chunk", id: id, data: data.subdata(in: start..<min(start + 48 * 1024, data.count))))
        }
    }
    private func read(_ length: Int) throws -> Data {
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < length {
                let count = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), length - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw NanoError.message("iA Nano disconnected or stopped responding; the request was not replayed.") }
                offset += count
            }
        }
        return data
    }
    public func receive() throws -> Packet {
        let header = try read(4)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 128 * 1024 else { throw NanoError.message("Invalid IPC frame length.") }
        return try JSONDecoder().decode(Packet.self, from: read(Int(size)))
    }
}

public struct Endpoint {
    public let directory: String
    public var socketPath: String { directory + "/socket" }
    public let gui: URL
    public var build: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: gui.path)
        return "\(attrs?[.systemFileNumber] ?? 0)-\(attrs?[.size] ?? 0)-\(attrs?[.modificationDate] ?? Date.distantPast)"
    }
    public init(executable: String = CommandLine.arguments[0]) throws {
        let executableURL = URL(fileURLWithPath: executable).standardizedFileURL.resolvingSymlinksInPath()
        let parent = executableURL.deletingLastPathComponent()
        gui = parent.appendingPathComponent("ia-nano-gui")
        let digest = SHA256.hash(data: Data(parent.path.utf8)).map { String(format: "%02x", $0) }.joined()
        directory = "/tmp/ia-nano-\(getuid())-\(digest.prefix(32))"
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw NanoError.message("Cannot create private IPC directory.") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            throw NanoError.message("Unsafe IPC directory: \(directory)")
        }
    }
    private func address<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw NanoError.message("Socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    public func connect() throws -> Connection? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NanoError.message("Cannot create IPC socket.") }
        let result = try address { Darwin.connect(fd, $0, $1) }
        if result != 0 {
            let error = errno; Darwin.close(fd)
            if error == ENOENT || error == ECONNREFUSED { return nil }
            throw NanoError.message("Cannot connect to iA Nano: \(String(cString: strerror(error)))")
        }
        return try Connection(fd)
    }
    public func listen() throws -> Int32 {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NanoError.message("Cannot create server socket.") }
        guard try address({ Darwin.bind(fd, $0, $1) }) == 0, Darwin.listen(fd, 128) == 0 else {
            Darwin.close(fd); throw NanoError.message("Cannot listen on IPC socket.")
        }
        return fd
    }
    public func acquireLock() throws -> Int32? {
        let fd = open(directory + "/host.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NanoError.message("Cannot open host lock.") }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        let error = errno; Darwin.close(fd)
        if error == EWOULDBLOCK { return nil }
        throw NanoError.message("Cannot lock host endpoint.")
    }
}
