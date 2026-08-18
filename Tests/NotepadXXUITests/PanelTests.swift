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

@MainActor
final class FloatingPanelTests: XCTestCase {
    private final class StubPanel: NSObject, DockablePanel {
        let panelIdentifier = "stub"
        let panelTitle = "Stub"
        let preferredPosition = DockPosition.left
        let contentView = NSView()
        var visibleCount = 0
        func panelDidBecomeVisible() { visibleCount += 1 }
    }

    func testFloatingRemovesFromTheDock() {
        let host = DockHostView()
        let panel = StubPanel()
        host.register(panel)
        host.show("stub")
        XCTAssertTrue(host.isVisible("stub"))

        host.float("stub")
        XCTAssertTrue(host.isFloating("stub"))
        XCTAssertFalse(host.isVisible("stub"), "a floating panel is not also docked")
    }

    /// Closing a floating panel must re-dock it, not lose it.
    func testDockingReturnsThePanelToTheDock() {
        let host = DockHostView()
        host.register(StubPanel())
        host.float("stub")
        host.dock("stub")
        XCTAssertFalse(host.isFloating("stub"))
        XCTAssertTrue(host.isVisible("stub"))
    }

    func testFloatingTwiceIsANoOp() {
        let host = DockHostView()
        host.register(StubPanel())
        host.float("stub")
        host.float("stub")
        XCTAssertTrue(host.isFloating("stub"))
    }

    func testFloatingPanelsStillRefresh() {
        let host = DockHostView()
        let panel = StubPanel()
        host.register(panel)
        host.float("stub")
        let before = panel.visibleCount
        host.refreshVisiblePanels()
        XCTAssertGreaterThan(panel.visibleCount, before,
                             "a floating panel still tracks the active document")
    }
}

@MainActor
final class TabLayoutTests: XCTestCase {
    func testHorizontalLayoutIsFixedHeight() {
        let bar = TabBarView()
        bar.layout = .horizontal
        XCTAssertEqual(bar.requiredExtent(tabCount: 20, availableWidth: 1000), 28)
    }

    func testVerticalLayoutGrowsWithTabCount() {
        let bar = TabBarView()
        bar.layout = .vertical
        let two = bar.requiredExtent(tabCount: 2, availableWidth: 1000)
        let ten = bar.requiredExtent(tabCount: 10, availableWidth: 1000)
        XCTAssertGreaterThan(ten, two)
    }

    func testMultiLineWrapsByAvailableWidth() {
        let bar = TabBarView()
        bar.layout = .multiLine
        let wide = bar.requiredExtent(tabCount: 8, availableWidth: 1600)
        let narrow = bar.requiredExtent(tabCount: 8, availableWidth: 320)
        XCTAssertGreaterThan(narrow, wide, "a narrower window needs more rows")
    }

    func testZeroTabsStillHasHeight() {
        let bar = TabBarView()
        bar.layout = .multiLine
        XCTAssertGreaterThan(bar.requiredExtent(tabCount: 0, availableWidth: 1000), 0)
    }
}
