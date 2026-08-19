import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// Two panes, each with its own editor. Cloning a document into the other pane
/// used to leave the first pane empty, because one editor's view cannot be in
/// two places at once.
@MainActor
final class SplitPaneTests: XCTestCase {
    private func make(_ texts: [String] = ["one\ntwo\n"]) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: texts.map { TextDocument(text: $0) }, activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1200, height: 700))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func settle(_ controller: MainWindowController) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    func testCloningFillsBothPanes() throws {
        let controller = make()
        controller.cloneToOtherViewAction(nil)
        settle(controller)

        let panes = controller.editorSplit.arrangedSubviews
        XCTAssertEqual(panes.count, 2)
        for (index, pane) in panes.enumerated() {
            XCTAssertFalse(pane.subviews.isEmpty, "pane \(index) is empty")
        }
    }

    /// Edits reach the clone; carets do not, as the design specifies.
    func testAnEditInOnePaneReachesTheClone() throws {
        let controller = make()
        let document = try XCTUnwrap(controller.activeDocument)
        controller.cloneToOtherViewAction(nil)
        settle(controller)

        let primary = controller.editorController(for: document, inPane: 0)
        let secondary = controller.editorController(for: document, inPane: 1)
        XCTAssertFalse(primary === secondary, "each pane has its own editor")

        primary.replaceAll(with: "edited in the first pane")
        primary.onTextChange?(primary.text)

        XCTAssertEqual(secondary.text, "edited in the first pane")
    }

    /// Only the focused pane's active tab carries the accent edge.
    func testOnlyTheFocusedPanesTabIsAccented() throws {
        let controller = make(["one\n", "two\n"])
        controller.toggleSplitViewAction(nil)   // moves the active tab to pane 1
        settle(controller)

        let tabs = descendants(of: controller.tabBar).compactMap { $0 as? DSTabView }
        XCTAssertEqual(tabs.count, 2)

        let focused = tabs.filter { $0.itemForTesting.isActive && $0.itemForTesting.isInFocusedPane }
        XCTAssertEqual(focused.count, 1, "exactly one tab is in the focused pane and active")
    }

    /// The unfocused pane keeps its text but stops showing a live caret.
    func testTheUnfocusedPaneDropsItsCurrentLineTint() throws {
        let controller = make(["one\n", "two\n"])
        controller.toggleSplitViewAction(nil)
        settle(controller)

        let focusedPane = controller.tabs[controller.activeIndex].pane
        for tab in controller.tabs {
            let editor = controller.editorController(for: tab.document, inPane: tab.pane)
            XCTAssertEqual(editor.isPaneFocused, tab.pane == focusedPane,
                           "\(tab.document.displayName) in pane \(tab.pane)")
        }
    }

    /// Closing one pane's tab leaves the other pane's editor alone.
    func testClosingACloneLeavesTheOtherPaneShowing() throws {
        let controller = make()
        let document = try XCTUnwrap(controller.activeDocument)
        controller.cloneToOtherViewAction(nil)
        settle(controller)

        controller.closeTabAction(nil)
        settle(controller)

        XCTAssertFalse(controller.documents.isEmpty)
        let remaining = controller.tabs.first { $0.document === document }
        XCTAssertNotNil(remaining, "the other pane still has the document")
    }
}
