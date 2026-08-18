import Foundation

/// Context used to expand `$(...)` variables in a Run command.
public struct RunContext: Sendable {
    public var fullCurrentPath: String
    public var currentDirectory: String
    public var fileName: String
    public var nameParty: String
    public var extPart: String
    public var currentWord: String
    public var currentLine: Int
    public var currentColumn: Int
    public var appDirectory: String

    public init(
        fullCurrentPath: String = "", currentDirectory: String = "", fileName: String = "",
        namePart: String = "", extPart: String = "", currentWord: String = "",
        currentLine: Int = 1, currentColumn: Int = 1, appDirectory: String = ""
    ) {
        self.fullCurrentPath = fullCurrentPath
        self.currentDirectory = currentDirectory
        self.fileName = fileName
        self.nameParty = namePart
        self.extPart = extPart
        self.currentWord = currentWord
        self.currentLine = currentLine
        self.currentColumn = currentColumn
        self.appDirectory = appDirectory
    }

    /// Builds a context from a document path and caret state.
    public static func forDocument(
        path: String?, currentWord: String = "", line: Int = 1, column: Int = 1
    ) -> RunContext {
        guard let path else {
            return RunContext(currentWord: currentWord, currentLine: line, currentColumn: column)
        }
        let url = URL(fileURLWithPath: path)
        return RunContext(
            fullCurrentPath: path,
            currentDirectory: url.deletingLastPathComponent().path,
            fileName: url.lastPathComponent,
            namePart: url.deletingPathExtension().lastPathComponent,
            extPart: url.pathExtension,
            currentWord: currentWord,
            currentLine: line,
            currentColumn: column,
            appDirectory: Bundle.main.bundlePath
        )
    }

    var substitutions: [String: String] {
        [
            "FULL_CURRENT_PATH": fullCurrentPath,
            "CURRENT_DIRECTORY": currentDirectory,
            "FILE_NAME": fileName,
            "NAME_PART": nameParty,
            "EXT_PART": extPart,
            "CURRENT_WORD": currentWord,
            "CURRENT_LINE": String(currentLine),
            "CURRENT_COLUMN": String(currentColumn),
            "NPP_DIRECTORY": appDirectory,
            "NPP_FULL_FILE_PATH": appDirectory,
        ]
    }
}

/// A saved external command, as in Notepad++'s Run menu.
public struct RunCommand: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var command: String
    /// Key equivalent, e.g. "r" with command+shift.
    public var keyEquivalent: String?

    public init(id: UUID = UUID(), name: String, command: String, keyEquivalent: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.keyEquivalent = keyEquivalent
    }
}

public enum RunCommandExpander {
    /// Expands `$(VARIABLE)` references. Unknown variables are left intact so a
    /// typo is visible in the command rather than silently becoming empty.
    public static func expand(_ command: String, with context: RunContext) -> String {
        let substitutions = context.substitutions
        var result = command
        // Longest names first so NPP_FULL_FILE_PATH is not shadowed by a prefix.
        for key in substitutions.keys.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: "$(\(key))", with: substitutions[key] ?? "")
        }
        return result
    }

    /// Variables referenced by a command that we do not know about.
    public static func unknownVariables(in command: String, context: RunContext) -> [String] {
        let known = Set(context.substitutions.keys)
        guard let regex = try? NSRegularExpression(pattern: #"\$\((\w+)\)"#) else { return [] }
        let range = NSRange(location: 0, length: (command as NSString).length)
        return regex.matches(in: command, options: [], range: range).compactMap { match in
            let name = (command as NSString).substring(with: match.range(at: 1))
            return known.contains(name) ? nil : name
        }
    }
}

/// Stores Run commands on disk.
public final class RunCommandStore {
    private let url: URL
    public private(set) var commands: [RunCommand] = []

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("run-commands.json")
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RunCommand].self, from: data) else { return }
        commands = decoded
    }

    public func save() throws {
        try JSONEncoder().encode(commands).write(to: url, options: .atomic)
    }

    public func add(_ command: RunCommand) throws {
        commands.append(command)
        try save()
    }

    public func remove(id: UUID) throws {
        commands.removeAll { $0.id == id }
        try save()
    }

    public func update(_ command: RunCommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        try save()
    }
}
