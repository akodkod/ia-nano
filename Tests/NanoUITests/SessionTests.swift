import XCTest
import AppKit
import NanoCore
@testable import IaNano

final class SessionTests: XCTestCase {
    func testOutputRemainsOpenUntilAcknowledgedAndCanRecover() throws {
        _ = NSApplication.shared
        var exits: [Int32] = [], delivered: [Data] = []
        weak var released: EditorController?
        try autoreleasepool {
        var controller: EditorController? = EditorController(buffer: try TextDocument(data: Data("hello 🦊\r\n".utf8)), highlighter: try SyntaxHighlighter()) { exits.append($0) }
        released = controller
        controller?.deliverOutput = { delivered.append($0) }
        controller?.finish()
        XCTAssertEqual(delivered, [Data("hello 🦊\r\n".utf8)])
        XCTAssertTrue(exits.isEmpty)
        XCTAssertFalse(controller!.editor.isEditable)
        controller?.finish()
        XCTAssertEqual(delivered.count, 1)
        controller?.deliveryFailed()
        XCTAssertTrue(controller!.editor.isEditable)
        XCTAssertEqual(controller!.editor.string, "hello 🦊\n")
        controller?.completeSession(1)
        XCTAssertEqual(exits, [1])
        controller = nil
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertNil(released)
    }

    func testDisconnectedBufferRecoversThroughSaveAs() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var exit: Int32?
        let editor = EditorController(buffer: try TextDocument(data: Data("recover 🦊\r\n".utf8)), highlighter: try SyntaxHighlighter()) { exit = $0 }
        editor.markDisconnected()
        try editor.saveAs(to: url)
        editor.finish()
        XCTAssertEqual(exit, 0)
        XCTAssertEqual(try Data(contentsOf: url), Data("recover 🦊\r\n".utf8))
    }

    func testFileAndOutputSessionsFinishIndependently() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var fileExit: Int32?, pipeExit: Int32?
        let file = EditorController(buffer: try TextDocument.open(path: url.path), highlighter: try SyntaxHighlighter()) { fileExit = $0 }
        let pipe = EditorController(buffer: try TextDocument(data: Data()), highlighter: try SyntaxHighlighter()) { pipeExit = $0 }
        file.editor.string = "saved"
        file.finish()
        XCTAssertEqual(fileExit, 0)
        XCTAssertNil(pipeExit)
        XCTAssertEqual(try String(contentsOf: url), "saved")
        pipe.completeSession(1)
        XCTAssertEqual(pipeExit, 1)
    }

    func testSaveConflictRetainsEditorAndReportsFailure() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var finished = false, failed = false
        let editor = EditorController(buffer: try TextDocument.open(path: url.path), highlighter: try SyntaxHighlighter()) { _ in finished = true }
        editor.onFailure = { failed = true }
        editor.editor.string = "keep me"
        try Data("external".utf8).write(to: url)
        editor.finish()
        XCTAssertFalse(finished)
        XCTAssertTrue(failed)
        XCTAssertEqual(editor.editor.string, "keep me")
        XCTAssertEqual(try String(contentsOf: url), "external")
        if let sheet = editor.window?.attachedSheet { editor.window?.endSheet(sheet) }
        editor.completeSession(1)
    }
}
