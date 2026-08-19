import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The design's rule for secondary surfaces: anything acting on one document is
/// a sheet, and every command dialog is modeless, remembers its values, commits
/// on Return and closes on Escape.
@MainActor
final class DialogBehaviourTests: XCTestCase {
    private func make(_ text: String = (1...50).map { "line \($0)" }.joined(separator: "\n"))
        -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1100, height: 720))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    // MARK: Go to

    func testGoToIsAModelessPanelNotAModalDialog() {
        let controller = make()
        controller.goToLineDialogAction(nil)
        let panel = controller.installedGoToPanel?.window as? NSPanel
        XCTAssertNotNil(panel, "Go to is a utility panel")
        XCTAssertFalse(panel?.isSheet ?? true, "it is not modal on the document")
        XCTAssertTrue(panel?.isFloatingPanel ?? false)
    }

    func testGoToMovesTheCaretToTheLine() {
        let controller = make()
        controller.goToLineDialogAction(nil)
        let panel = try! XCTUnwrap(controller.installedGoToPanel)

        XCTAssertEqual(panel.onGo?(.line, 12), true)
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 12)
    }

    func testGoToRefusesALineOutsideTheDocument() {
        let controller = make()
        controller.goToLineDialogAction(nil)
        let panel = try! XCTUnwrap(controller.installedGoToPanel)

        XCTAssertEqual(panel.onGo?(.line, 9_999), false, "out of range is refused, not clamped silently")
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 1, "the caret did not move")
    }

    func testGoToOffsetMovesToTheCharacterPosition() {
        let controller = make("abcdefghij")
        controller.goToLineDialogAction(nil)
        let panel = try! XCTUnwrap(controller.installedGoToPanel)

        XCTAssertEqual(panel.onGo?(.offset, 4), true)
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 4)
    }

    /// Reopening keeps the panel, so its last value is still there.
    func testGoToReusesOnePanel() {
        let controller = make()
        controller.goToLineDialogAction(nil)
        let first = controller.installedGoToPanel
        controller.goToLineDialogAction(nil)
        XCTAssertTrue(controller.installedGoToPanel === first)
    }

    // MARK: Document prompts

    /// A prompt about one document must not be a free-floating alert.
    func testAnExternalChangePromptIsASheetOnTheWindow() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-sheet-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try "first".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        let document = try TextDocument.load(contentsOf: url)
        controller.adopt(documents: [document], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.showWindow(nil)

        // Change the file behind the app's back.
        try "second".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(document.hasChangedOnDisk())

        controller.promptForExternalChanges([document])
        // A sheet is attached to the window; a modal alert would have blocked
        // this test instead of returning.
        XCTAssertNotNil(controller.window?.attachedSheet, "the prompt is attached to the window")
        controller.window?.attachedSheet.map { controller.window?.endSheet($0) }
        controller.close()
    }

    /// The comparison copy must never be able to overwrite the file it was
    /// opened to compare against.
    func testTheOnDiskComparisonCopyIsReadOnly() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-compare-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try "on disk".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        let document = try TextDocument.load(contentsOf: url)
        controller.adopt(documents: [document], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let onDisk = try TextDocument.load(contentsOf: url)
        onDisk.isReadOnly = true
        controller.openBeside(onDisk)

        XCTAssertEqual(controller.documents.count, 2)
        XCTAssertTrue(controller.documents.last?.isReadOnly ?? false)
        XCTAssertTrue(controller.isSplit, "it opens beside, in the other pane")
    }
}

/// Prompts that concern one document belong to that document's window.
@MainActor
final class DocumentPromptsAreSheetsTests: XCTestCase {
    private func makeWithFile() throws -> (MainWindowController, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-prompt-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try "content".write(to: url, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.adopt(documents: [try TextDocument.load(contentsOf: url)], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1000, height: 700))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.showWindow(nil)
        return (controller, url)
    }

    private func expectSheet(_ controller: MainWindowController, _ name: String) {
        XCTAssertNotNil(controller.window?.attachedSheet, "\(name) is not attached to the window")
        controller.window?.attachedSheet.map { controller.window?.endSheet($0) }
    }

    func testRenameAsksInASheet() throws {
        let (controller, url) = try makeWithFile()
        defer { try? FileManager.default.removeItem(at: url); controller.close() }
        controller.renameFileAction(nil)
        expectSheet(controller, "Rename")
    }

    func testMoveToTrashConfirmsInASheet() throws {
        let (controller, url) = try makeWithFile()
        defer { try? FileManager.default.removeItem(at: url); controller.close() }
        controller.moveToTrashAction(nil)
        expectSheet(controller, "Move to Trash")
    }

    func testReloadWithUnsavedEditsConfirmsInASheet() throws {
        let (controller, url) = try makeWithFile()
        defer { try? FileManager.default.removeItem(at: url); controller.close() }
        controller.currentEditor?.replaceAll(with: "edited")
        controller.activeDocument?.text = "edited"
        controller.reloadFromDiskAction(nil)
        expectSheet(controller, "Reload")
    }

    /// Saving a session is about this window's documents, so it asks here.
    func testSaveSessionAsksInASheet() throws {
        let (controller, url) = try makeWithFile()
        defer { try? FileManager.default.removeItem(at: url); controller.close() }
        controller.saveSessionAction(nil)
        expectSheet(controller, "Save Session As")
    }
}
