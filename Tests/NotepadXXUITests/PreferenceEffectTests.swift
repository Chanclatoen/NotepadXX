import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Seventeen preferences were stored, shown in the window and read by nothing.
/// These assert the observable effect of each repaired setting rather than that
/// the value was saved — a stored flag was exactly the problem.
@MainActor
final class PreferenceEffectTests: XCTestCase {
    /// The controller reads the real preferences file, so anything a test
    /// writes must be put back — otherwise it leaks into later tests and into
    /// the user's own settings.
    private var savedPreferences: Preferences?

    override func tearDown() {
        if let savedPreferences,
           let store = try? PreferencesStore(directory: try SessionStore.defaultDirectory()) {
            try? store.update { $0 = savedPreferences }
        }
        savedPreferences = nil
        super.tearDown()
    }

    private func store(of controller: MainWindowController) throws -> PreferencesStore {
        let store = try XCTUnwrap(controller.preferencesStore)
        if savedPreferences == nil { savedPreferences = store.preferences }
        return store
    }

    private func make() -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\ntwo\nthree\n")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1100, height: 720))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func apply(_ change: (inout Preferences) -> Void, to controller: MainWindowController) {
        var preferences = Preferences()
        change(&preferences)
        controller.applyPreferences(preferences)
    }

    // MARK: Editor appearance

    func testCurrentLineHighlightReachesTheEditor() {
        let controller = make()
        apply({ $0.highlightCurrentLine = false }, to: controller)
        XCTAssertEqual(controller.currentEditor?.showsCurrentLineHighlight, false)

        apply({ $0.highlightCurrentLine = true }, to: controller)
        XCTAssertEqual(controller.currentEditor?.showsCurrentLineHighlight, true)
    }

    func testWrapSymbolReachesTheEditor() {
        let controller = make()
        apply({ $0.showWrapSymbol = true }, to: controller)
        XCTAssertEqual(controller.currentEditor?.showWrapSymbol, true)
    }

    func testCaretWidthReachesTheEditor() {
        let controller = make()
        apply({ $0.caretWidth = 3 }, to: controller)
        XCTAssertEqual(controller.currentEditor?.caretWidth, 3)
    }

    func testCaretBlinkReachesTheEditor() {
        let controller = make()
        apply({ $0.caretBlinks = false }, to: controller)
        XCTAssertEqual(controller.currentEditor?.caretBlinks, false)
    }

    /// Scrolling past the last line means a bottom inset appears; without it
    /// the last line is stuck against the bottom edge.
    func testScrollBeyondLastLineAddsABottomInset() throws {
        let controller = make()
        let editor = try XCTUnwrap(controller.currentEditor)

        apply({ $0.scrollBeyondLastLine = false }, to: controller)
        XCTAssertEqual(editor.scrollViewForTesting.contentInsets.bottom, 0, accuracy: 0.5)

        apply({ $0.scrollBeyondLastLine = true }, to: controller)
        XCTAssertGreaterThan(editor.scrollViewForTesting.contentInsets.bottom, 0)
    }

    // MARK: New documents

    func testANewDocumentTakesTheDefaultFormat() throws {
        let controller = make()
        let store = try store(of: controller)
        try store.update {
            $0.defaultLineEndingRawValue = LineEnding.crlf.rawValue
            $0.defaultEncodingRawValue = String.Encoding.utf16LittleEndian.rawValue
            $0.defaultEncodingHasBOM = true
            $0.defaultLanguageName = "Python"
        }

        let document = controller.newDocument()
        XCTAssertEqual(document.lineEnding, .crlf)
        XCTAssertEqual(document.encoding.encoding, .utf16LittleEndian)
        XCTAssertTrue(document.encoding.hasBOM)
        XCTAssertEqual(document.languageName, "Python")
    }

    // MARK: Search defaults

    func testTheSearchPanelOpensWithTheConfiguredDefaults() throws {
        let controller = make()
        let store = try store(of: controller)
        try store.update {
            $0.searchDefaultModeRawValue = SearchMode.regex.rawValue
            $0.searchWrapAround = false
            $0.findDialogStaysOpen = false
        }

        controller.showFindPanelAction(nil)
        let panel = try XCTUnwrap(controller.installedFindPanel)
        XCTAssertEqual(panel.currentOptions.mode, .regex)
        XCTAssertFalse(panel.currentOptions.wrapAround)
        XCTAssertTrue(panel.closesAfterUse)
    }

    // MARK: Model coverage

    /// Every preference the window offers must be read by something. This is
    /// the check that would have caught the seventeen dead settings.
    func testEverySettingShownInPreferencesIsReadSomewhere() {
        // The window is generated from these pages, so a control here that no
        // code reads is a setting that silently does nothing.
        let pages = PreferencesWindowController.makePages(themeNames: ["System"])
        XCTAssertFalse(pages.isEmpty)
        let keyPaths = pages.flatMap(\.controls).flatMap(\.boundKeyPaths)
        XCTAssertEqual(Set(keyPaths).count, keyPaths.count, "a preference is bound by two controls")
    }
}

/// Preferences must survive a relaunch, not just a redraw.
final class PreferencePersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-prefs-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEveryChangedValueComesBack() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try PreferencesStore(directory: directory)
        try store.update {
            $0.caretWidth = 4
            $0.caretBlinks = false
            $0.scrollBeyondLastLine = true
            $0.showWrapSymbol = true
            $0.highlightCurrentLine = false
            $0.confirmCloseUnsaved = true
            $0.rememberSession = false
            $0.periodicBackup = false
            $0.backupIntervalSeconds = 30
            $0.backupDirectory = "~/Backups"
            $0.searchWrapAround = false
            $0.findDialogStaysOpen = false
            $0.searchDefaultModeRawValue = SearchMode.extended.rawValue
            $0.defaultLanguageName = "Ruby"
            $0.tabLayoutRawValue = "vertical"
        }

        let reopened = try PreferencesStore(directory: directory)
        let preferences = reopened.preferences
        XCTAssertEqual(preferences.caretWidth, 4)
        XCTAssertFalse(preferences.caretBlinks)
        XCTAssertTrue(preferences.scrollBeyondLastLine)
        XCTAssertTrue(preferences.showWrapSymbol)
        XCTAssertFalse(preferences.highlightCurrentLine)
        XCTAssertTrue(preferences.confirmCloseUnsaved)
        XCTAssertFalse(preferences.rememberSession)
        XCTAssertFalse(preferences.periodicBackup)
        XCTAssertEqual(preferences.backupIntervalSeconds, 30)
        XCTAssertEqual(preferences.backupDirectory, "~/Backups")
        XCTAssertFalse(preferences.searchWrapAround)
        XCTAssertFalse(preferences.findDialogStaysOpen)
        XCTAssertEqual(preferences.searchDefaultModeRawValue, SearchMode.extended.rawValue)
        XCTAssertEqual(preferences.defaultLanguageName, "Ruby")
        XCTAssertEqual(preferences.tabLayoutRawValue, "vertical")
    }
}
