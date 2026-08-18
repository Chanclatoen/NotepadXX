import XCTest
@testable import NotepadXXCore

final class SearchHistoryTests: XCTestCase {
    func testMostRecentFirstWithoutDuplicates() {
        let history = SearchHistory()
        history.record("alpha", in: .pattern)
        history.record("beta", in: .pattern)
        history.record("alpha", in: .pattern)
        XCTAssertEqual(history.entries(for: .pattern), ["alpha", "beta"],
                       "re-searching moves an entry to the top rather than duplicating it")
    }

    func testEmptyAndWhitespaceEntriesAreIgnored() {
        let history = SearchHistory()
        history.record("", in: .pattern)
        history.record("   ", in: .pattern)
        XCTAssertTrue(history.entries(for: .pattern).isEmpty)
    }

    func testFieldsAreIndependent() {
        let history = SearchHistory()
        history.record("find", in: .pattern)
        history.record("replace", in: .replacement)
        XCTAssertEqual(history.entries(for: .pattern), ["find"])
        XCTAssertEqual(history.entries(for: .replacement), ["replace"])
    }

    func testLimitIsEnforced() {
        let history = SearchHistory(limit: 3)
        for index in 0..<10 { history.record("p\(index)", in: .pattern) }
        XCTAssertEqual(history.entries(for: .pattern).count, 3)
        XCTAssertEqual(history.entries(for: .pattern).first, "p9")
    }

    func testPersistsAcrossReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-hist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let history = SearchHistory()
        history.record("needle", in: .pattern)
        history.save(to: dir)

        XCTAssertEqual(SearchHistory.load(from: dir).entries(for: .pattern), ["needle"])
    }

    func testMissingFileYieldsAnEmptyHistory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-nohist-\(UUID().uuidString)", isDirectory: true)
        XCTAssertTrue(SearchHistory.load(from: dir).entries(for: .pattern).isEmpty)
    }
}

final class MarkedRangesTests: XCTestCase {
    private let style0 = MarkStyle(index: 0)
    private let style1 = MarkStyle(index: 1)

    func testStylesAreIndependent() {
        var marks = MarkedRanges()
        marks.set([NSRange(location: 0, length: 3)], for: style0)
        marks.set([NSRange(location: 10, length: 3)], for: style1)

        marks.clear(style0)
        XCTAssertTrue(marks.ranges(for: style0).isEmpty)
        XCTAssertEqual(marks.ranges(for: style1).count, 1, "clearing one style leaves the other")
    }

    func testStyleIndexIsClamped() {
        XCTAssertEqual(MarkStyle(index: 99).index, 4)
        XCTAssertEqual(MarkStyle(index: -3).index, 0)
        XCTAssertEqual(MarkStyle.all.count, 5, "Notepad++ has five mark styles")
    }

    func testMarkedTextIsInDocumentOrderAcrossStyles() {
        var marks = MarkedRanges()
        marks.set([NSRange(location: 8, length: 3)], for: style0)
        marks.set([NSRange(location: 0, length: 3)], for: style1)
        XCTAssertEqual(marks.markedText(in: "abc def ghi"), "abc\nghi")
    }

    func testMarkedTextIgnoresRangesPastTheEnd() {
        var marks = MarkedRanges()
        marks.set([NSRange(location: 50, length: 5)], for: style0)
        XCTAssertEqual(marks.markedText(in: "short"), "", "a stale range cannot crash the copy")
    }

    func testClearAll() {
        var marks = MarkedRanges()
        marks.set([NSRange(location: 0, length: 1)], for: style0)
        marks.clearAll()
        XCTAssertTrue(marks.isEmpty)
    }
}
