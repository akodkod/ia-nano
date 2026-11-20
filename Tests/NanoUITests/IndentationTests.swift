import AppKit
import XCTest
@testable import IaNano

@MainActor
final class IndentationTests: XCTestCase {
    private func editor(_ text: String, selection: NSRange? = nil) -> EditorView {
        _ = NSApplication.shared
        let view = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        view.setSelectedRange(selection ?? NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    func testTabInsertsTwoSpaces() {
        let view = editor("👋")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "👋  ")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testSelectedLinesIndentAndOutdent() {
        let text = "👋 first\nsecond\nthird"
        let selection = NSRange(location: 0, length: ("👋 first\nsecond\n" as NSString).length)
        let view = editor(text, selection: selection)
        view.insertTab(nil)
        XCTAssertEqual(view.string, "  👋 first\n  second\nthird")
        view.insertBacktab(nil)
        XCTAssertEqual(view.string, text)
        XCTAssertEqual(view.selectedRange(), selection)
    }

    func testOutdentHandlesShortIndentAndTabs() {
        for (before, after) in [("    hello", "  hello"), (" hello", "hello"), ("\thello", "hello"), ("hello", "hello"), ("", "")] {
            let view = editor(before)
            view.insertBacktab(nil)
            XCTAssertEqual(view.string, after)
            XCTAssertEqual(view.selectedRange().location, (after as NSString).length)
        }
    }

    func testNewlinePreservesCodeIndentationOnly() {
        for (before, suffix) in [("```ruby\n  puts 'hi'", "\n  "),
                                 ("```ts\n\tcall();", "\n  "),
                                 ("  prose", "\n"),
                                 ("```ruby\n  puts 'hi'\n```", "\n")] {
            let view = editor(before)
            view.insertNewline(nil)
            XCTAssertEqual(view.string, before + suffix)
        }
    }

    func testNewlineInsideClosedFenceAndSelectionReplacement() {
        let view = editor("```ruby\n  hello world\n```", selection: NSRange(location: 15, length: 7))
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "```ruby\n  hello\n  ```")
    }
}
