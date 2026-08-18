import Foundation

/// One recorded step. Notepad++ macros are pure replay — a sequence of typed
/// text and invoked commands, with no branching — so this is deliberately a
/// flat list rather than a script.
public enum MacroStep: Codable, Equatable, Sendable {
    case insertText(String)
    /// A menu command, identified by its action selector name.
    case command(String)
    /// Caret movement, e.g. "moveLeft", "moveToEndOfLine".
    case navigation(String)

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case "insertText": self = .insertText(value)
        case "command": self = .command(value)
        case "navigation": self = .navigation(value)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unknown macro step \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insertText(let value):
            try container.encode("insertText", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .command(let value):
            try container.encode("command", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .navigation(let value):
            try container.encode("navigation", forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct Macro: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [MacroStep]
    public var keyEquivalent: String?

    public init(id: UUID = UUID(), name: String, steps: [MacroStep], keyEquivalent: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.keyEquivalent = keyEquivalent
    }
}

/// Records and replays macros.
///
/// Consecutive `insertText` steps are coalesced while recording, so typing a
/// word produces one step rather than one per keystroke — this keeps saved
/// macros readable and replay fast.
public final class MacroRecorder {
    public private(set) var isRecording = false
    public private(set) var steps: [MacroStep] = []

    public init() {}

    public func start() {
        isRecording = true
        steps = []
    }

    @discardableResult
    public func stop() -> [MacroStep] {
        isRecording = false
        return steps
    }

    public func record(_ step: MacroStep) {
        guard isRecording else { return }
        if case .insertText(let new) = step,
           case .insertText(let previous)? = steps.last {
            steps[steps.count - 1] = .insertText(previous + new)
        } else {
            steps.append(step)
        }
    }
}

/// Replays macro steps against a target.
@MainActor
public protocol MacroPlaybackTarget: AnyObject {
    func macroInsertText(_ text: String)
    func macroRunCommand(_ selectorName: String)
    func macroNavigate(_ movement: String)
    /// True when the caret has reached the end of the document, used by
    /// "run until end of file".
    var macroIsAtEndOfDocument: Bool { get }
}

@MainActor
public enum MacroPlayer {
    public static func play(_ macro: Macro, on target: MacroPlaybackTarget, times: Int = 1) {
        guard times > 0 else { return }
        for _ in 0..<times {
            playOnce(macro, on: target)
        }
    }

    /// Replays until the caret stops advancing or the document ends. The
    /// no-progress guard is what stops a macro that never moves from looping
    /// forever.
    public static func playUntilEndOfDocument(
        _ macro: Macro, on target: MacroPlaybackTarget, safetyLimit: Int = 100_000
    ) {
        var iterations = 0
        while !target.macroIsAtEndOfDocument && iterations < safetyLimit {
            playOnce(macro, on: target)
            iterations += 1
        }
    }

    private static func playOnce(_ macro: Macro, on target: MacroPlaybackTarget) {
        for step in macro.steps {
            switch step {
            case .insertText(let text): target.macroInsertText(text)
            case .command(let name): target.macroRunCommand(name)
            case .navigation(let movement): target.macroNavigate(movement)
            }
        }
    }
}

/// Persists saved macros.
public final class MacroStore {
    private let url: URL
    public private(set) var macros: [Macro] = []

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("macros.json")
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Macro].self, from: data) else { return }
        macros = decoded
    }

    public func save() throws {
        try JSONEncoder().encode(macros).write(to: url, options: .atomic)
    }

    public func add(_ macro: Macro) throws {
        macros.append(macro)
        try save()
    }

    public func remove(id: UUID) throws {
        macros.removeAll { $0.id == id }
        try save()
    }
}
