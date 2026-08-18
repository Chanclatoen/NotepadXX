import Foundation

/// Parsed command-line invocation, mirroring Notepad++'s switches.
///
/// Notepad++ accepts `notepad++ file.txt -n25 -c4` to open at a line and column.
/// The macOS equivalent also accepts the common `file.txt:25:4` form, because
/// that is what other Mac tooling emits and what users will paste from a
/// compiler error.
public struct CommandLineOptions: Equatable, Sendable {
    public struct FileRequest: Equatable, Sendable {
        public let path: String
        public let line: Int?
        public let column: Int?
        public init(path: String, line: Int? = nil, column: Int? = nil) {
            self.path = path
            self.line = line
            self.column = column
        }
    }

    public var files: [FileRequest] = []
    public var readOnly = false
    public var newInstance = false
    public var noSession = false
    public var screenshotPath: String?

    public init() {}

    /// Parses arguments, ignoring the executable path at index 0.
    public static func parse(_ arguments: [String]) -> CommandLineOptions {
        var options = CommandLineOptions()
        var pendingLine: Int?
        var pendingColumn: Int?
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            switch true {
            case argument == "-ro" || argument == "--read-only":
                options.readOnly = true
            case argument == "-multiInst" || argument == "--new-instance":
                options.newInstance = true
            case argument == "-nosession" || argument == "--no-session":
                options.noSession = true
            case argument == "--screenshot":
                if index < arguments.count {
                    options.screenshotPath = arguments[index]
                    index += 1
                }
            case argument.hasPrefix("-n"):
                pendingLine = Int(argument.dropFirst(2))
            case argument.hasPrefix("-c"):
                pendingColumn = Int(argument.dropFirst(2))
            case argument.hasPrefix("-"):
                break   // unknown switch: ignore rather than treat as a filename
            default:
                let (path, line, column) = splitLocation(argument)
                options.files.append(FileRequest(
                    path: path,
                    line: line ?? pendingLine,
                    column: column ?? pendingColumn
                ))
                pendingLine = nil
                pendingColumn = nil
            }
        }
        return options
    }

    /// Splits `path:line:column`, but only when the trailing components are
    /// numeric — a file genuinely named "a:b" must not be mangled.
    static func splitLocation(_ argument: String) -> (String, Int?, Int?) {
        let parts = argument.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return (argument, nil, nil) }

        if parts.count >= 3, let line = Int(parts[parts.count - 2]), let column = Int(parts[parts.count - 1]) {
            return (parts.dropLast(2).joined(separator: ":"), line, column)
        }
        if let line = Int(parts[parts.count - 1]) {
            return (parts.dropLast().joined(separator: ":"), line, nil)
        }
        return (argument, nil, nil)
    }
}
