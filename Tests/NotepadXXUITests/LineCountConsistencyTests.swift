import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Three places count lines: the gutter, the status bar, and LineOperations.
/// If they disagree, the number under the caret contradicts the number in the
/// margin, and a "go to last line" lands in the wrong place.
@MainActor
final class LineCountConsistencyTests: XCTestCase {
    private func counts(for text: String) -> (gutter: Int, status: Int, split: Int) {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 900, height: 600))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let gutter = controller.currentEditor?.lineCount ?? -1
        let status = text.isEmpty ? 1 : LineEnding.counts(in: text).lf + 1
        let (lines, _) = LineOperations.split(text)
        return (gutter, status, lines.count)
    }

    /// A file ending in a newline: the editor shows an empty final line, and
    /// every counter should agree about whether it exists.
    func testTrailingNewlineCountsAgree() {
        let result = counts(for: "one\ntwo\nthree\n")
        XCTAssertEqual(result.gutter, result.status,
                       "gutter says \(result.gutter), status bar says \(result.status)")
    }

    func testNoTrailingNewlineCountsAgree() {
        let result = counts(for: "one\ntwo\nthree")
        XCTAssertEqual(result.gutter, result.status,
                       "gutter says \(result.gutter), status bar says \(result.status)")
    }

    func testEmptyDocumentIsOneLine() {
        let result = counts(for: "")
        XCTAssertEqual(result.gutter, 1)
        XCTAssertEqual(result.status, 1)
    }

    /// Go to Line must reach the last line the gutter shows.
    func testGoToTheLastLineTheGutterShows() throws {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\ntwo\nthree\n")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 900, height: 600))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(controller.currentEditor)
        let last = editor.lineCount
        editor.goToLine(last)
        XCTAssertEqual(editor.caretPosition().line, last,
                       "asked for line \(last), landed on \(editor.caretPosition().line)")
    }
}
