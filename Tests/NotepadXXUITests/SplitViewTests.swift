import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class SplitViewTests: XCTestCase {
    private func makeController(_ texts: [String]) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: texts.map { TextDocument(text: $0) }, activeIndex: 0)
        _ = controller.window
        return controller
    }

    func testStartsUnsplit() {
        XCTAssertFalse(makeController(["a"]).isSplit)
    }

    func testMoveToOtherViewMovesRatherThanCopies() {
        let controller = makeController(["a", "b"])
        controller.selectTab(at: 0)
        controller.moveToOtherViewAction(nil)

        XCTAssertTrue(controller.isSplit)
        XCTAssertEqual(controller.tabs.count, 2, "moving does not create a tab")
        XCTAssertEqual(controller.tabs(inPane: 1).count, 1)
        XCTAssertEqual(controller.tabs(inPane: 0).count, 1)
    }

    /// The whole point of clone: one buffer, two views. An edit in one must be
    /// visible in the other, so both tabs must reference the same instance.
    func testCloneSharesTheSameDocumentInstance() {
        let controller = makeController(["shared"])
        controller.selectTab(at: 0)
        controller.cloneToOtherViewAction(nil)

        XCTAssertEqual(controller.tabs.count, 2, "clone adds a tab")
        let primary = controller.tabs(inPane: 0).first?.document
        let secondary = controller.tabs(inPane: 1).first?.document
        XCTAssertTrue(primary === secondary, "both panes must share one buffer")

        primary?.text = "edited in one pane"
        XCTAssertEqual(secondary?.text, "edited in one pane")
    }

    func testCloningTwiceIsANoOp() {
        let controller = makeController(["a"])
        controller.selectTab(at: 0)
        controller.cloneToOtherViewAction(nil)
        controller.cloneToOtherViewAction(nil)
        XCTAssertEqual(controller.tabs.count, 2)
    }

    func testClosingSplitReturnsEverythingAndDropsDuplicates() {
        let controller = makeController(["a"])
        controller.selectTab(at: 0)
        controller.cloneToOtherViewAction(nil)
        XCTAssertEqual(controller.tabs.count, 2)

        controller.closeSplitAction(nil)
        XCTAssertFalse(controller.isSplit)
        XCTAssertEqual(controller.tabs.count, 1, "the clone collapses back into one tab")
    }

    func testClosingSplitKeepsDistinctDocuments() {
        let controller = makeController(["a", "b"])
        controller.selectTab(at: 1)
        controller.moveToOtherViewAction(nil)
        controller.closeSplitAction(nil)
        XCTAssertEqual(controller.tabs.count, 2, "distinct documents are not merged")
        XCTAssertFalse(controller.isSplit)
    }

    func testClosingOneCloneKeepsTheEditorForTheOther() {
        let controller = makeController(["shared"])
        controller.selectTab(at: 0)
        controller.cloneToOtherViewAction(nil)
        let document = controller.tabs[0].document

        controller.selectTab(at: 1)
        controller.closeTabAction(nil)
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertTrue(controller.tabs[0].document === document,
                      "closing one view of a cloned buffer leaves the other intact")
    }

    func testPaneAssignmentSurvivesASessionRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-split-\(UUID().uuidString)", isDirectory: true)
        let store = try SessionStore(directory: dir)
        let document = TextDocument(text: "x")
        document.paneIndex = 1
        try store.save(documents: [document], activeIndex: 0)

        let restored = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(restored.documents.first?.paneIndex, 1)
    }
}
