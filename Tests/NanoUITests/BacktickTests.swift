import AppKit
import XCTest
@testable import IaNano

@MainActor
final class BacktickTests: XCTestCase {
    private func editor(_ text: String = "", selection: NSRange? = nil) -> EditorView {
        _ = NSApplication.shared
        let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        view.setSelectedRange(selection ?? NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    private func type(_ text: String, in view: EditorView) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func testInlinePairAndClosingSkip() {
        let view = editor()
        type("`", in: view)
        XCTAssertEqual(view.string, "``")
        XCTAssertEqual(view.selectedRange().location, 1)
        type("my word", in: view)
        type("`", in: view)
        XCTAssertEqual(view.string, "`my word`")
        XCTAssertEqual(view.selectedRange().location, 9)
    }

    func testThreeKeystrokesCreateFenceAndAllowLanguage() {
        let view = editor("  ")
        for _ in 0..<3 { type("`", in: view) }
        XCTAssertEqual(view.string, "  ```\n  ```")
        XCTAssertEqual(view.selectedRange().location, 5)
        type("ruby", in: view)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "  ```ruby\n  \n  ```")
        XCTAssertEqual(view.selectedRange().location, 12)
    }

    func testWrapUnicodeSelection() {
        let text = "👋 my word"
        let view = editor(text, selection: NSRange(location: 0, length: (text as NSString).length))
        type("`", in: view)
        XCTAssertEqual(view.string, "`" + text + "`")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: (text as NSString).length))
    }

    func testEscapedBacktickAndBulkInsertionStayLiteral() {
        let view = editor("\\")
        type("`", in: view)
        XCTAssertEqual(view.string, "\\`")
        let bulk = editor()
        type("```ruby\ncode\n```", in: bulk)
        XCTAssertEqual(bulk.string, "```ruby\ncode\n```")
    }

    func testClosingFenceDoesNotCreateAnotherFence() {
        let view = editor("```ruby\ncode\n")
        for _ in 0..<3 { type("`", in: view) }
        XCTAssertEqual(view.string, "```ruby\ncode\n```")
    }
}
