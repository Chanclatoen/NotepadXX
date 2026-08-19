import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The design makes Find, Replace, Find in Files and Mark four modes of one
/// panel. These check the workflow that results, not the flags behind it.
@MainActor
final class SearchWorkflowTests: XCTestCase {
    private func make(_ text: String = "alpha beta alpha gamma\nalpha delta\n") -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    /// The inconsistency this replaced: Find in Files used to pop a folder
    /// picker before there was anything to search, while Find opened a dialog.
    func testEveryEntryPointOpensTheSamePanelInItsOwnMode() {
        let controller = make()

        controller.showFindPanelAction(nil)
        let panel = controller.installedFindPanel
        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.mode, .find)

        controller.showReplacePanelAction(nil)
        XCTAssertTrue(controller.installedFindPanel === panel, "Replace reuses the one panel")
        XCTAssertEqual(controller.installedFindPanel?.mode, .replace)

        controller.showFindInFilesAction(nil)
        XCTAssertTrue(controller.installedFindPanel === panel, "Find in Files reuses the one panel")
        XCTAssertEqual(controller.installedFindPanel?.mode, .findInFiles)

        controller.showMarkPanelAction(nil)
        XCTAssertTrue(controller.installedFindPanel === panel, "Mark reuses the one panel")
        XCTAssertEqual(controller.installedFindPanel?.mode, .mark)
    }

    /// The menu item must not run a search or ask for a folder on its own.
    func testFindInFilesMenuItemOnlyOpensThePanel() {
        let controller = make()
        controller.findInFilesAction(nil)
        XCTAssertEqual(controller.installedFindPanel?.mode, .findInFiles)
        XCTAssertEqual(controller.searchResultsPanel?.hitCount, 0,
                       "no search runs until the panel is given a pattern and a directory")
    }

    func testOpeningTheSearchPanelSeedsThePatternFromTheSelection() {
        let controller = make()
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 5)
        controller.showFindPanelAction(nil)
        XCTAssertEqual(controller.installedFindPanel?.currentPattern, "alpha")
    }

    func testCyclingSearchModeWalksNormalExtendedRegex() {
        let controller = make()
        controller.showFindPanelAction(nil)
        let panel = try! XCTUnwrap(controller.installedFindPanel)
        // Start from a known mode: the panel opens in whichever mode the user's
        // preferences name, which is not necessarily Normal.
        panel.applyDefaults(searchMode: .normal, wrapsAround: true, closesAfterUse: false)
        XCTAssertEqual(panel.currentOptions.mode, .normal)
        controller.cycleSearchModeAction(nil)
        XCTAssertEqual(panel.currentOptions.mode, .extended)
        controller.cycleSearchModeAction(nil)
        XCTAssertEqual(panel.currentOptions.mode, .regex)
        controller.cycleSearchModeAction(nil)
        XCTAssertEqual(panel.currentOptions.mode, .normal, "cycles back round")
    }

    /// The panel's status line is the only place ordinary outcomes are spoken —
    /// a failed search must not raise a dialog.
    func testAFailedSearchReportsInTheStatusLine() {
        let controller = make()
        controller.showFindPanelAction(nil)
        let panel = try! XCTUnwrap(controller.installedFindPanel)
        panel.setPattern("nothing-here")
        controller.performFind(panel.request)
        XCTAssertTrue(panel.statusMessage.contains("Can't find"), "got: \(panel.statusMessage)")
    }

    func testReplaceAllInOpenDocumentsChangesEveryDocument() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "alpha one"),
                                     TextDocument(text: "alpha two")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.showReplacePanelAction(nil)
        let panel = try! XCTUnwrap(controller.installedFindPanel)
        panel.setPattern("alpha")
        controller.performReplaceAllInOpenDocuments(
            .init(pattern: "alpha", replacement: "omega", options: SearchOptions(), inSelection: false))

        XCTAssertEqual(controller.documents[0].text, "omega one")
        XCTAssertEqual(controller.documents[1].text, "omega two")
    }

    func testMarkAllMarksEveryMatchAndCanBookmarkTheLines() {
        let controller = make("TODO one\nplain\nTODO two\n")
        controller.showMarkPanelAction(nil)
        let document = try! XCTUnwrap(controller.activeDocument)

        controller.performMarkAll(.init(pattern: "TODO", replacement: "",
                                        options: SearchOptions(), inSelection: false,
                                        markStyle: MarkStyle(index: 2),
                                        bookmarkMatchingLines: true))

        let marks = try! XCTUnwrap(controller.markedRanges[document.id])
        XCTAssertEqual(marks.ranges(for: MarkStyle(index: 2)).count, 2, "both TODOs marked")
        XCTAssertEqual(controller.bookmarks[document.id]?.lines, [0, 2],
                       "the matching lines are bookmarked, and only those")
    }

    /// Marking again with "purge" clears the previous run rather than stacking.
    func testPurgeReplacesThePreviousMarks() {
        let controller = make("aaa bbb\n")
        let document = try! XCTUnwrap(controller.activeDocument)

        controller.performMarkAll(.init(pattern: "aaa", replacement: "", options: SearchOptions(),
                                        inSelection: false, markStyle: MarkStyle(index: 0)))
        controller.performMarkAll(.init(pattern: "bbb", replacement: "", options: SearchOptions(),
                                        inSelection: false, markStyle: MarkStyle(index: 1),
                                        purgeMarks: true))

        let marks = try! XCTUnwrap(controller.markedRanges[document.id])
        XCTAssertTrue(marks.ranges(for: MarkStyle(index: 0)).isEmpty, "the first run was purged")
        XCTAssertEqual(marks.ranges(for: MarkStyle(index: 1)).count, 1)
    }
}

/// Find in Files gained an exclusion field, so it needs to actually exclude.
final class FindInFilesExclusionTests: XCTestCase {
    private func makeTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-exclusions-\(ProcessInfo.processInfo.globallyUniqueString)")
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)
        try "needle in source".write(to: root.appendingPathComponent("src/a.swift"),
                                     atomically: true, encoding: .utf8)
        try "needle in build".write(to: root.appendingPathComponent("build/b.swift"),
                                    atomically: true, encoding: .utf8)
        try "needle in notes".write(to: root.appendingPathComponent("notes.txt"),
                                    atomically: true, encoding: .utf8)
        return root
    }

    func testExcludedDirectoryIsNotSearched() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = SearchEngine(pattern: "needle", options: SearchOptions())
        let all = try FindInFiles(engine: engine).search(directory: root)
        XCTAssertEqual(all.count, 3, "every file matches before exclusions")

        let filtered = try FindInFiles(
            engine: engine, options: FindInFilesOptions(exclusions: "build/")
        ).search(directory: root)
        XCTAssertEqual(Set(filtered.map(\.url.lastPathComponent)), ["a.swift", "notes.txt"])
    }

    func testExcludedFileGlobIsNotSearched() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let filtered = try FindInFiles(
            engine: SearchEngine(pattern: "needle", options: SearchOptions()),
            options: FindInFilesOptions(exclusions: "*.txt")
        ).search(directory: root)
        XCTAssertFalse(filtered.contains { $0.url.lastPathComponent == "notes.txt" })
        XCTAssertEqual(filtered.count, 2)
    }
}

/// Screenshots cannot show SwiftUI-hosted controls, so the panel's layout is
/// checked by asserting the geometry the user would otherwise see.
@MainActor
final class SearchPanelLayoutTests: XCTestCase {
    private func panel(_ mode: SearchPanelController.Mode) -> SearchPanelController {
        let panel = SearchPanelController()
        panel.show(mode: mode)
        panel.window?.contentView?.layoutSubtreeIfNeeded()
        return panel
    }

    /// A row that runs past the panel edge is clipped on screen; the file
    /// filter fields did exactly that before they were constrained.
    func testNoVisibleRowOverflowsThePanelInAnyMode() {
        for mode in SearchPanelController.Mode.allCases {
            let controller = panel(mode)
            let content = controller.window!.contentView!
            for row in visibleRows(of: content) {
                let frame = row.convert(row.bounds, to: content)
                XCTAssertLessThanOrEqual(
                    frame.maxX, content.bounds.maxX + 0.5,
                    "a row overflows the panel in \(mode.title) mode")
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5, "a row starts off the left edge in \(mode.title)")
            }
        }
    }

    /// Find in Files adds four rows Find does not have; the window has to grow
    /// with them or the actions are cut off below the edge.
    func testEveryModeFitsInsideItsWindow() {
        for mode in SearchPanelController.Mode.allCases {
            let controller = panel(mode)
            let content = controller.window!.contentView!
            let fitting = content.fittingSize
            XCTAssertGreaterThanOrEqual(
                content.bounds.height + 0.5, fitting.height,
                "\(mode.title) mode is taller than its window")
        }
    }

    /// The field order is what muscle memory depends on: switching modes adds
    /// rows below, it never reorders the ones already there.
    func testFieldOrderIsIdenticalAcrossModes() {
        var seenOrders: [[String]] = []
        for mode in SearchPanelController.Mode.allCases {
            let controller = panel(mode)
            let content = controller.window!.contentView!
            let labels = visibleRows(of: content)
                .compactMap { row -> (CGFloat, String)? in
                    guard let label = firstLabel(in: row) else { return nil }
                    return (row.convert(row.bounds, to: content).minY, label)
                }
                // Top to bottom.
                .sorted { $0.0 > $1.0 }
                .map(\.1)
            seenOrders.append(labels)
        }
        // Every mode's labels must appear in the same relative order as the
        // fullest mode's.
        let reference = seenOrders.max(by: { $0.count < $1.count }) ?? []
        for order in seenOrders {
            let positions = order.compactMap { reference.firstIndex(of: $0) }
            XCTAssertEqual(positions, positions.sorted(), "rows are reordered between modes: \(order)")
        }
    }

    private func visibleRows(of content: NSView) -> [NSView] {
        guard let stack = content.subviews.compactMap({ $0 as? NSStackView }).first else { return [] }
        return stack.views.filter { !$0.isHidden }
    }

    private func firstLabel(in row: NSView) -> String? {
        guard let stack = row as? NSStackView else { return nil }
        return stack.views.compactMap { ($0 as? NSTextField)?.stringValue }
            .first { $0.hasSuffix(":") }
    }
}

/// A long scan must not freeze the window, and Cancel has to actually stop it.
@MainActor
final class FindInFilesProgressTests: XCTestCase {
    private func makeTree(files: Int) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-scan-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<files {
            try "needle \(index)".write(to: root.appendingPathComponent("file\(index).txt"),
                                        atomically: true, encoding: .utf8)
        }
        return root
    }

    func testTheScanReportsProgressAsItGoes() throws {
        let root = try makeTree(files: 120)
        defer { try? FileManager.default.removeItem(at: root) }

        var reports: [FindInFiles.Progress] = []
        let results = try FindInFiles(engine: SearchEngine(pattern: "needle", options: SearchOptions()))
            .search(directory: root, onProgress: { reports.append($0) })

        XCTAssertEqual(results.count, 120)
        XCTAssertGreaterThan(reports.count, 1, "progress is reported during the scan, not only at the end")
        XCTAssertEqual(reports.last?.scanned, 120)
        XCTAssertEqual(reports.last?.total, 120)
        XCTAssertGreaterThan(reports.last?.hits ?? 0, 0)
    }

    /// Cancelling stops the walk rather than letting it run to the end.
    func testCancellingStopsTheScanEarly() throws {
        let root = try makeTree(files: 200)
        defer { try? FileManager.default.removeItem(at: root) }

        let token = SearchCancellationToken()
        var scanned = 0
        let results = try FindInFiles(engine: SearchEngine(pattern: "needle", options: SearchOptions()))
            .search(directory: root,
                    isCancelled: { token.isCancelled },
                    onProgress: { progress in
                        scanned = progress.scanned
                        if progress.scanned >= 25 { token.cancel() }
                    })

        XCTAssertLessThan(results.count, 200, "the scan stopped before the end")
        XCTAssertGreaterThan(scanned, 0)
    }

    /// The panel drives the scan without blocking the main thread.
    func testTheWindowStaysResponsiveWhileScanning() throws {
        let root = try makeTree(files: 60)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "x")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.showFindInFilesAction(nil)

        controller.performFindInFiles(.init(pattern: "needle", replacement: "",
                                            options: SearchOptions(), inSelection: false,
                                            directory: root))
        // performFindInFiles returned immediately: the scan is elsewhere.
        XCTAssertEqual(controller.installedFindPanel?.isScanning, true)

        // A predicate expectation, not a run-loop spin: the results arrive on
        // the main queue, and only this drains it reliably on a loaded CI box.
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { controller.searchResultsPanel?.fileCount == 60 }
            },
            object: nil)
        wait(for: [finished], timeout: 60)

        XCTAssertEqual(controller.searchResultsPanel?.fileCount, 60)
        XCTAssertEqual(controller.installedFindPanel?.isScanning, false)
    }
}
