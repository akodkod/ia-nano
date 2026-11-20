import XCTest
import Foundation
import Darwin
@testable import NanoIPC

final class TransportTests: XCTestCase {
    func pair() throws -> (Connection, Connection) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        return try (Connection(fds[0]), Connection(fds[1]))
    }
    func testUnicodeBinaryAndChunking() throws {
        let (writer, reader) = try pair()
        let bytes = Data((0..<200_000).map { UInt8($0 % 256) })
        let sent = expectation(description: "sent")
        DispatchQueue.global().async {
            defer { sent.fulfill() }
            do {
                try writer.send(Packet("open", id: "🦊", path: "/tmp/文字"))
                try writer.sendData(bytes, id: "🦊")
                try writer.send(Packet("end", id: "🦊"))
            } catch { XCTFail("\(error)") }
        }
        let first = try reader.receive()
        XCTAssertEqual(first.path, "/tmp/文字")
        var received = Data()
        while true {
            let packet = try reader.receive()
            XCTAssertEqual(packet.id, "🦊")
            if packet.kind == "end" { break }
            received.append(try XCTUnwrap(packet.data))
        }
        XCTAssertEqual(received, bytes)
        wait(for: [sent], timeout: 5)
    }
    func testTruncatedFrameAndDisconnect() throws {
        let (writer, reader) = try pair()
        let partial: [UInt8] = [0, 0, 0, 30, 123]
        _ = partial.withUnsafeBytes { Darwin.write(writer.fd, $0.baseAddress, $0.count) }
        writer.shutdown()
        XCTAssertThrowsError(try reader.receive())
        reader.shutdown()
        XCTAssertThrowsError(try reader.send(Packet("ack")))
    }
    func testRejectOversizedFrameBeforeAllocation() throws {
        let (writer, reader) = try pair()
        let header: [UInt8] = [255, 255, 255, 255]
        _ = header.withUnsafeBytes { Darwin.write(writer.fd, $0.baseAddress, $0.count) }
        XCTAssertThrowsError(try reader.receive())
    }
    func testFragmentedFrame() throws {
        let (writer, reader) = try pair()
        let data = try JSONEncoder().encode(Packet("ack", id: "request", code: 0))
        var size = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }; frame.append(data)
        let sent = expectation(description: "fragmented send")
        DispatchQueue.global().async {
            for byte in frame {
                var byte = byte
                _ = Darwin.write(writer.fd, &byte, 1)
            }
            sent.fulfill()
        }
        XCTAssertEqual(try reader.receive().kind, "ack")
        wait(for: [sent], timeout: 5)
    }
    func testEndpointIsolationLockAndStaleSocket() throws {
        let base = "/tmp/ia-test-\(UUID().uuidString)"
        let endpoint = try Endpoint(executable: base + "/ia-nano")
        let other = try Endpoint(executable: base + "-other/ia-nano")
        defer {
            try? FileManager.default.removeItem(atPath: endpoint.directory)
            try? FileManager.default.removeItem(atPath: other.directory)
        }
        XCTAssertNotEqual(endpoint.socketPath, other.socketPath)
        XCTAssertEqual(endpoint.socketPath, try Endpoint(executable: base + "/ia-nano-gui").socketPath)
        let lock = try XCTUnwrap(endpoint.acquireLock())
        XCTAssertNil(try endpoint.acquireLock())
        let fd = try endpoint.listen()
        Darwin.close(fd)
        XCTAssertNil(try endpoint.connect())
        let replacement = try endpoint.listen()
        Darwin.close(replacement)
        Darwin.close(lock)
        let newLock = try XCTUnwrap(endpoint.acquireLock())
        Darwin.close(newLock)
    }
    func testQuitInvocation() throws {
        XCTAssertEqual(try Invocation.parse(["--quit-if-idle"]), .quitIfIdle)
    }
}
