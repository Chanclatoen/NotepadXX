import XCTest
@testable import NotepadXXCore

/// The design names three conflict severities and says what each one does.
final class ShortcutConflictTests: XCTestCase {
    private let command: UInt = 1 << 20
    private let option: UInt = 1 << 19
    private let shift: UInt = 1 << 17

    private func map() -> ShortcutMap {
        ShortcutMap(commands: [
            ShortcutCommand(id: "duplicateLine:", title: "Duplicate Line", category: .main,
                            binding: KeyBinding(key: "d", modifiers: 1 << 20)),
            ShortcutCommand(id: "columnEditor:", title: "Column Editor", category: .main,
                            binding: KeyBinding(key: "c", modifiers: (1 << 20) | (1 << 19))),
            ShortcutCommand(id: "playMacro:", title: "Play Macro", category: .macro),
            ShortcutCommand(id: "pluginThing:", title: "Plug-in Thing", category: .plugin),
        ])
    }

    /// Two menu commands on one key: both flagged, the newer wins only after
    /// the user confirms.
    func testTwoMenuCommandsAreAHardConflict() {
        let map = map()
        let conflict = map.conflict(for: KeyBinding(key: "c", modifiers: command | option),
                                    assigningTo: "duplicateLine:")
        XCTAssertEqual(conflict?.severity, .hard)
        XCTAssertEqual(conflict?.commands.map(\.title), ["Column Editor"])
        XCTAssertTrue(conflict?.explanation.contains("Column Editor") ?? false,
                      "the explanation names what holds the key")
    }

    func testAHardConflictIsRefusedUntilForced() throws {
        let map = map()
        let binding = KeyBinding(key: "c", modifiers: command | option)
        XCTAssertThrowsError(try map.assign(binding, to: "duplicateLine:")) { error in
            XCTAssertEqual(error as? ShortcutMap.AssignError, .conflict(["Column Editor"]))
        }
        XCTAssertEqual(map.binding(for: "duplicateLine:")?.key, "d", "nothing changed")

        try map.assign(binding, to: "duplicateLine:", force: true)
        XCTAssertEqual(map.binding(for: "duplicateLine:"), binding)
        XCTAssertNil(map.binding(for: "columnEditor:"), "the previous holder is left without one")
    }

    /// A plug-in shadowing a menu command is allowed, and both keep the key.
    func testAPluginShadowingAMenuCommandIsASoftConflict() throws {
        let map = map()
        let binding = KeyBinding(key: "d", modifiers: command)
        let conflict = map.conflict(for: binding, assigningTo: "pluginThing:")
        XCTAssertEqual(conflict?.severity, .soft)

        try map.assign(binding, to: "pluginThing:", allowingShadow: true)
        XCTAssertEqual(map.binding(for: "pluginThing:"), binding)
        XCTAssertEqual(map.binding(for: "duplicateLine:"), binding,
                       "the menu command keeps its shortcut; scope decides at run time")
    }

    /// A key macOS owns is refused however hard the caller pushes, because a
    /// binding that can never fire is worse than no binding.
    func testAReservedShortcutIsRefusedEvenWhenForced() {
        let map = map()
        let hide = KeyBinding(key: "h", modifiers: command)
        let conflict = map.conflict(for: hide, assigningTo: "duplicateLine:")
        XCTAssertEqual(conflict?.severity, .reserved)
        XCTAssertEqual(conflict?.reservedBy, "Hide the application")

        XCTAssertThrowsError(try map.assign(hide, to: "duplicateLine:", force: true)) { error in
            XCTAssertEqual(error as? ShortcutMap.AssignError, .reserved("Hide the application"))
        }
        XCTAssertEqual(map.binding(for: "duplicateLine:")?.key, "d")
    }

    func testAFreeShortcutHasNoConflict() {
        XCTAssertNil(map().conflict(for: KeyBinding(key: "j", modifiers: command | shift),
                                    assigningTo: "duplicateLine:"))
    }

    /// The "conflicts only" filter needs to know which rows are in conflict.
    func testConflictingCommandsListsBothSides() throws {
        let map = map()
        try map.assign(KeyBinding(key: "d", modifiers: command), to: "playMacro:", allowingShadow: true)
        let conflicting = map.conflictingCommands().map(\.title)
        XCTAssertEqual(Set(conflicting), ["Duplicate Line", "Play Macro"])
    }
}
