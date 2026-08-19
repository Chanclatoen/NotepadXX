import Foundation

/// A key equivalent: the character plus its modifier mask, stored in a form
/// that survives JSON so the Shortcut Mapper can persist rebindings.
public struct KeyBinding: Codable, Equatable, Sendable, Hashable {
    public var key: String
    /// Raw value of NSEvent.ModifierFlags, masked to the device-independent set.
    public var modifiers: UInt

    public init(key: String, modifiers: UInt) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Human-readable form, e.g. "⇧⌘F".
    public var displayString: String {
        var result = ""
        if modifiers & (1 << 18) != 0 { result += "⌃" }   // control
        if modifiers & (1 << 19) != 0 { result += "⌥" }   // option
        if modifiers & (1 << 17) != 0 { result += "⇧" }   // shift
        if modifiers & (1 << 20) != 0 { result += "⌘" }   // command
        return result + key.uppercased()
    }
}

/// One rebindable command.
public struct ShortcutCommand: Codable, Equatable, Sendable, Identifiable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case main, macro, run, plugin, scintilla
    }
    public var id: String          // the action selector name
    public var title: String
    public var category: Category
    public var binding: KeyBinding?

    public init(id: String, title: String, category: Category, binding: KeyBinding? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.binding = binding
    }
}

/// How badly two commands disagree about a key.
public enum ConflictSeverity: String, Sendable, Equatable {
    /// Two commands in the same scope. Both are flagged; the newer one only
    /// wins after the user confirms.
    case hard
    /// A plug-in or macro shadows a menu command. Allowed, and resolved by
    /// scope when the key is pressed.
    case soft
    /// Claimed by macOS. Refused, naming what owns it.
    case reserved
}

/// What stands in the way of a binding.
public struct ShortcutConflict: Sendable, Equatable {
    public let severity: ConflictSeverity
    /// The commands already using the key, for a hard or soft conflict.
    public let commands: [ShortcutCommand]
    /// What the system uses the key for, for a reserved one.
    public let reservedBy: String?

    public init(severity: ConflictSeverity, commands: [ShortcutCommand] = [], reservedBy: String? = nil) {
        self.severity = severity
        self.commands = commands
        self.reservedBy = reservedBy
    }

    /// A sentence explaining the conflict — never a beep on its own.
    public var explanation: String {
        switch severity {
        case .reserved:
            return "\(reservedBy ?? "macOS") already uses this shortcut, and the system keeps it."
        case .hard:
            let names = commands.map(\.title).joined(separator: ", ")
            return "Already used by \(names). Reassigning moves the shortcut and leaves it without one."
        case .soft:
            let names = commands.map(\.title).joined(separator: ", ")
            return "\(names) also uses this shortcut. Both can keep it — the one in scope wins."
        }
    }
}

/// The Shortcut Mapper's model: every rebindable command, plus conflict
/// detection so two commands cannot silently claim one key.
public final class ShortcutMap {
    public private(set) var commands: [ShortcutCommand]
    private let url: URL?

    public init(commands: [ShortcutCommand], directory: URL? = nil) {
        self.commands = commands
        self.url = directory?.appendingPathComponent("shortcuts.json")
        load()
    }

    public func commands(in category: ShortcutCommand.Category) -> [ShortcutCommand] {
        commands.filter { $0.category == category }
    }

    /// Commands other than `id` already bound to `binding`.
    public func conflicts(for binding: KeyBinding, excluding id: String) -> [ShortcutCommand] {
        commands.filter { $0.id != id && $0.binding == binding }
    }

    /// Shortcuts macOS keeps for itself, with what owns each one. Refusing
    /// these with an explanation beats letting the user bind a key that will
    /// never reach the app.
    public static let systemReserved: [KeyBinding: String] = [
        KeyBinding(key: "\t", modifiers: 1 << 20): "Switching applications",
        KeyBinding(key: " ", modifiers: 1 << 20): "Spotlight",
        KeyBinding(key: "q", modifiers: 1 << 20): "Quit",
        KeyBinding(key: "h", modifiers: 1 << 20): "Hide the application",
        KeyBinding(key: "3", modifiers: (1 << 20) | (1 << 17)): "Taking a screenshot",
        KeyBinding(key: "4", modifiers: (1 << 20) | (1 << 17)): "Taking a screenshot",
        KeyBinding(key: "5", modifiers: (1 << 20) | (1 << 17)): "Screenshot and recording",
        KeyBinding(key: "\u{1b}", modifiers: (1 << 20) | (1 << 19)): "Force Quit",
    ]

    /// What, if anything, stands in the way of giving `binding` to `id`.
    public func conflict(for binding: KeyBinding, assigningTo id: String) -> ShortcutConflict? {
        if let owner = Self.systemReserved[binding] {
            return ShortcutConflict(severity: .reserved, reservedBy: owner)
        }
        let clashing = conflicts(for: binding, excluding: id)
        guard !clashing.isEmpty else { return nil }

        // A plug-in or macro shadowing a menu command is resolved by scope at
        // run time, so it is allowed and merely flagged.
        let assigningCategory = commands.first { $0.id == id }?.category
        let shadowing = assigningCategory == .plugin || assigningCategory == .macro
        let allMenuCommands = clashing.allSatisfy { $0.category == .main }
        if shadowing && allMenuCommands {
            return ShortcutConflict(severity: .soft, commands: clashing)
        }
        return ShortcutConflict(severity: .hard, commands: clashing)
    }

    /// Every command currently in conflict with another, for the mapper's
    /// "conflicts only" filter.
    public func conflictingCommands() -> [ShortcutCommand] {
        var counts: [KeyBinding: [ShortcutCommand]] = [:]
        for command in commands {
            guard let binding = command.binding else { continue }
            counts[binding, default: []].append(command)
        }
        return counts.values.filter { $0.count > 1 }.flatMap { $0 }
            .sorted { $0.title < $1.title }
    }

    public enum AssignError: Error, Equatable {
        case unknownCommand
        case conflict([String])
        /// Claimed by macOS, with what owns it.
        case reserved(String)
    }

    /// Assigns a binding.
    ///
    /// Refuses on conflict unless `force` is set, in which case the previous
    /// holders are unbound — leaving two commands on one key would make one of
    /// them silently unreachable. `allowingShadow` is the exception the design
    /// makes for soft conflicts: a plug-in or macro may share a menu command's
    /// key, because scope decides which one fires.
    public func assign(_ binding: KeyBinding?, to id: String,
                       force: Bool = false, allowingShadow: Bool = false) throws {
        guard let index = commands.firstIndex(where: { $0.id == id }) else {
            throw AssignError.unknownCommand
        }
        if let binding {
            // A key the system owns is refused whatever `force` says: forcing
            // it would store a shortcut that can never fire.
            if let owner = Self.systemReserved[binding] {
                throw AssignError.reserved(owner)
            }
            let clashing = conflicts(for: binding, excluding: id)
            if !clashing.isEmpty && !allowingShadow {
                guard force else { throw AssignError.conflict(clashing.map(\.title)) }
                for conflict in clashing {
                    if let conflictIndex = commands.firstIndex(where: { $0.id == conflict.id }) {
                        commands[conflictIndex].binding = nil
                    }
                }
            }
        }
        commands[index].binding = binding
        save()
    }

    public func binding(for id: String) -> KeyBinding? {
        commands.first { $0.id == id }?.binding
    }

    public func resetToDefaults(_ defaults: [ShortcutCommand]) {
        commands = defaults
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let url else { return }
        // Only rebindings are stored, so new commands added in a later build
        // still get their default binding.
        let overrides = commands.reduce(into: [String: KeyBinding?]()) { result, command in
            result[command.id] = command.binding
        }
        let encodable = overrides.compactMapValues { $0 }
        try? JSONEncoder().encode(encodable).write(to: url, options: .atomic)
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let overrides = try? JSONDecoder().decode([String: KeyBinding].self, from: data) else { return }
        for (id, binding) in overrides {
            guard let index = commands.firstIndex(where: { $0.id == id }) else { continue }
            commands[index].binding = binding
        }
    }
}
