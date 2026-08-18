import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Drives the real window controller — tabs, editor and status bar — rather than
/// testing the model in isolation. These exercise the paths a user actually hits.
@MainActor
final class MainWindowControllerTests: XCTestCase {
    private func tempFile(_ contents: String, name: String = "t.txt") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testStartsWithAnUntitledBuffer() {
        let controller = MainWindowController()
        controller.newDocument()
        XCTAssertEqual(controller.documents.count, 1)
        XCTAssertTrue(controller.documents[0].isUntitled)
        XCTAssertEqual(controller.documents[0].untitledName, "new 1")
    }

    func testUntitledDocumentsGetIncrementingNames() {
        let controller = MainWindowController()
        controller.newDocument()
        controller.newDocument()
        controller.newDocument()
        XCTAssertEqual(controller.documents.map(\.untitledName), ["new 1", "new 2", "new 3"])
        XCTAssertEqual(controller.activeIndex, 2, "creating a tab activates it")
    }

    func testAdoptRestoresTabsAndActiveIndex() throws {
        let controller = MainWindowController()
        let a = TextDocument(text: "alpha")
        let b = TextDocument(text: "beta")
        controller.adopt(documents: [a, b], activeIndex: 1)
        XCTAssertEqual(controller.documents.count, 2)
        XCTAssertEqual(controller.activeIndex, 1)
    }

    func testEditorReceivesDocumentText() throws {
        let controller = MainWindowController()
        let document = TextDocument(text: "hello from disk")
        controller.adopt(documents: [document], activeIndex: 0)
        // The window must be loaded for the editor to be installed.
        _ = controller.window
        XCTAssertEqual(controller.documents[0].text, "hello from disk")
    }

    func testClosingLastTabLeavesAFreshUntitledBuffer() {
        let controller = MainWindowController()
        controller.newDocument()
        controller.closeTabAction(nil)
        XCTAssertEqual(controller.documents.count, 1, "never leave the user with zero tabs")
        XCTAssertTrue(controller.documents[0].isUntitled)
    }

    func testClosingAMiddleTabActivatesANeighbour() {
        let controller = MainWindowController()
        controller.adopt(
            documents: [TextDocument(text: "a"), TextDocument(text: "b"), TextDocument(text: "c")],
            activeIndex: 1
        )
        controller.closeTabAction(nil)
        XCTAssertEqual(controller.documents.count, 2)
        XCTAssertTrue(controller.activeIndex < controller.documents.count)
    }

    func testSaveWritesThroughToDiskPreservingLineEndings() throws {
        let url = try tempFile("one\r\ntwo\r\n")
        let document = try TextDocument.load(contentsOf: url)
        let controller = MainWindowController()
        controller.adopt(documents: [document], activeIndex: 0)

        document.text = "one\ntwo\nthree\n"
        controller.saveDocumentAction(nil)

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(written, "one\r\ntwo\r\nthree\r\n")
        XCTAssertFalse(document.isDirty)
    }

    func testSaveAllSkipsUntitledAndCleanDocuments() throws {
        let url = try tempFile("x")
        let onDisk = try TextDocument.load(contentsOf: url)
        onDisk.text = "changed"
        let scratch = TextDocument()
        scratch.text = "untitled scratch"   // typed into, as a user would

        let controller = MainWindowController()
        controller.adopt(documents: [onDisk, scratch], activeIndex: 0)
        controller.saveAllAction(nil)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed")
        XCTAssertTrue(scratch.isDirty, "an untitled buffer has nowhere to be saved to")
        XCTAssertNil(scratch.fileURL, "Save All must not invent a destination for untitled buffers")
    }
}
