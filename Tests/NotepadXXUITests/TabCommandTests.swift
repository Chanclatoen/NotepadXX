import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class TabCommandTests: XCTestCase {
    private func makeController(_ names: [String]) -> MainWindowController {
        let controller = MainWindowController()
        let documents = names.map { name -> TextDocument in
            let document = TextDocument(text: "x")
            document.untitledName = name
            return document
        }
        controller.adopt(documents: documents, activeIndex: 0)
        _ = controller.window
        return controller
    }

    private func titles(_ controller: MainWindowController) -> [String] {
        controller.tabs.map { $0.document.displayName }
    }

    func testPinningMovesATabToTheFront() {
        let controller = makeController(["a", "b", "c"])
        controller.selectTab(at: 2)
        controller.togglePinTabAction(nil)
        XCTAssertEqual(titles(controller).first, "c")
    }

    func testUnpinningRestoresItToTheUnpinnedGroup() {
        let controller = makeController(["a", "b", "c"])
        controller.selectTab(at: 2)
        controller.togglePinTabAction(nil)
        controller.togglePinTabAction(nil)
        XCTAssertFalse(controller.tabs.contains { controller.attributes(for: $0.document).isPinned })
    }

    /// Dragging an unpinned tab to the far left must stop after the pinned ones.
    func testUnpinnedTabCannotBeDraggedAheadOfAPinnedTab() {
        let controller = makeController(["a", "b", "c"])
        controller.selectTab(at: 0)
        controller.togglePinTabAction(nil)   // "a" is pinned and first

        controller.moveTab(from: 2, to: 0)
        XCTAssertEqual(titles(controller).first, "a", "the pinned tab keeps the first slot")
    }

    func testSortTabsByName() {
        let controller = makeController(["c", "a", "b"])
        controller.sortTabsByNameAction(nil)
        XCTAssertEqual(titles(controller), ["a", "b", "c"])
    }

    func testSortKeepsPinnedTabsFirst() {
        let controller = makeController(["c", "a", "b"])
        controller.selectTab(at: 0)          // "c"
        controller.togglePinTabAction(nil)
        controller.sortTabsByNameAction(nil)
        XCTAssertEqual(titles(controller).first, "c", "pinned stays left despite sorting")
        XCTAssertEqual(Array(titles(controller).dropFirst()), ["a", "b"])
    }

    func testCloseAllButThis() {
        let controller = makeController(["a", "b", "c"])
        controller.selectTab(at: 1)
        controller.closeOtherTabsAction(nil)
        XCTAssertEqual(titles(controller), ["b"])
    }

    func testCloseToTheLeftAndRight() {
        let left = makeController(["a", "b", "c"])
        left.selectTab(at: 1)
        left.closeTabsToTheLeftAction(nil)
        XCTAssertEqual(titles(left), ["b", "c"])

        let right = makeController(["a", "b", "c"])
        right.selectTab(at: 1)
        right.closeTabsToTheRightAction(nil)
        XCTAssertEqual(titles(right), ["a", "b"])
    }

    func testCloseAllLeavesOneUntitledBuffer() {
        let controller = makeController(["a", "b"])
        controller.closeAllTabsAction(nil)
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertTrue(controller.tabs[0].document.isUntitled)
    }

    func testReadOnlyTogglePropagatesToTheEditor() {
        let controller = makeController(["a"])
        controller.toggleReadOnlyAction(nil)
        XCTAssertTrue(controller.activeDocument?.isReadOnly ?? false)
        XCTAssertEqual(controller.currentEditor?.isEditable, false)
        controller.toggleReadOnlyAction(nil)
        XCTAssertEqual(controller.currentEditor?.isEditable, true)
    }

    func testTabColourIsRemembered() {
        let controller = makeController(["a"])
        guard let document = controller.activeDocument else { return XCTFail("no document") }
        var attributes = controller.attributes(for: document)
        attributes.colour = .blue
        controller.setAttributes(attributes, for: document)
        XCTAssertEqual(controller.attributes(for: document).colour, .blue)
        XCTAssertNotNil(controller.colour(for: attributes))
    }
}

@MainActor
final class FileCommandTests: XCTestCase {
    private func tempFile(_ name: String, _ contents: String = "original") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testReloadFromDiskPicksUpExternalChanges() throws {
        let url = try tempFile("r.txt", "first")
        let controller = MainWindowController()
        _ = controller.window
        XCTAssertTrue(controller.openOrFocus(url: url))

        try Data("second".utf8).write(to: url)
        controller.reloadFromDiskAction(nil)
        XCTAssertEqual(controller.activeDocument?.text, "second")
        XCTAssertFalse(controller.activeDocument?.isDirty ?? true)
    }

    func testSaveACopyDoesNotRetargetTheOpenDocument() throws {
        let url = try tempFile("orig.txt", "body")
        let controller = MainWindowController()
        _ = controller.window
        controller.openOrFocus(url: url)

        let document = try XCTUnwrap(controller.activeDocument)
        XCTAssertEqual(document.fileURL, url, "the open document still points at the original")
    }

    /// An unsaved edit must never be silently discarded by a reload.
    func testSilentReloadSkipsDirtyDocuments() throws {
        let url = try tempFile("d.txt", "disk")
        let document = try TextDocument.load(contentsOf: url)
        document.text = "my unsaved work"

        let controller = MainWindowController()
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        try controller.preferencesStore?.update { $0.reloadChangedFilesSilently = true }

        try Data("changed on disk".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path
        )
        // Not calling checkForExternalChanges here: it would show a modal.
        XCTAssertTrue(document.hasChangedOnDisk())
        XCTAssertTrue(document.isDirty, "a dirty document is never silently reloaded")
    }

    func testAcceptOnDiskRevisionStopsRepeatedPrompts() throws {
        let url = try tempFile("a.txt", "one")
        let document = try TextDocument.load(contentsOf: url)
        try Data("two".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path
        )
        XCTAssertTrue(document.hasChangedOnDisk())
        document.acceptOnDiskRevision()
        XCTAssertFalse(document.hasChangedOnDisk(), "the same change is not reported twice")
    }

    func testRelocateUpdatesThePathWithoutTouchingContent() throws {
        let url = try tempFile("before.txt", "keep me")
        let document = try TextDocument.load(contentsOf: url)
        let moved = url.deletingLastPathComponent().appendingPathComponent("after.txt")
        try FileManager.default.moveItem(at: url, to: moved)

        document.relocate(to: moved)
        XCTAssertEqual(document.fileURL, moved)
        XCTAssertEqual(document.text, "keep me")
        XCTAssertEqual(document.displayName, "after.txt")
    }
}
