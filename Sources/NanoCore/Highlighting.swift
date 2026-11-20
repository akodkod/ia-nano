import Foundation
import SwiftTreeSitter
import TreeSitterRuby
import TreeSitterTypeScript

public struct Fence: Equatable {
    public let language: String
    public let content: NSRange
    public let markers: [NSRange]

    public static func scan(_ text: String) -> [Fence] {
        let source = text as NSString
        var result: [Fence] = []
        var open: (language: String, length: Int, start: Int, marker: NSRange)?
        var offset = 0
        while offset < source.length {
            let range = source.lineRange(for: NSRange(location: offset, length: 0))
            let line = source.substring(with: range).trimmingCharacters(in: .newlines)
            let trimmed = line.drop(while: { $0 == " " })
            let indentation = line.count - trimmed.count
            let ticks = trimmed.prefix(while: { $0 == "`" }).count
            if indentation <= 3, ticks >= 3 {
                let tail = trimmed.dropFirst(ticks).trimmingCharacters(in: .whitespaces)
                if let active = open {
                    if ticks >= active.length, tail.isEmpty {
                        result.append(Fence(language: active.language,
                            content: NSRange(location: active.start, length: range.location - active.start),
                            markers: [active.marker, range]))
                        open = nil
                    }
                } else if !tail.contains("`") {
                    open = (tail.components(separatedBy: .whitespaces).first?.lowercased() ?? "", ticks, NSMaxRange(range), range)
                }
            }
            offset = NSMaxRange(range)
        }
        if let active = open {
            result.append(Fence(language: active.language,
                content: NSRange(location: active.start, length: source.length - active.start), markers: [active.marker]))
        }
        return result
    }
}

public enum TokenKind: Sendable { case comment, string, number, keyword, type, function, fence }
public struct Highlight: Sendable {
    public let range: NSRange
    public let kind: TokenKind
}

public final class SyntaxHighlighter {
    private let ruby = Parser()
    private let typescript = Parser()

    public init() throws {
        try ruby.setLanguage(tree_sitter_ruby())
        try typescript.setLanguage(tree_sitter_typescript())
    }

    public func highlights(in text: String) -> [Highlight] {
        let source = text as NSString
        var result: [Highlight] = []
        for fence in Fence.scan(text) {
            result += fence.markers.map { Highlight(range: $0, kind: .fence) }
            let parser: Parser
            switch fence.language {
            case "ruby", "rb": parser = ruby
            case "ts", "typescript": parser = typescript
            default: continue
            }
            guard let root = parser.parse(source.substring(with: fence.content))?.rootNode else { continue }
            var pending = [root]
            while let node = pending.popLast() {
                let type = node.nodeType ?? ""
                let kind: TokenKind?
                if type.contains("comment") { kind = .comment }
                else if ["string", "string_content", "string_fragment", "template_string", "regex", "simple_symbol", "delimited_symbol"].contains(type) { kind = .string }
                else if node.isNamed, ["integer", "float", "number"].contains(type) { kind = .number }
                else if ["constant", "type_identifier", "predefined_type"].contains(type) { kind = .type }
                else if Self.keywords.contains(type) { kind = .keyword }
                else if type == "identifier", let parent = node.parent,
                    ["method", "singleton_method", "function_declaration", "call_expression", "call"].contains(parent.nodeType ?? ""),
                    (parent.child(byFieldName: "name") == node || parent.child(byFieldName: "function") == node || parent.child(byFieldName: "method") == node) { kind = .function }
                else { kind = nil }
                if let kind {
                    // Tree-sitter's Swift parser consumes UTF-16 bytes; AppKit uses code units.
                    let start = Int(node.byteRange.lowerBound) / 2
                    let end = Int(node.byteRange.upperBound) / 2
                    result.append(Highlight(range: NSRange(location: fence.content.location + start, length: end - start), kind: kind))
                }
                for index in (0..<node.childCount).reversed() {
                    if let child = node.child(at: index) { pending.append(child) }
                }
            }
        }
        return result
    }

    private static let keywords: Set<String> = [
        "def", "end", "class", "module", "if", "else", "elsif", "unless", "then", "do", "while", "until", "for", "in",
        "return", "yield", "super", "self", "nil", "true", "false", "begin", "rescue", "ensure", "raise", "require",
        "const", "let", "var", "function", "async", "await", "new", "export", "import", "from", "default", "interface",
        "type", "extends", "implements", "public", "private", "protected", "readonly", "static", "this", "null",
        "undefined", "throw", "try", "catch", "finally", "switch", "case", "break", "continue", "of", "typeof", "as"
    ]
}
