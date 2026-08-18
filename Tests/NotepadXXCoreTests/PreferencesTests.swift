import XCTest
@testable import NotepadXXCore

final class PreferencesTests: XCTestCase {
    private func makeStore() throws -> (PreferencesStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-prefs-\(UUID().uuidString)", isDirectory: true)
        return (try PreferencesStore(directory: dir), dir)
    }

    func testDefaultsMatchNotepadPlusPlusBehaviour() {
        let preferences = Preferences()
        XCTAssertFalse(preferences.confirmCloseUnsaved,
                       "the scratchpad contract: never prompt to save")
        XCTAssertTrue(preferences.rememberSession)
        XCTAssertEqual(preferences.tabWidth, 4)
        XCTAssertTrue(preferences.showLineNumbers)
    }

    func testChangesPersistAcrossReload() throws {
        let (store, dir) = try makeStore()
        try store.update {
            $0.tabWidth = 8
            $0.wordWrap = true
            $0.themeName = "Solarized"
        }
        let reopened = try PreferencesStore(directory: dir)
        XCTAssertEqual(reopened.preferences.tabWidth, 8)
        XCTAssertTrue(reopened.preferences.wordWrap)
        XCTAssertEqual(reopened.preferences.themeName, "Solarized")
    }

    func testSanitizeClampsOutOfRangeValues() {
        var preferences = Preferences()
        preferences.tabWidth = 999
        preferences.fontSize = 0
        preferences.recentFilesLimit = -5
        preferences.backupIntervalSeconds = 0
        preferences.sanitize()

        XCTAssertEqual(preferences.tabWidth, 16)
        XCTAssertEqual(preferences.fontSize, 6)
        XCTAssertEqual(preferences.recentFilesLimit, 0)
        XCTAssertEqual(preferences.backupIntervalSeconds, 1)
    }

    func testSavingClampsBeforeWriting() throws {
        let (store, dir) = try makeStore()
        try store.update { $0.tabWidth = 500 }
        XCTAssertEqual(store.preferences.tabWidth, 16)
        XCTAssertEqual(try PreferencesStore(directory: dir).preferences.tabWidth, 16)
    }

    /// A file written by an older build lacking newer keys must still load.
    func testPartialJSONLoadsWithDefaultsForMissingKeys() throws {
        let (_, dir) = try makeStore()
        let partial = #"{"tabWidth": 2, "wordWrap": true}"#
        try Data(partial.utf8).write(to: dir.appendingPathComponent("preferences.json"))

        let store = try PreferencesStore(directory: dir)
        XCTAssertEqual(store.preferences.tabWidth, 2, "the supplied key is honoured")
        XCTAssertTrue(store.preferences.wordWrap)
        XCTAssertTrue(store.preferences.showLineNumbers, "missing keys fall back to defaults")
    }

    /// A corrupt file must not stop the app from starting.
    func testCorruptFileFallsBackToDefaults() throws {
        let (_, dir) = try makeStore()
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("preferences.json"))
        let store = try PreferencesStore(directory: dir)
        XCTAssertEqual(store.preferences, Preferences(), "defaults, not a crash")
    }

    func testResetToDefaults() throws {
        let (store, dir) = try makeStore()
        try store.update { $0.tabWidth = 8 }
        try store.resetToDefaults()
        XCTAssertEqual(store.preferences.tabWidth, 4)
        XCTAssertEqual(try PreferencesStore(directory: dir).preferences.tabWidth, 4)
    }

    func testExportImportRoundTrip() throws {
        let (source, _) = try makeStore()
        try source.update {
            $0.tabWidth = 2
            $0.fontName = "Menlo"
            $0.showWhitespace = true
        }
        let exported = try source.exportJSON()

        let (destination, _) = try makeStore()
        try destination.importJSON(exported)
        XCTAssertEqual(destination.preferences, source.preferences)
    }

    func testImportingRubbishThrowsAndLeavesSettingsIntact() throws {
        let (store, _) = try makeStore()
        try store.update { $0.tabWidth = 7 }
        XCTAssertThrowsError(try store.importJSON(Data("nonsense".utf8)))
        XCTAssertEqual(store.preferences.tabWidth, 7, "a failed import must not clobber settings")
    }
}
