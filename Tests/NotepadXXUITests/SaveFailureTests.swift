import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// A save that fails without saying so is how an editor loses work: the user
/// presses Command-S, sees nothing happen, and closes the file.
@MainActor
final class SaveFailureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainWindowController.presentsAlerts = false
    }

    override func tearDown() {
        MainWindowController.presentsAlerts = true
        super.tearDown()
    }

    private func controller(with document: TextDocument) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [document], activeIndex: 0)
        return controller
    }

    /// A file that cannot be written produces a message naming the document.
    func testAFailedSaveIsReported() {
        let document = TextDocument(fileURL: URL(fileURLWithPath: "/System/nope/work.txt"),
                                    text: "work")
        document.text = "edited work"
        let controller = controller(with: document)

        controller.saveDocumentAction(nil)

        let reported = controller.lastReportedError
        XCTAssertNotNil(reported, "the save failed and the user was told nothing")
        XCTAssertTrue(reported?.message.contains("work.txt") == true,
                      "the message should name the document: \(reported?.message ?? "")")
        XCTAssertTrue(document.isDirty, "the document must stay dirty")
    }

    /// Text the encoding cannot represent is reported with the way out of it.
    func testAnUnencodableSaveExplainsWhatToDo() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let document = TextDocument(fileURL: url, text: "plain", encoding: FileEncoding(.ascii))
        document.text = "emoji 😀"
        let controller = controller(with: document)

        controller.saveDocumentAction(nil)

        let detail = try XCTUnwrap(controller.lastReportedError?.detail)
        XCTAssertTrue(detail.contains("UTF-8"), "it should point at the fix: \(detail)")
    }

    /// The gutter's change marks must not be moved to "saved" for a file that
    /// was never written — that is a false statement about the user's work.
    func testAFailedSaveDoesNotMarkChangesAsSaved() {
        let document = TextDocument(fileURL: URL(fileURLWithPath: "/System/nope/work.txt"),
                                    text: "one\ntwo")
        let controller = controller(with: document)
        let editor = controller.editorController(for: document)
        editor.load(text: "one\ntwo")
        // Drive a real edit so the change bar is populated the way typing does.
        editor.textView.string = "one\nedited"
        editor.textView(editor.textView, didReplaceContentsIn: NSRange(location: 4, length: 3),
                        with: "edited")
        document.text = "one\nedited"

        let changedBefore = editor.changeHistory.modifiedLines
        controller.saveDocumentAction(nil)

        XCTAssertEqual(editor.changeHistory.modifiedLines, changedBefore,
                       "the change bar was moved to saved for a file that was not written")
        XCTAssertTrue(editor.changeHistory.savedLines.isEmpty,
                      "nothing was saved, so no line may be marked as saved")
    }

    /// Save All reports the file it could not write and still saves the others.
    func testSaveAllKeepsGoingAndStillReports() throws {
        let good = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        defer { try? FileManager.default.removeItem(at: good) }

        let broken = TextDocument(fileURL: URL(fileURLWithPath: "/System/nope/a.txt"), text: "a")
        broken.text = "a edited"
        let fine = TextDocument(fileURL: good, text: "b")
        fine.text = "b edited"

        let controller = MainWindowController()
        controller.adopt(documents: [broken, fine], activeIndex: 0)
        controller.saveAllAction(nil)

        XCTAssertNotNil(controller.lastReportedError, "the unwritable file was not reported")
        XCTAssertFalse(fine.isDirty, "the writable document should still have been saved")
        XCTAssertEqual(try String(contentsOf: good, encoding: .utf8), "b edited")
    }
}
