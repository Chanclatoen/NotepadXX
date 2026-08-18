import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Opening the same file twice would give two tabs editing one file, where
/// saving one silently discards the other's edits. This is the guard.
@MainActor
final class OpenOrFocusTests: XCTestCase {
    private func tempFile(_ name: String, _ contents: String = "x") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testOpeningTheSameFileTwiceFocusesRatherThanDuplicates() throws {
        let url = try tempFile("a.txt")
        let controller = MainWindowController()
        _ = controller.window

        XCTAssertTrue(controller.openOrFocus(url: url))
        XCTAssertEqual(controller.documents.count, 1)

        XCTAssertTrue(controller.openOrFocus(url: url))
        XCTAssertEqual(controller.documents.count, 1, "second open focuses the existing tab")
        XCTAssertEqual(controller.activeIndex, 0)
    }

    func testSymlinkedPathsResolveToTheSameTab() throws {
        let url = try tempFile("b.txt")
        // /var is a symlink to /private/var, so the same file has two spellings.
        let resolved = url.resolvingSymlinksInPath()
        let controller = MainWindowController()
        _ = controller.window

        controller.openOrFocus(url: url)
        controller.openOrFocus(url: resolved)
        XCTAssertEqual(controller.documents.count, 1,
                       "two spellings of one path must not open two tabs")
    }

    func testDifferentFilesOpenSeparateTabs() throws {
        let first = try tempFile("one.txt")
        let second = try tempFile("two.txt")
        let controller = MainWindowController()
        _ = controller.window

        controller.openOrFocus(url: first)
        controller.openOrFocus(url: second)
        XCTAssertEqual(controller.documents.count, 2)
        XCTAssertEqual(controller.activeIndex, 1, "the newly opened file is focused")
    }

    func testMissingFileReportsFailureAndOpensNothing() {
        let controller = MainWindowController()
        _ = controller.window
        let before = controller.documents.count
        XCTAssertFalse(controller.openOrFocus(url: URL(fileURLWithPath: "/nope/missing.txt")))
        XCTAssertEqual(controller.documents.count, before)
    }

    func testMoveToColumnClampsToLineLength() throws {
        let controller = MainWindowController()
        let document = TextDocument(text: "ab\nlonger line\n")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window

        controller.currentEditor?.moveToColumn(99, onLine: 1)
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 1)
        XCTAssertLessThanOrEqual(controller.currentEditor?.caretPosition().column ?? 0, 3,
                                 "an out-of-range column stops at the end of the line")
    }
}
