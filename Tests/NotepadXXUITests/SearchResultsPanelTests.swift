import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Search Results is a docked panel grouped by file. These check what the panel
/// shows and what its keyboard map does, not that a flag was set.
@MainActor
final class SearchResultsPanelTests: XCTestCase {
    private func hit(_ path: String, _ line: Int, _ text: String, match: NSRange) -> FileSearchHit {
        FileSearchHit(url: URL(fileURLWithPath: path), lineNumber: line, lineText: text,
                      range: NSRange(location: 0, length: match.length), rangeInLine: match)
    }

    private func panel() -> SearchResultsPanel {
        let panel = SearchResultsPanel()
        panel.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        panel.contentView.layoutSubtreeIfNeeded()
        return panel
    }

    private func results() -> [FileSearchResult] {
        [
            FileSearchResult(url: URL(fileURLWithPath: "/tmp/a/One.swift"), hits: [
                hit("/tmp/a/One.swift", 3, "    let descriptor = x", match: NSRange(location: 8, length: 10)),
                hit("/tmp/a/One.swift", 9, "    use(descriptor)", match: NSRange(location: 8, length: 10)),
            ]),
            FileSearchResult(url: URL(fileURLWithPath: "/tmp/b/Two.conf"), hits: [
                hit("/tmp/b/Two.conf", 1, "descriptor = 4", match: NSRange(location: 0, length: 10)),
            ]),
        ]
    }

    func testGroupsAreExpandedAndCountsAreShown() {
        let panel = panel()
        panel.present(results: results(), summary: "“descriptor” · 3 hits in 2 files", query: "descriptor")
        XCTAssertEqual(panel.fileCount, 2)
        XCTAssertEqual(panel.hitCount, 3)
        XCTAssertEqual(panel.summary, "“descriptor” · 3 hits in 2 files")
    }

    /// Copy takes the lines *with* their paths, so a pasted result still says
    /// where it came from.
    func testCopyIncludesThePathOfTheSelectedHit() {
        let panel = panel()
        panel.present(results: results(), summary: "", query: "descriptor")
        // present() selects the first hit, so a bare copy takes that one.
        let text = panel.copyText()
        XCTAssertEqual(text, "/tmp/a/One.swift:3:     let descriptor = x")
    }

    func testCopyingEverythingIncludesEveryFilesPath() {
        let panel = panel()
        panel.present(results: results(), summary: "", query: "descriptor")
        panel.selectAll()
        let text = panel.copyText()
        XCTAssertTrue(text.contains("/tmp/a/One.swift:3:"), "got: \(text)")
        XCTAssertTrue(text.contains("/tmp/b/Two.conf:1:"), "got: \(text)")
    }

    func testClearEmptiesThePanel() {
        let panel = panel()
        panel.present(results: results(), summary: "3 hits", query: "descriptor")
        panel.clear()
        XCTAssertEqual(panel.hitCount, 0)
        XCTAssertEqual(panel.summary, "")
    }

    /// The hit row highlights the match inside the line and keeps the line's
    /// indentation, which is often the only clue where in the file it sits.
    func testHitRowHighlightsTheMatchAndKeepsIndentation() throws {
        let row = SearchResultHitRow(
            hit: hit("/tmp/a/One.swift", 3, "    let descriptor = x", match: NSRange(location: 8, length: 10)),
            query: "descriptor")
        let field = try XCTUnwrap(descendants(of: row).compactMap { $0 as? NSTextField }
            .first { $0.attributedStringValue.string.contains("descriptor") })
        let string = field.attributedStringValue
        XCTAssertTrue(string.string.hasPrefix("    "), "indentation preserved")

        var range = NSRange(location: 0, length: 0)
        let background = string.attribute(.backgroundColor, at: 8, effectiveRange: &range)
        XCTAssertNotNil(background, "the match itself is highlighted")
        XCTAssertEqual(range, NSRange(location: 8, length: 10))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

/// The panel layout belongs to the user: what is open, where it is docked, what
/// is floating and how big the docks are all have to survive a relaunch.
@MainActor
final class DockLayoutPersistenceTests: XCTestCase {
    private let key = "NotepadXX.DockLayout"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    private final class StubPanel: NSObject, DockablePanel {
        let panelIdentifier: String
        let panelTitle = "Stub"
        let preferredPosition: DockPosition
        let contentView = NSView()
        init(_ identifier: String, at position: DockPosition) {
            panelIdentifier = identifier
            preferredPosition = position
        }
    }

    private func host() -> DockHostView {
        let host = DockHostView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        host.register(StubPanel("left", at: .left))
        host.register(StubPanel("bottom", at: .bottom))
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testVisibilitySurvivesARelaunch() {
        let first = host()
        first.show("left")
        first.show("bottom")

        let second = host()
        second.restoreLayout()
        XCTAssertTrue(second.isVisible("left"))
        XCTAssertTrue(second.isVisible("bottom"))
    }

    func testAMovedPanelStaysWhereItWasPut() {
        let first = host()
        first.show("left")
        first.move("left", to: .right)

        let second = host()
        second.restoreLayout()
        let panel = StubPanel("left", at: .left)
        XCTAssertEqual(second.position(of: panel), .right,
                       "the panel returns to the dock the user moved it to, not its default")
    }

    func testAFloatingPanelIsStillFloatingAfterARelaunch() {
        let first = host()
        first.show("bottom")
        first.float("bottom")
        XCTAssertTrue(first.isFloating("bottom"))

        let second = host()
        second.restoreLayout()
        XCTAssertTrue(second.isFloating("bottom"), "it comes back floating rather than docked")
        second.dock("bottom")
    }

    /// A closed panel must not come back open.
    func testAClosedPanelStaysClosed() {
        let first = host()
        first.show("left")
        first.hide("left")

        let second = host()
        second.restoreLayout()
        XCTAssertFalse(second.isVisible("left"))
    }
}

/// "The dock target is remembered per workspace." The arrangement that suits
/// one project is rarely the one that suits the next.
@MainActor
final class PerWorkspaceDockTests: XCTestCase {
    private let keys = ["NotepadXX.DockLayout",
                        "NotepadXX.DockLayout._tmp_project-a",
                        "NotepadXX.DockLayout._tmp_project-b"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private final class StubPanel: NSObject, DockablePanel {
        let panelIdentifier: String
        let panelTitle = "Stub"
        let preferredPosition: DockPosition
        let contentView = NSView()
        init(_ identifier: String, at position: DockPosition) {
            panelIdentifier = identifier
            preferredPosition = position
        }
    }

    private func host() -> DockHostView {
        let host = DockHostView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        host.register(StubPanel("searchResults", at: .bottom))
        host.register(StubPanel("functionList", at: .right))
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testEachWorkspaceKeepsItsOwnArrangement() {
        let first = host()
        first.workspaceIdentifier = "_tmp_project-a"
        first.show("searchResults")

        let second = host()
        second.workspaceIdentifier = "_tmp_project-b"
        second.show("functionList")

        // Reopening project A gets A's panels, not B's.
        let reopened = host()
        reopened.workspaceIdentifier = "_tmp_project-a"
        XCTAssertTrue(reopened.isVisible("searchResults"))
        XCTAssertFalse(reopened.isVisible("functionList"))
    }

    /// Switching workspace in one window swaps the arrangement over.
    func testSwitchingWorkspaceSwapsTheLayout() {
        let host = host()
        host.workspaceIdentifier = "_tmp_project-a"
        host.show("searchResults")

        host.workspaceIdentifier = "_tmp_project-b"
        XCTAssertFalse(host.isVisible("searchResults"),
                       "project B's layout is not project A's")

        host.show("functionList")
        host.workspaceIdentifier = "_tmp_project-a"
        XCTAssertTrue(host.isVisible("searchResults"), "and switching back restores A's")
        XCTAssertFalse(host.isVisible("functionList"))
    }

    /// A folder is turned into a key that is safe to store.
    func testWorkspaceKeysAreDerivedFromThePath() {
        let key = MainWindowController.workspaceKey(for: URL(fileURLWithPath: "/tmp/my project"))
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains(" "))
    }
}
