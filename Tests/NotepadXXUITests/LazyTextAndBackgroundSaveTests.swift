import XCTest
import AppKit
import NotepadXXEditor
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The document no longer copies the editor's text on every edit; it pulls it
/// when something reads it. And a large file saves off the main thread.
@MainActor
final class LazyTextAndBackgroundSaveTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-lazy-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name)
    }

    func testTheDocumentPullsTheEditorTextOnlyWhenRead() {
        let document = TextDocument(text: "old")
        var pulls = 0
        document.noteEdited { pulls += 1; return "new" }
        document.noteEdited { pulls += 1; return "newer" }
        XCTAssertTrue(document.isDirty, "dirty without reading anything")
        XCTAssertEqual(pulls, 0, "an edit does not copy the text")
        XCTAssertEqual(document.text, "newer")
        XCTAssertEqual(document.text, "newer")
        XCTAssertEqual(pulls, 1, "the pulled text is kept until the next edit")
    }

    func testAnAssignmentReplacesWhatWasWaitingToBePulled() {
        let document = TextDocument(text: "old")
        document.noteEdited { "from the editor" }
        document.text = "assigned"
        XCTAssertEqual(document.text, "assigned")
        XCTAssertTrue(document.isDirty)
    }

    func testTypingDoesNotReadTheWholeBuffer() throws {
        let controller = MainWindowController()
        let document = TextDocument(text: "hello\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        let editor = try XCTUnwrap(controller.currentEditor)
        editor.onTextChange = nil
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.replaceSelection(with: "x")
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.text, "xhello\n")
    }

    func testBackgroundSaveWritesTheFileAndCleansTheDocument() throws {
        let url = tempURL("big.txt")
        try "start\n".write(to: url, atomically: true, encoding: .utf8)
        let saved = MainWindowController.backgroundSaveThreshold
        MainWindowController.backgroundSaveThreshold = 10
        defer { MainWindowController.backgroundSaveThreshold = saved }

        let controller = MainWindowController()
        let document = TextDocument(fileURL: url, text: "start\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.currentEditor?.replaceAll(with: String(repeating: "line of text\n", count: 50))
        XCTAssertTrue(document.isDirty)

        let done = expectation(description: "saved")
        controller.saveActiveDocument { done.fulfill() }
        XCTAssertFalse(controller.savesInFlight.isEmpty, "the write is running off the main thread")
        wait(for: [done], timeout: 10)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), String(repeating: "line of text\n", count: 50))
        XCTAssertFalse(document.isDirty)
        XCTAssertTrue(controller.savesInFlight.isEmpty)
    }

    func testAnEditDuringABackgroundSaveStaysUnsaved() throws {
        let url = tempURL("race.txt")
        try "x\n".write(to: url, atomically: true, encoding: .utf8)
        let document = TextDocument(fileURL: url, text: "first version\n")
        document.text = "first version, edited\n"
        let snapshot = try document.makeSaveSnapshot()
        try TextDocument.SaveSnapshot.write(snapshot)
        document.text = "typed while the write ran\n"
        document.finishSave(snapshot)
        XCTAssertTrue(document.isDirty, "the newer text is not on disk")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first version, edited\n")

        let again = try document.makeSaveSnapshot()
        try TextDocument.SaveSnapshot.write(again)
        document.finishSave(again)
        XCTAssertFalse(document.isDirty)
    }

    func testAFailedBackgroundSaveIsReportedAndStaysDirty() {
        let saved = MainWindowController.backgroundSaveThreshold
        MainWindowController.backgroundSaveThreshold = 10
        defer { MainWindowController.backgroundSaveThreshold = saved }
        MainWindowController.presentsAlerts = false
        defer { MainWindowController.presentsAlerts = true }

        let controller = MainWindowController()
        let document = TextDocument(fileURL: URL(fileURLWithPath: "/System/nope/big.txt"), text: "a\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.currentEditor?.replaceAll(with: String(repeating: "line of text\n", count: 20))

        let done = expectation(description: "finished")
        controller.saveActiveDocument { done.fulfill() }
        wait(for: [done], timeout: 10)

        XCTAssertNotNil(controller.lastReportedError)
        XCTAssertTrue(document.isDirty)
    }
}
