import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// The incremental strip is the only place incremental search speaks, so what
/// it says has to be right.
@MainActor
final class IncrementalSearchTests: XCTestCase {
    private func make(_ text: String) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1100, height: 720))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func labels(in view: NSView) -> [String] {
        view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
            + view.subviews.flatMap { labels(in: $0) }
    }

    func testTheStripIsTheHeightTheDesignSpecifies() {
        XCTAssertEqual(IncrementalSearchBar.height, 26)
    }

    func testItReportsWhichMatchOfHowMany() throws {
        let controller = make("alpha one\nalpha two\nalpha three\n")
        controller.incrementalSearchAction(nil)
        let bar = try XCTUnwrap(controller.incrementalBar)

        bar.setQuery("alpha")
        XCTAssertTrue(labels(in: bar).contains { $0.contains("1 of 3") },
                      "got: \(labels(in: bar))")
    }

    /// A search that finds nothing says so in words.
    func testItSaysWhenThereAreNoMatches() throws {
        let controller = make("alpha\n")
        controller.incrementalSearchAction(nil)
        let bar = try XCTUnwrap(controller.incrementalBar)

        bar.setQuery("zzz")
        XCTAssertTrue(labels(in: bar).contains { $0.contains("No matches") },
                      "got: \(labels(in: bar))")
    }

    /// Escape restores the caret: an abandoned search leaves nothing behind.
    func testEscapeReturnsTheCaretToWhereItStarted() throws {
        let controller = make("alpha one\nalpha two\n")
        controller.currentEditor?.selectedRange = NSRange(location: 6, length: 0)
        controller.incrementalSearchAction(nil)
        let bar = try XCTUnwrap(controller.incrementalBar)

        bar.setQuery("two")
        XCTAssertNotEqual(controller.currentEditor?.selectedRange.location, 6, "the caret moved")

        bar.onCancel?()
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 6,
                       "and Escape put it back")
    }

    /// Changing an option re-runs the search on what is already typed.
    func testTogglingAnOptionRefreshesTheSearch() throws {
        let controller = make("Alpha\nalpha\n")
        controller.incrementalSearchAction(nil)
        let bar = try XCTUnwrap(controller.incrementalBar)

        var queries: [String] = []
        let original = bar.onQueryChanged
        bar.onQueryChanged = { query in
            queries.append(query)
            original?(query)
        }
        bar.setQuery("alpha")
        bar.onOptionsChanged?()
        XCTAssertEqual(queries, ["alpha", "alpha"], "the option change re-ran the search")
    }
}
