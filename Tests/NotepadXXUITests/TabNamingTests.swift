import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// Fifty open documents have to stay tellable apart: colliding names carry
/// their folder, long names keep their extension, and every tab carries its
/// full path in the tooltip.
@MainActor
final class TabNamingTests: XCTestCase {
    private func document(_ path: String) -> TextDocument {
        TextDocument(fileURL: URL(fileURLWithPath: path), text: "")
    }

    /// Only the documents that actually collide are qualified — qualifying
    /// every tab would add noise to names that were never ambiguous.
    func testOnlyCollidingNamesCarryTheirFolder() {
        let documents = [
            document("/project/Sources/Info.plist"),
            document("/project/Tests/Info.plist"),
            document("/project/Sources/main.swift"),
        ]
        let qualifiers = MainWindowController.qualifiers(for: documents)

        XCTAssertEqual(qualifiers[ObjectIdentifier(documents[0])], "Sources")
        XCTAssertEqual(qualifiers[ObjectIdentifier(documents[1])], "Tests")
        XCTAssertNil(qualifiers[ObjectIdentifier(documents[2])],
                     "a name nothing collides with is left alone")
    }

    /// Truncation keeps the extension, which is the part that says what the
    /// file is.
    func testLongNamesAreTruncatedInTheMiddle() {
        let shortened = TabTitle.shortened("SessionRestorationCoordinator.swift")
        XCTAssertTrue(shortened.hasSuffix(".swift"), "the extension survives: \(shortened)")
        XCTAssertTrue(shortened.hasPrefix("Session"), "and so does the start")
        XCTAssertTrue(shortened.contains("…"))
        XCTAssertLessThan(shortened.count, "SessionRestorationCoordinator.swift".count)
    }

    func testShortNamesAreLeftAlone() {
        XCTAssertEqual(TabTitle.shortened("main.swift"), "main.swift")
    }

    func testEveryTabCarriesItsFullPathAsATooltip() {
        let controller = MainWindowController()
        controller.adopt(documents: [document("/project/Sources/Info.plist")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        func descendants(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap { descendants(of: $0) }
        }
        let tabs = descendants(of: controller.tabBar).compactMap { $0 as? DSTabView }
        XCTAssertFalse(tabs.isEmpty)
        XCTAssertEqual(tabs.first?.toolTip, "/project/Sources/Info.plist")
    }
}

/// With a split open the status bar has to say which pane the caret is in.
@MainActor
final class SplitPaneStatusTests: XCTestCase {
    private func make() -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\n"), TextDocument(text: "two\n")],
                         activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1440, height: 900))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    /// Reads every label the status bar draws, as a person would read it.
    private func summary(of controller: MainWindowController) -> String {
        func labels(in view: NSView) -> [String] {
            view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
                + view.subviews.flatMap { labels(in: $0) }
        }
        return labels(in: controller.statusBar).joined(separator: " | ")
    }

    func testASinglePaneSaysNothingAboutPanes() {
        let controller = make()
        XCTAssertFalse(summary(of: controller).contains("pane"),
                       "there is only one pane, so there is nothing to say")
    }

    func testASplitReportsWhichPaneHasTheCaret() {
        let controller = make()
        controller.toggleSplitViewAction(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let summary = summary(of: controller)
        XCTAssertTrue(summary.contains("pane"), "got: \(summary)")
        XCTAssertTrue(summary.contains("of 2"), "got: \(summary)")
    }
}
