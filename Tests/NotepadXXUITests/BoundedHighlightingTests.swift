import XCTest
import AppKit
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Highlighting is what makes a large file feel instant or feel broken. It has
/// to stay proportional to the window, never to the document.
@MainActor
final class BoundedHighlightingTests: XCTestCase {
    private func editor(lines: Int) -> EditorViewController {
        let controller = EditorViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        controller.setLanguage(LanguageRegistry.shared.all.first { $0.blockCommentOpen == "/*" })
        controller.load(text: (0..<lines).map { "int value_\($0) = \($0);" }.joined(separator: "\n"))
        return controller
    }

    /// Loading is the case that used to lex the whole document: with no layout
    /// yet, the viewport's lower edge maps to no offset, and the fallback was
    /// the end of the file.
    func testLoadingALargeDocumentHighlightsOnlyAWindowOfIt() throws {
        let controller = editor(lines: 200_000)
        let range = try XCTUnwrap(controller.lastHighlightedLineRange,
                                  "loading should have highlighted something")
        XCTAssertLessThanOrEqual(range.count, EditorViewController.maximumLinesPerHighlightPass,
                                 "one pass lexed \(range.count) lines")
    }

    /// And the ceiling holds after layout has run, too.
    func testTheCeilingHoldsAfterLayout() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let controller = editor(lines: 200_000)
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()
        controller.highlightVisibleRegion()

        let range = try XCTUnwrap(controller.lastHighlightedLineRange)
        XCTAssertLessThanOrEqual(range.count, EditorViewController.maximumLinesPerHighlightPass)
    }

    /// A small document is still highlighted in full — the bound must not turn
    /// into a limit on ordinary files.
    func testASmallDocumentIsHighlightedEntirely() throws {
        let controller = editor(lines: 40)
        let range = try XCTUnwrap(controller.lastHighlightedLineRange)
        XCTAssertEqual(range.lowerBound, 0)
        XCTAssertGreaterThanOrEqual(range.upperBound, 39,
                                    "a 40-line file should be covered in one pass")
    }
}
