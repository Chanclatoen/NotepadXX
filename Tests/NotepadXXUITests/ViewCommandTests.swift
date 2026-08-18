import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class ViewCommandTests: XCTestCase {
    private func makeController(_ text: String = "line one\nline two\nline three\n") -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        _ = controller.window
        return controller
    }

    func testShowAllCharactersTurnsEverythingOnThenOff() {
        let controller = makeController()
        controller.toggleShowAllCharactersAction(nil)
        XCTAssertTrue(controller.showSpaces && controller.showTabs && controller.showLineEndings)
        controller.toggleShowAllCharactersAction(nil)
        XCTAssertFalse(controller.showSpaces || controller.showTabs || controller.showLineEndings)
    }

    /// With only some options on, "Show All" must turn the rest on rather than
    /// toggling the whole set off.
    func testShowAllFromAPartialStateTurnsTheRestOn() {
        let controller = makeController()
        controller.toggleShowWhitespaceAction(nil)
        XCTAssertTrue(controller.showSpaces)
        controller.toggleShowAllCharactersAction(nil)
        XCTAssertTrue(controller.showTabs && controller.showLineEndings)
    }

    func testIndividualSymbolTogglesAreIndependent() {
        let controller = makeController()
        controller.toggleShowTabsAction(nil)
        XCTAssertTrue(controller.showTabs)
        XCTAssertFalse(controller.showSpaces)
        XCTAssertFalse(controller.showLineEndings)
    }

    func testZoomClampsAtBothEnds() {
        let controller = makeController()
        for _ in 0..<200 { controller.zoomInAction(nil) }
        XCTAssertLessThanOrEqual(controller.editorFontSize, 96)
        for _ in 0..<400 { controller.zoomOutAction(nil) }
        XCTAssertGreaterThanOrEqual(controller.editorFontSize, 6)
    }

    func testZoomRestoreReturnsToDefault() {
        let controller = makeController()
        controller.zoomInAction(nil)
        controller.zoomInAction(nil)
        controller.zoomRestoreAction(nil)
        XCTAssertEqual(controller.editorFontSize, 12)
    }

    func testBookmarkToggleAndNavigation() {
        let controller = makeController()
        controller.currentEditor?.goToLine(1)
        controller.toggleBookmarkAction(nil)
        controller.currentEditor?.goToLine(3)
        controller.toggleBookmarkAction(nil)

        guard let document = controller.activeDocument else { return XCTFail("no document") }
        XCTAssertEqual(controller.bookmarks[document.id]?.lines, [0, 2])

        controller.currentEditor?.goToLine(1)
        controller.nextBookmarkAction(nil)
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 3)
    }

    func testClearBookmarks() {
        let controller = makeController()
        controller.toggleBookmarkAction(nil)
        controller.clearBookmarksAction(nil)
        guard let document = controller.activeDocument else { return XCTFail("no document") }
        XCTAssertTrue(controller.bookmarks[document.id]?.isEmpty ?? false)
    }

    func testRemoveBookmarkedLinesEditsTheDocument() {
        let controller = makeController("a\nb\nc\n")
        controller.currentEditor?.goToLine(2)
        controller.toggleBookmarkAction(nil)
        controller.removeBookmarkedLinesAction(nil)
        XCTAssertEqual(controller.activeDocument?.text, "a\nc\n")
    }

    func testDistractionFreeHidesAndRestoresChrome() {
        let controller = makeController()
        controller.dockHost?.show("functionList")
        controller.toggleDistractionFreeAction(nil)
        XCTAssertTrue(controller.tabBar.isHidden)
        XCTAssertTrue(controller.statusBar.isHidden)
        XCTAssertFalse(controller.dockHost?.isVisible("functionList") ?? true)

        controller.toggleDistractionFreeAction(nil)
        XCTAssertFalse(controller.tabBar.isHidden)
        XCTAssertTrue(controller.dockHost?.isVisible("functionList") ?? false,
                      "panels that were open come back")
    }

    func testAlwaysOnTopTogglesWindowLevel() {
        let controller = makeController()
        controller.toggleAlwaysOnTopAction(nil)
        XCTAssertEqual(controller.window?.level, .floating)
        controller.toggleAlwaysOnTopAction(nil)
        XCTAssertEqual(controller.window?.level, .normal)
    }
}
