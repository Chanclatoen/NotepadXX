import XCTest
@testable import NotepadXXCore

final class FindInFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-fif-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        for dir in [root!, nested, hidden] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("alpha needle\nbeta\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("no match here\n".utf8).write(to: root.appendingPathComponent("b.txt"))
        try Data("needle in swift\n".utf8).write(to: root.appendingPathComponent("c.swift"))
        try Data("deep needle\n".utf8).write(to: nested.appendingPathComponent("d.txt"))
        try Data("hidden needle\n".utf8).write(to: hidden.appendingPathComponent("e.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func finder(_ pattern: String = "needle", _ options: FindInFilesOptions = FindInFilesOptions()) -> FindInFiles {
        FindInFiles(engine: SearchEngine(pattern: pattern, options: SearchOptions()), options: options)
    }

    func testFindsAcrossSubfoldersButSkipsHiddenByDefault() throws {
        let results = try finder().search(directory: root)
        let names = Set(results.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["a.txt", "c.swift", "d.txt"])
        XCTAssertFalse(names.contains("e.txt"), "hidden folders are skipped by default")
        XCTAssertFalse(names.contains("b.txt"))
    }

    func testSubfolderToggle() throws {
        let results = try finder("needle", FindInFilesOptions(inSubfolders: false)).search(directory: root)
        XCTAssertFalse(results.map { $0.url.lastPathComponent }.contains("d.txt"))
    }

    func testFileFilters() throws {
        let results = try finder("needle", FindInFilesOptions(filters: "*.swift")).search(directory: root)
        XCTAssertEqual(results.map { $0.url.lastPathComponent }, ["c.swift"])
    }

    func testMultipleFilters() {
        let options = FindInFilesOptions(filters: "*.txt;*.swift")
        XCTAssertEqual(options.filterPatterns, ["*.txt", "*.swift"])
        XCTAssertTrue(options.matchesFilter("a.txt"))
        XCTAssertTrue(options.matchesFilter("b.swift"))
        XCTAssertFalse(options.matchesFilter("c.md"))
    }

    func testEmptyFilterMatchesEverything() {
        XCTAssertTrue(FindInFilesOptions().matchesFilter("anything.bin"))
    }

    func testHitCarriesLineNumberAndText() throws {
        let url = URL(fileURLWithPath: "/tmp/x.txt")
        let hits = try finder().search(text: "one\ntwo needle two\nthree\n", url: url)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].lineNumber, 2)
        XCTAssertEqual(hits[0].lineText, "two needle two", "line text is trimmed of its terminator")
    }

    func testLineNumbersAreCorrectForManyHits() throws {
        let text = (1...100).map { "line \($0) needle" }.joined(separator: "\n")
        let hits = try finder().search(text: text, url: URL(fileURLWithPath: "/tmp/y.txt"))
        XCTAssertEqual(hits.count, 100)
        XCTAssertEqual(hits.first?.lineNumber, 1)
        XCTAssertEqual(hits.last?.lineNumber, 100)
    }

    func testUnsavedBufferContentWinsOverDisk() throws {
        let path = root.appendingPathComponent("b.txt").path
        let results = try finder().search(directory: root, openBuffers: [path: "now it has a needle\n"])
        let names = Set(results.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("b.txt"), "unsaved edits must be searched, not the stale file")
    }

    func testCancellationStopsEarly() throws {
        var calls = 0
        let results = try finder().search(directory: root, isCancelled: { calls += 1; return calls > 1 })
        XCTAssertLessThan(results.count, 3)
    }
}
