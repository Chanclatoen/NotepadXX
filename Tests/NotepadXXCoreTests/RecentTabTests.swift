import XCTest
@testable import NotepadXXCore

final class RecentFilesTests: XCTestCase {
    private func makeStore(limit: Int = 15) throws -> (RecentFiles, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (RecentFiles(directory: dir, limit: limit), dir)
    }

    func testMostRecentFirst() throws {
        let (recent, _) = try makeStore()
        recent.record("/tmp/a.txt")
        recent.record("/tmp/b.txt")
        XCTAssertEqual(recent.paths.first, "/tmp/b.txt")
    }

    func testReopeningMovesToTopWithoutDuplicating() throws {
        let (recent, _) = try makeStore()
        recent.record("/tmp/a.txt")
        recent.record("/tmp/b.txt")
        recent.record("/tmp/a.txt")
        XCTAssertEqual(recent.paths, ["/tmp/a.txt", "/tmp/b.txt"])
    }

    func testLimitIsEnforcedAndLoweringItTrims() throws {
        let (recent, _) = try makeStore(limit: 3)
        for index in 0..<10 { recent.record("/tmp/\(index).txt") }
        XCTAssertEqual(recent.paths.count, 3)
        recent.limit = 1
        XCTAssertEqual(recent.paths.count, 1)
    }

    func testPersistsAcrossReload() throws {
        let (recent, dir) = try makeStore()
        recent.record("/tmp/keep.txt")
        let reopened = RecentFiles(directory: dir)
        XCTAssertEqual(reopened.paths, ["/tmp/keep.txt"])
    }

    /// A list full of dead paths is worse than a short one.
    func testPruneMissingDropsDeletedFiles() throws {
        let (recent, dir) = try makeStore()
        let real = dir.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        recent.record(real.path)
        recent.record("/tmp/definitely-not-here-\(UUID().uuidString).txt")

        recent.pruneMissing()
        XCTAssertEqual(recent.paths.count, 1)
        XCTAssertTrue(recent.paths[0].hasSuffix("real.txt"))
    }

    func testClearAndRemove() throws {
        let (recent, _) = try makeStore()
        recent.record("/tmp/a.txt")
        recent.record("/tmp/b.txt")
        recent.remove("/tmp/a.txt")
        XCTAssertEqual(recent.paths, ["/tmp/b.txt"])
        recent.clear()
        XCTAssertTrue(recent.paths.isEmpty)
    }
}

final class TabSortingTests: XCTestCase {
    func testPinnedTabsComeFirstPreservingOrder() {
        // Tabs 1 and 3 are pinned.
        let order = TabSorting.ordering(count: 5) { [1, 3].contains($0) }
        XCTAssertEqual(order, [1, 3, 0, 2, 4])
    }

    func testNoPinnedTabsLeavesOrderAlone() {
        XCTAssertEqual(TabSorting.ordering(count: 3) { _ in false }, [0, 1, 2])
    }

    /// An unpinned tab must not be draggable ahead of a pinned one.
    func testUnpinnedTabCannotJumpAheadOfPinned() {
        let destination = TabSorting.clampedDestination(
            moving: 3, to: 0, isPinned: { $0 < 2 }, count: 5
        )
        XCTAssertEqual(destination, 2, "clamped to just after the pinned tabs")
    }

    func testPinnedTabStaysWithinThePinnedGroup() {
        let destination = TabSorting.clampedDestination(
            moving: 0, to: 4, isPinned: { $0 < 2 }, count: 5
        )
        XCTAssertEqual(destination, 1, "cannot move past the last pinned slot")
    }

    func testSortByName() {
        let names = ["c.txt", "a.txt", "b.txt"]
        let sorted = TabSorting.sorted(indices: [0, 1, 2], order: .name,
                                       name: { names[$0] }, path: { _ in nil })
        XCTAssertEqual(sorted.map { names[$0] }, ["a.txt", "b.txt", "c.txt"])
    }

    func testSortByExtensionThenName() {
        let names = ["b.swift", "a.txt", "a.swift"]
        let sorted = TabSorting.sorted(indices: [0, 1, 2], order: .extensionThenName,
                                       name: { names[$0] }, path: { _ in nil })
        XCTAssertEqual(sorted.map { names[$0] }, ["a.swift", "b.swift", "a.txt"])
    }

    func testSortUsesNaturalOrderingForNumbers() {
        let names = ["file10.txt", "file2.txt"]
        let sorted = TabSorting.sorted(indices: [0, 1], order: .name,
                                       name: { names[$0] }, path: { _ in nil })
        XCTAssertEqual(sorted.map { names[$0] }, ["file2.txt", "file10.txt"],
                       "file2 sorts before file10, not after")
    }
}
