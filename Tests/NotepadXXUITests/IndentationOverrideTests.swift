import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Per-language indentation and re-indent-on-paste.
final class IndentationOverrideTests: XCTestCase {
    func testALanguageWithoutAnOverrideFollowsTheDefaults() {
        var preferences = Preferences()
        preferences.tabWidth = 4
        preferences.replaceTabsBySpaces = true
        let indentation = preferences.indentation(forLanguage: "Swift")
        XCTAssertEqual(indentation.width, 4)
        XCTAssertTrue(indentation.usesSpaces)
    }

    func testAnOverrideWinsOverTheDefault() {
        var preferences = Preferences()
        preferences.tabWidth = 4
        preferences.replaceTabsBySpaces = true
        preferences.indentOverrides["Makefile"] = .init(width: 8, usesSpaces: false)

        let makefile = preferences.indentation(forLanguage: "Makefile")
        XCTAssertEqual(makefile.width, 8)
        XCTAssertFalse(makefile.usesSpaces, "a Makefile needs real tabs")

        let swift = preferences.indentation(forLanguage: "Swift")
        XCTAssertEqual(swift.width, 4, "other languages are untouched")
    }

    func testOverridesSurviveARelaunch() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-overrides-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try PreferencesStore(directory: directory)
        try store.update { $0.indentOverrides["Python"] = .init(width: 2, usesSpaces: true) }

        let reopened = try PreferencesStore(directory: directory)
        XCTAssertEqual(reopened.preferences.indentOverrides["Python"],
                       Preferences.IndentOverride(width: 2, usesSpaces: true))
    }

    // MARK: Re-indent on paste

    /// The block keeps its own shape; every line moves by the same amount.
    func testPastedBlockIsMovedToTheTargetIndentKeepingItsShape() {
        let pasted = "if x {\n    body()\n}"
        let result = ClipboardBehaviour.reindented(pasted, toMatch: "        ", tabWidth: 4)

        // The first line lands at the caret, which is already indented; the
        // rest move by the same eight columns, so the nesting is preserved.
        XCTAssertEqual(result, "if x {\n            body()\n        }", "got:\n\(result)")
    }

    func testBlankLinesStayEmpty() {
        let result = ClipboardBehaviour.reindented("a\n\nb", toMatch: "    ", tabWidth: 4)
        XCTAssertEqual(result, "a\n\n    b", "a blank line is not filled with indent")
    }

    func testNothingMovesWhenTheIndentAlreadyMatches() {
        let pasted = "    one\n    two"
        XCTAssertEqual(ClipboardBehaviour.reindented(pasted, toMatch: "    ", tabWidth: 4), pasted)
    }
}

/// A file that disappears underneath an open document, and comes back.
@MainActor
final class MissingFileTests: XCTestCase {
    private func makeOpenDocument() throws -> (MainWindowController, URL, TextDocument) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-missing-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try "on disk".write(to: url, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        let document = try TextDocument.load(contentsOf: url)
        controller.adopt(documents: [document], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return (controller, url, document)
    }

    /// Deleting the file must not close the document — the text is still there
    /// and can be written back.
    func testADeletedFileLeavesTheDocumentOpen() throws {
        let (controller, url, document) = try makeOpenDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(document.isMissingFromDisk())

        controller.checkForExternalChanges()
        XCTAssertEqual(controller.documents.count, 1, "the document is still open")
        XCTAssertTrue(controller.missingDocumentIDs.contains(document.id))
    }

    /// When the path reappears the document re-attaches and takes the new text.
    func testTheDocumentReattachesWhenTheFileComesBack() throws {
        let (controller, url, document) = try makeOpenDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        try FileManager.default.removeItem(at: url)
        controller.checkForExternalChanges()
        XCTAssertTrue(controller.missingDocumentIDs.contains(document.id))

        try "back again".write(to: url, atomically: true, encoding: .utf8)
        controller.checkForExternalChanges()

        XCTAssertFalse(controller.missingDocumentIDs.contains(document.id), "it re-attached")
        XCTAssertEqual(document.text, "back again")
    }

    /// Unsaved edits are never overwritten by a returning file.
    func testUnsavedEditsSurviveTheFileComingBack() throws {
        let (controller, url, document) = try makeOpenDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.text = "my unsaved work"
        try FileManager.default.removeItem(at: url)
        controller.checkForExternalChanges()

        try "something else".write(to: url, atomically: true, encoding: .utf8)
        controller.checkForExternalChanges()

        XCTAssertEqual(document.text, "my unsaved work", "the edits were kept")
    }
}
