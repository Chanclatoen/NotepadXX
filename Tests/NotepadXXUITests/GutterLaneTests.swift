import XCTest
import AppKit
@testable import NotepadXXEditor
import NotepadXXDesign

/// The design fixes the gutter's lane widths so toggling a lane never reflows
/// the code. These check the observable geometry, not the flags that set it.
@MainActor
final class GutterLaneTests: XCTestCase {
    private func makeGutter(lines: Int = 12) -> (GutterView, EditorViewController) {
        let controller = EditorViewController()
        // Size and lay out the editor: line positions only exist once the text
        // has been laid out, and an unsized view reports none.
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        controller.view.layoutSubtreeIfNeeded()
        controller.load(text: (1...lines).map { "line \($0)" }.joined(separator: "\n"))
        controller.view.layoutSubtreeIfNeeded()
        let gutter = try! XCTUnwrap(controller.gutterView)
        return (gutter, controller)
    }

    func testAllFourLanesAddUpToTheGutterWidth() {
        let (gutter, _) = makeGutter()
        let total = gutter.requiredWidth()
        XCTAssertEqual(total,
                       DS.Metric.gutterBookmark + DS.Metric.gutterNumber
                           + DS.Metric.gutterChangeBar + DS.Metric.gutterFolding,
                       accuracy: 0.5)
    }

    func testHidingALaneRemovesExactlyThatLanesWidth() {
        let (gutter, _) = makeGutter()
        let full = gutter.requiredWidth()

        gutter.showBookmarks = false
        XCTAssertEqual(gutter.requiredWidth(), full - DS.Metric.gutterBookmark, accuracy: 0.5)

        gutter.showBookmarks = true
        gutter.showFoldMargin = false
        XCTAssertEqual(gutter.requiredWidth(), full - DS.Metric.gutterFolding, accuracy: 0.5)

        gutter.showFoldMargin = true
        gutter.showChangeHistory = false
        XCTAssertEqual(gutter.requiredWidth(), full - DS.Metric.gutterChangeBar, accuracy: 0.5)
    }

    /// The number lane holds its design width for ordinary documents, and only
    /// grows once the digits genuinely need more room.
    func testNumberLaneGrowsOnlyForVeryLongDocuments() {
        let (small, _) = makeGutter(lines: 10)
        XCTAssertEqual(small.requiredWidth(),
                       DS.Metric.gutterBookmark + DS.Metric.gutterNumber
                           + DS.Metric.gutterChangeBar + DS.Metric.gutterFolding,
                       accuracy: 0.5)

        let (large, _) = makeGutter(lines: 2000)
        XCTAssertGreaterThan(large.requiredWidth(), small.requiredWidth(),
                             "a four-digit document needs a wider number lane")
    }

    func testClickingTheBookmarkLaneReportsTheLine() {
        let (gutter, _) = makeGutter()
        var toggled: [Int] = []
        gutter.onToggleBookmark = { toggled.append($0) }
        gutter.onToggleFold = { _ in XCTFail("a bookmark-lane click is not a fold click") }

        // Click inside the bookmark lane on the first line.
        let point = NSPoint(x: DS.Metric.gutterBookmark / 2, y: 4)
        gutter.simulateClick(at: point)
        XCTAssertEqual(toggled, [0])
    }
}

private extension GutterView {
    /// mouseDown converts from window coordinates, so drive it the same way a
    /// real click would arrive.
    func simulateClick(at point: NSPoint) {
        let inWindow = convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: inWindow, modifierFlags: [],
            timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        mouseDown(with: event)
    }
}
