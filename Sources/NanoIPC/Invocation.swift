import Foundation

public enum NanoError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

public enum Invocation: Equatable {
    case file(String), pipe, empty, help, version, quitIfIdle

    public static func parse(_ arguments: [String]) throws -> Invocation {
        if arguments.isEmpty { return .empty }
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        if arguments == ["--quit-if-idle"] { return .quitIfIdle }
        if arguments == ["--version"] { return .version }
        if arguments == ["-"] { return .pipe }
        if arguments.count == 2, arguments[0] == "--" { return .file(arguments[1]) }
        guard arguments.count == 1, !arguments[0].hasPrefix("-") else {
            throw NanoError.message("Usage: ia-nano [FILE | - | --help | --version]")
        }
        return .file(arguments[0])
    }
}

