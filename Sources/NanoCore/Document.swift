import Foundation
@_exported import NanoIPC

public struct TextDocument {
    public let url: URL?
    public let text: String
    private let newline: String
    private let hasBOM: Bool
    private var originalData: Data?
    private let initialText: String

    public init(data: Data, url: URL? = nil, exists: Bool = true) throws {
        guard var decoded = String(data: data, encoding: .utf8) else {
            throw NanoError.message("iA Nano only supports valid UTF-8 text.")
        }
        hasBOM = decoded.hasPrefix("\u{feff}")
        if hasBOM { decoded.removeFirst() }
        newline = decoded.contains("\r\n") ? "\r\n" : (decoded.contains("\r") ? "\r" : "\n")
        text = Self.normalize(decoded)
        initialText = text
        self.url = url
        originalData = exists ? data : nil
    }

    public static func open(path: String) throws -> TextDocument {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        guard !directory.boolValue else { throw NanoError.message("Cannot edit a directory: \(path)") }
        if !exists {
            var parentIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
                throw NanoError.message("The parent directory does not exist: \(path)")
            }
        }
        return try TextDocument(data: exists ? Data(contentsOf: url) : Data(), url: url, exists: exists)
    }

    public static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public func encoded(_ edited: String) -> Data {
        // An untouched document retains even mixed line endings byte-for-byte.
        if edited == initialText, let originalData,
           (try? TextDocument(data: originalData).text) == initialText { return originalData }
        let output = (hasBOM ? "\u{feff}" : "") + Self.normalize(edited).replacingOccurrences(of: "\n", with: newline)
        return Data(output.utf8)
    }

    public mutating func save(_ edited: String) throws {
        guard let url else { return }
        let exists = FileManager.default.fileExists(atPath: url.path)
        let currentData = exists ? try Data(contentsOf: url) : nil
        guard currentData == originalData else {
            throw NanoError.message("The file changed outside iA Nano. Your text is still here; copy it before resolving the conflict.")
        }
        let output = encoded(edited)
        if currentData == output { return }
        if exists, !FileManager.default.isWritableFile(atPath: url.path) {
            throw NanoError.message("The file is read-only: \(url.path)")
        }
        let attributes = exists ? try FileManager.default.attributesOfItem(atPath: url.path) : [:]
        try output.write(to: url, options: .atomic)
        if let permissions = attributes[.posixPermissions] {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        originalData = output
    }
}
