import XCTest
@testable import NotepadXXCore

final class HexColorTests: XCTestCase {
    func testParsesSixDigitHex() {
        let rgb = HexColor.components("#FF8000")
        XCTAssertEqual(rgb?.red ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.green ?? 0, 0.502, accuracy: 0.01)
        XCTAssertEqual(rgb?.blue ?? 0, 0.0, accuracy: 0.001)
    }

    func testAcceptsShorthandAndMissingHash() {
        XCTAssertNotNil(HexColor.components("FFF"))
        XCTAssertEqual(HexColor.components("#FFF")?.red, HexColor.components("#FFFFFF")?.red)
        XCTAssertNotNil(HexColor.components("00FF00"))
    }

    func testRejectsNonsense() {
        XCTAssertNil(HexColor.components("#GGGGGG"))
        XCTAssertNil(HexColor.components("#12345"))
        XCTAssertNil(HexColor.components(""))
    }

    func testRoundTrip() {
        let hex = "#3A7BD5"
        guard let rgb = HexColor.components(hex) else { return XCTFail("parse failed") }
        XCTAssertEqual(HexColor.string(red: rgb.red, green: rgb.green, blue: rgb.blue), hex)
    }

    func testStringClampsOutOfRangeComponents() {
        XCTAssertEqual(HexColor.string(red: 2, green: -1, blue: 0.5), "#FF0080")
    }
}

final class ThemeStoreTests: XCTestCase {
    private func makeStore() throws -> (ThemeStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-theme-\(UUID().uuidString)", isDirectory: true)
        return (try ThemeStore(directory: dir), dir)
    }

    func testBuiltInsAreAlwaysPresent() throws {
        let (store, _) = try makeStore()
        XCTAssertTrue(store.allThemes.contains { $0.name == "Default Dark" })
        XCTAssertTrue(store.allThemes.contains { $0.name == "Default Light" })
    }

    func testSaveAndReloadUserTheme() throws {
        let (store, dir) = try makeStore()
        var theme = EditorTheme.defaultDark
        theme.name = "Midnight"
        theme.tokenColors[TokenType.keyword1.rawValue] = "#FF0000"
        try store.save(theme)

        let reopened = try ThemeStore(directory: dir)
        let loaded = reopened.theme(named: "Midnight")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.color(for: .keyword1), "#FF0000")
    }

    /// Shadowing a built-in name would make it impossible to get back to the
    /// shipped theme.
    func testCannotShadowABuiltInName() throws {
        let (store, _) = try makeStore()
        XCTAssertThrowsError(try store.save(EditorTheme.defaultDark)) { error in
            XCTAssertEqual(error as? ThemeStore.ThemeError, .reservedName("Default Dark"))
        }
    }

    func testDeleteRemovesOnlyUserThemes() throws {
        let (store, _) = try makeStore()
        var theme = EditorTheme.defaultLight
        theme.name = "Scratch"
        try store.save(theme)
        XCTAssertNotNil(store.theme(named: "Scratch"))

        store.delete(named: "Scratch")
        XCTAssertNil(store.theme(named: "Scratch"))
        XCTAssertNotNil(store.theme(named: "Default Light"), "built-ins survive")
    }

    func testThemeNameWithASlashDoesNotEscapeTheDirectory() throws {
        let (store, dir) = try makeStore()
        var theme = EditorTheme.defaultDark
        theme.name = "evil/../../escape"
        try store.save(theme)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("themes").path
        )
        XCTAssertEqual(files.count, 1, "the file stays inside the themes directory")
    }
}

final class ShortcutMapTests: XCTestCase {
    private let command = KeyBinding(key: "f", modifiers: 1 << 20)
    private let shiftCommand = KeyBinding(key: "f", modifiers: (1 << 20) | (1 << 17))

    private func makeMap(directory: URL? = nil) -> ShortcutMap {
        ShortcutMap(commands: [
            ShortcutCommand(id: "find:", title: "Find", category: .main),
            ShortcutCommand(id: "replace:", title: "Replace", category: .main),
            ShortcutCommand(id: "playMacro:", title: "Play Macro", category: .macro),
        ], directory: directory)
    }

    func testDisplayStringUsesStandardSymbols() {
        XCTAssertEqual(shiftCommand.displayString, "⇧⌘F")
        XCTAssertEqual(command.displayString, "⌘F")
    }

    func testAssignAndRead() throws {
        let map = makeMap()
        try map.assign(command, to: "find:")
        XCTAssertEqual(map.binding(for: "find:"), command)
    }

    /// Two commands on one key would make one silently unreachable.
    func testConflictIsRefusedByDefault() throws {
        let map = makeMap()
        try map.assign(command, to: "find:")
        XCTAssertThrowsError(try map.assign(command, to: "replace:")) { error in
            guard case ShortcutMap.AssignError.conflict(let titles)? = error as? ShortcutMap.AssignError else {
                return XCTFail("expected a conflict error")
            }
            XCTAssertEqual(titles, ["Find"])
        }
        XCTAssertNil(map.binding(for: "replace:"))
    }

    func testForcedAssignmentUnbindsThePreviousHolder() throws {
        let map = makeMap()
        try map.assign(command, to: "find:")
        try map.assign(command, to: "replace:", force: true)
        XCTAssertEqual(map.binding(for: "replace:"), command)
        XCTAssertNil(map.binding(for: "find:"), "the old holder is unbound, not left duplicated")
    }

    func testDifferentModifiersAreNotAConflict() throws {
        let map = makeMap()
        try map.assign(command, to: "find:")
        XCTAssertNoThrow(try map.assign(shiftCommand, to: "replace:"))
    }

    func testUnbindingIsAllowed() throws {
        let map = makeMap()
        try map.assign(command, to: "find:")
        try map.assign(nil, to: "find:")
        XCTAssertNil(map.binding(for: "find:"))
    }

    func testUnknownCommandThrows() {
        XCTAssertThrowsError(try makeMap().assign(command, to: "nope:")) { error in
            XCTAssertEqual(error as? ShortcutMap.AssignError, .unknownCommand)
        }
    }

    func testCategoriesFilter() {
        XCTAssertEqual(makeMap().commands(in: .macro).map(\.id), ["playMacro:"])
    }

    /// Only overrides are persisted, so commands added in a later build still
    /// pick up their new default binding.
    func testRebindingsPersistWithoutFreezingDefaults() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let map = makeMap(directory: dir)
        try map.assign(shiftCommand, to: "replace:")

        // A later build adds a command with a default binding.
        let reopened = ShortcutMap(commands: [
            ShortcutCommand(id: "find:", title: "Find", category: .main),
            ShortcutCommand(id: "replace:", title: "Replace", category: .main),
            ShortcutCommand(id: "newThing:", title: "New Thing", category: .main,
                            binding: KeyBinding(key: "n", modifiers: 1 << 20)),
        ], directory: dir)

        XCTAssertEqual(reopened.binding(for: "replace:"), shiftCommand, "the override survives")
        XCTAssertEqual(reopened.binding(for: "newThing:")?.key, "n",
                       "a newly shipped default is not clobbered by the saved file")
    }
}
