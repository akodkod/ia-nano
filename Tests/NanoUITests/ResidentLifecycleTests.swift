import XCTest
import AppKit
import NanoCore
import NanoIPC
@testable import IaNano

final class ResidentLifecycleTests: XCTestCase {
    func makeHost(terminate: @escaping () -> Void = {}) throws -> ApplicationDelegate {
        _ = NSApplication.shared
        let endpoint = try Endpoint(executable: "/tmp/lifecycle-\(UUID().uuidString)/ia-nano")
        let server = try ResidentServer(endpoint: endpoint, lock: XCTUnwrap(endpoint.acquireLock()))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: endpoint.directory) }
        return ApplicationDelegate(server: server, background: true, terminate: terminate)
    }

    func testQuitSavesOtherFilesButConflictPreventsTermination() throws {
        var terminated = false
        let host = try makeHost { terminated = true }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let conflict = root.appendingPathComponent("conflict"), saved = root.appendingPathComponent("saved")
        try Data("before".utf8).write(to: conflict)
        host.open(id: "conflict", path: conflict.path, data: Data(), connection: nil)
        host.open(id: "saved", path: saved.path, data: Data(), connection: nil)
        host.sessions["conflict"]?.editor.editor.string = "recover me"
        host.sessions["saved"]?.editor.editor.string = "saved text"
        try Data("external".utf8).write(to: conflict)
        _ = host.applicationShouldTerminate(NSApp)
        XCTAssertFalse(terminated)
        XCTAssertEqual(Set(host.sessions.keys), ["conflict"])
        XCTAssertEqual(host.sessions["conflict"]?.editor.editor.string, "recover me")
        XCTAssertEqual(try String(contentsOf: saved), "saved text")
        let editor = host.sessions["conflict"]!.editor
        if let sheet = editor.window?.attachedSheet { editor.window?.endSheet(sheet) }
        editor.completeSession(1)
        XCTAssertTrue(host.sessions.isEmpty)
        XCTAssertFalse(terminated)
    }

    func testQuitWaitsForOutputAcknowledgment() throws {
        var terminated = false
        let host = try makeHost { terminated = true }
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let server = try Connection(fds[0]), client = try Connection(fds[1])
        host.open(id: "output", path: nil, data: Data("output".utf8), connection: server)
        XCTAssertEqual(try client.receive().kind, "ready")
        _ = host.applicationShouldTerminate(NSApp)
        XCTAssertFalse(terminated)
        XCTAssertEqual(try client.receive().data, Data("output".utf8))
        XCTAssertEqual(try client.receive().kind, "outputEnd")
        host.acknowledge("output", success: true)
        XCTAssertEqual(try client.receive().code, 0)
        XCTAssertTrue(terminated)
        XCTAssertTrue(host.sessions.isEmpty)
    }

    func testFailedAcknowledgmentPreventsQuitAndRetainsText() throws {
        var terminated = false
        let host = try makeHost { terminated = true }
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let server = try Connection(fds[0]), client = try Connection(fds[1])
        host.open(id: "output", path: nil, data: Data("recover".utf8), connection: server)
        _ = try client.receive()
        _ = host.applicationShouldTerminate(NSApp)
        _ = try client.receive(); _ = try client.receive()
        host.acknowledge("output", success: false)
        XCTAssertFalse(terminated)
        XCTAssertEqual(host.sessions["output"]?.editor.editor.string, "recover")
        XCTAssertTrue(host.sessions["output"]!.editor.editor.isEditable)
        host.sessions["output"]?.editor.completeSession(1)
    }

    func testReleaseWarmBenchmark() throws {
        guard ProcessInfo.processInfo.environment["IA_NANO_BENCHMARK"] == "1" else {
            throw XCTSkip("Run IA_NANO_BENCHMARK=1 swift test -c release --filter testReleaseWarmBenchmark")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nano-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dist/iA Nano.app/Contents/MacOS")
        for name in ["ia-nano", "ia-nano-gui"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: root.appendingPathComponent(name))
        }
        let endpoint = try Endpoint(executable: root.appendingPathComponent("ia-nano").path)
        defer { try? FileManager.default.removeItem(atPath: endpoint.directory) }
        let host = ApplicationDelegate(server: try ResidentServer(endpoint: endpoint, lock: XCTUnwrap(endpoint.acquireLock())), background: true)
        _ = NSApplication.shared
        host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        var timings: [Double] = []
        for index in 0..<31 {
            let process = Process(), output = Pipe(), error = Pipe()
            process.executableURL = root.appendingPathComponent("ia-nano")
            process.environment = ProcessInfo.processInfo.environment.merging(["IA_NANO_METRICS": "1"]) { _, new in new }
            process.standardOutput = output; process.standardError = error
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {
                for session in Array(host.sessions.values) { session.editor.finish() }
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
            if process.isRunning { process.terminate(); XCTFail("Client did not finish"); return }
            XCTAssertEqual(process.terminationStatus, 0)
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let words = message.components(separatedBy: " ")
            let ms = try XCTUnwrap(words.firstIndex(of: "in").flatMap { Double(words[$0 + 1]) })
            if index > 0 { timings.append(ms) }
            XCTAssertTrue(host.sessions.isEmpty)
        }
        let sorted = timings.sorted()
        print("RESIDENT_BENCHMARK n=30 median=\((sorted[14]+sorted[15])/2)ms p95=\(sorted[28])ms samples=\(timings)")
    }
}
