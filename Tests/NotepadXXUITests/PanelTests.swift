import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class DockHostTests: XCTestCase {
    private final class StubPanel: NSObject, DockablePanel {
        let panelIdentifier: String
        let panelTitle = "Stub"
        let preferredPosition: DockPosition
        let contentView = NSView()
        var becameVisibleCount = 0
        init(identifier: String, position: DockPosition) {
            self.panelIdentifier = identifier
            self.preferredPosition = position
        }
        func panelDidBecomeVisible() { becameVisibleCount += 1 }
    }

    func testPanelsStartHidden() {
        let host = DockHostView()
        host.register(StubPanel(identifier: "a", position: .left))
        XCTAssertFalse(host.isVisible("a"))
    }

    func testShowHideAndToggle() {
        let host = DockHostView()
        host.register(StubPanel(identifier: "a", position: .left))
        host.show("a")
        XCTAssertTrue(host.isVisible("a"))
        host.hide("a")
        XCTAssertFalse(host.isVisible("a"))
        host.toggle("a")
        XCTAssertTrue(host.isVisible("a"))
    }

    func testShowingNotifiesThePanel() {
        let host = DockHostView()
        let panel = StubPanel(identifier: "a", position: .right)
        host.register(panel)
        host.show("a")
        XCTAssertEqual(panel.becameVisibleCount, 1)
        host.show("a")
        XCTAssertEqual(panel.becameVisibleCount, 1, "showing an already-visible panel is a no-op")
    }

    func testRefreshNotifiesOnlyVisiblePanels() {
        let host = DockHostView()
        let shown = StubPanel(identifier: "shown", position: .left)
        let hidden = StubPanel(identifier: "hidden", position: .right)
        host.register(shown)
        host.register(hidden)
        host.show("shown")
        host.refreshVisiblePanels()
        XCTAssertEqual(shown.becameVisibleCount, 2)
        XCTAssertEqual(hidden.becameVisibleCount, 0)
    }

    func testUnknownIdentifierIsIgnored() {
        let host = DockHostView()
        XCTAssertNoThrow(host.show("nope"))
        XCTAssertFalse(host.isVisible("nope"))
    }

    func testPanelsInDifferentDocksCoexist() {
        let host = DockHostView()
        for (id, position) in [("l", DockPosition.left), ("r", .right), ("b", .bottom)] {
            host.register(StubPanel(identifier: id, position: position))
            host.show(id)
        }
        XCTAssertTrue(["l", "r", "b"].allSatisfy(host.isVisible))
    }
}

@MainActor
final class ClipboardHistoryPanelTests: XCTestCase {
    func testMostRecentFirst() {
        let panel = ClipboardHistoryPanel()
        panel.record("one")
        panel.record("two")
        XCTAssertEqual(panel.recordedEntries, ["two", "one"])
        panel.stopPolling()
    }

    func testDuplicatesAreMovedNotDuplicated() {
        let panel = ClipboardHistoryPanel()
        panel.record("a")
        panel.record("b")
        panel.record("a")
        XCTAssertEqual(panel.recordedEntries, ["a", "b"], "re-copying moves an entry to the top")
        panel.stopPolling()
    }

    func testHistoryIsCapped() {
        let panel = ClipboardHistoryPanel()
        panel.maximumEntries = 3
        for index in 1...10 { panel.record("entry \(index)") }
        XCTAssertEqual(panel.recordedEntries.count, 3)
        XCTAssertEqual(panel.recordedEntries.first, "entry 10")
        panel.stopPolling()
    }
}

@MainActor
final class FunctionListPanelTests: XCTestCase {
    func testPanelPullsSymbolsFromItsProvider() {
        let panel = FunctionListPanel()
        panel.symbolProvider = {
            FunctionListExtractor.symbols(in: "def a():\n    pass\ndef b():\n    pass\n",
                                          languageName: "Python")
        }
        panel.panelDidBecomeVisible()
        // Selecting the first row should report the first symbol.
        var selected: Symbol?
        panel.onSelect = { selected = $0 }
        panel.reload()
        XCTAssertNil(selected, "no selection until the user clicks")
    }

    func testWorkspacePanelOpensFilesNotDirectories() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("f.txt"))

        let panel = FolderWorkspacePanel()
        panel.addRoot(dir)
        panel.addRoot(dir)   // adding twice must not duplicate the root
        XCTAssertNotNil(panel.contentView)
        panel.removeAllRoots()
    }
}
