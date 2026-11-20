import XCTest
@testable import NanoCore

final class NanoCoreTests: XCTestCase {
    func testArguments() throws {
        XCTAssertEqual(try Invocation.parse([]), .empty)
        XCTAssertEqual(try Invocation.parse(["-"]), .pipe)
        XCTAssertEqual(try Invocation.parse(["a b.md"]), .file("a b.md"))
        XCTAssertEqual(try Invocation.parse(["--", "-file"]), .file("-file"))
        XCTAssertEqual(try Invocation.parse(["--help"]), .help)
        XCTAssertThrowsError(try Invocation.parse(["a", "b"]))
        XCTAssertThrowsError(try Invocation.parse(["--unknown"]))
    }

    func testUTF8AndNewlines() throws {
        for value in ["", "hello", "hello\n", "Привіт 👩🏽‍💻\r\nline\r\n", "a\rb", "\u{feff}a\r\nb", "a\r\nb\nc"] {
            let document = try TextDocument(data: Data(value.utf8))
            XCTAssertEqual(document.encoded(document.text), Data(value.utf8))
        }
        let document = try TextDocument(data: Data("a\r\nb".utf8))
        XCTAssertEqual(String(decoding: document.encoded("a\nb\nc"), as: UTF8.self), "a\r\nb\r\nc")
        XCTAssertThrowsError(try TextDocument(data: Data([0xff, 0xfe])))
    }

    func testSaveSymlinkPermissionsAndConflict() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("prompt")
        let link = directory.appendingPathComponent("link")
        try Data("before\r\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        var document = try TextDocument.open(path: link.path)
        try document.save("after\n")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "after\r\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), file.path)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        try document.save("before\n")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "before\r\n")
        try Data("external".utf8).write(to: file)
        XCTAssertThrowsError(try document.save("overwrite"))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external")
    }

    func testNewFileAndInvalidPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = try TextDocument.open(path: directory.appendingPathComponent("new").path)
        try document.save("new text")
        XCTAssertEqual(try String(contentsOf: document.url!, encoding: .utf8), "new text")
        XCTAssertThrowsError(try TextDocument.open(path: directory.path))
        XCTAssertThrowsError(try TextDocument.open(path: directory.appendingPathComponent("missing/file").path))
        var failure = try TextDocument.open(path: directory.appendingPathComponent("failure").path)
        try FileManager.default.removeItem(at: directory)
        XCTAssertThrowsError(try failure.save("text"))
    }

    func testFencesAndUnicodeRanges() throws {
        let source = "👋 prose\n```ruby\nputs 'привіт'\n```\n\n```ts\nconst answer = 42;\n"
        let fences = Fence.scan(source)
        XCTAssertEqual(fences.count, 2)
        XCTAssertEqual((source as NSString).substring(with: fences[0].content), "puts 'привіт'\n")
        XCTAssertEqual(fences[1].language, "ts")
        let highlights = try SyntaxHighlighter().highlights(in: source)
        XCTAssertTrue(highlights.contains { $0.kind == .number && (source as NSString).substring(with: $0.range) == "42" })
        XCTAssertTrue(highlights.contains { $0.kind == .keyword && (source as NSString).substring(with: $0.range) == "const" })
        XCTAssertTrue(highlights.contains { $0.kind == .string && (source as NSString).substring(with: $0.range).contains("привіт") })
        XCTAssertTrue(highlights.allSatisfy { NSMaxRange($0.range) <= (source as NSString).length })
    }

    func testLongerFenceAndUnknownLanguages() throws {
        let source = "````ruby\n```\n42\n````\n```unknown\n42\n```\n"
        let fences = Fence.scan(source)
        XCTAssertEqual(fences.count, 2)
        XCTAssertEqual((source as NSString).substring(with: fences[0].content), "```\n42\n")
        let spans = try SyntaxHighlighter().highlights(in: "```unknown\n42\n```\n")
        XCTAssertTrue(spans.allSatisfy { $0.kind == .fence })
        XCTAssertTrue(Fence.scan("    ```ruby\n42").isEmpty)
    }
}
