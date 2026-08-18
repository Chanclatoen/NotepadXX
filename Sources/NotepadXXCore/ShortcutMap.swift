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

    public enum AssignError: Error, Equatable {
        case unknownCommand
        case conflict([String])
    }

    /// Assigns a binding. Refuses on conflict unless `force` is set, in which
    /// case the previous holders are unbound — leaving two commands on one key
    /// would make one of them silently unreachable.
    public func assign(_ binding: KeyBinding?, to id: String, force: Bool = false) throws {
        guard let index = commands.firstIndex(where: { $0.id == id }) else {
            throw AssignError.unknownCommand
        }
        if let binding {
            let clashing = conflicts(for: binding, excluding: id)
            if !clashing.isEmpty {
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
