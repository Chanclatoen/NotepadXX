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

    // MARK: - An edit is never lost with the pane it was typed in

    private func split(_ text: String) -> (MainWindowController, TextDocument) {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        controller.adopt(documents: [document], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1200, height: 700))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.cloneToOtherViewAction(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        return (controller, document)
    }

    func testAnEditSurvivesClosingTheClone() throws {
        let (controller, document) = split("one\ntwo\n")
        let primary = controller.editorController(for: document, inPane: 0)
        primary.selectedRange = NSRange(location: 0, length: 0)
        primary.replaceSelection(with: "typed ")
        // The edit has not been read yet; now the clone's tab goes away.
        let cloneIndex = try XCTUnwrap(controller.tabs.lastIndex { $0.pane == 1 })
        controller.performClose(index: cloneIndex)
        XCTAssertEqual(document.text, "typed one\ntwo\n")
    }

    func testAnEditSurvivesClosingTheSplit() {
        let (controller, document) = split("one\ntwo\n")
        let primary = controller.editorController(for: document, inPane: 0)
        primary.selectedRange = NSRange(location: 0, length: 0)
        primary.replaceSelection(with: "typed ")
        controller.closeSplitAction(nil)
        XCTAssertEqual(document.text, "typed one\ntwo\n")
    }

    func testAnEditSurvivesMovingToTheOtherView() {
        let controller = MainWindowController()
        let document = TextDocument(text: "one\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.currentEditor?.replaceSelection(with: "typed ")
        controller.moveToOtherViewAction(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(document.text, "typed one\n")
    }

    // MARK: - Unchanged text is not an edit

    func testSortingSortedLinesLeavesTheDocumentClean() {
        let controller = MainWindowController()
        let document = TextDocument(text: "a\nb\nc\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.sortLinesAscendingAction(nil)
        XCTAssertFalse(document.isDirty, "nothing changed, so nothing to save")
        controller.sortLinesDescendingAction(nil)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.text, "c\nb\na\n")
    }

    func testUppercasingUppercaseTextLeavesTheDocumentClean() {
        let controller = MainWindowController()
        let document = TextDocument(text: "ABC\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        controller.convertUpperCaseAction(nil)
        XCTAssertFalse(document.isDirty)
    }

    // MARK: - The snapshot is independent of the live editor

    func testTypingWhileABackgroundSaveRunsDoesNotReachTheFile() throws {
        let url = tempURL("typing.txt")
        let original = String(repeating: "line of text\n", count: 400)
        try "x\n".write(to: url, atomically: true, encoding: .utf8)
        let saved = MainWindowController.backgroundSaveThreshold
        MainWindowController.backgroundSaveThreshold = 10
        defer { MainWindowController.backgroundSaveThreshold = saved }

        let controller = MainWindowController()
        let document = TextDocument(fileURL: url, text: "x\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        controller.currentEditor?.replaceAll(with: original)

        let done = expectation(description: "saved")
        controller.saveActiveDocument { done.fulfill() }
        // Typing before the write finishes: the main thread is free, the file must keep the snapshot.
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.currentEditor?.replaceSelection(with: "TYPED DURING SAVE ")
        wait(for: [done], timeout: 10)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
        XCTAssertTrue(document.isDirty, "the typed text is not on disk")
        XCTAssertTrue(document.text.hasPrefix("TYPED DURING SAVE "))
    }
}
