import XCTest
@testable import NotepadXXCore

final class BookmarkStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-bookmarks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? dir).appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDisabledStoreIsPassThroughAndWritesNothing() throws {
        let store = BookmarkStore(directory: dir, enabled: false)
        let f = try file("a.txt")
        store.remember(f)
        XCTAssertFalse(store.hasBookmark(for: f.path))
        XCTAssertEqual(store.access(f.path)?.path, f.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bookmarks.json").path))
    }

    func testRememberSurvivesRelaunchAndResolves() throws {
        let f = try file("a.txt")
        BookmarkStore(directory: dir, enabled: true).remember(f)
        let reopened = BookmarkStore(directory: dir, enabled: true)
        XCTAssertTrue(reopened.hasBookmark(for: f.path))
        XCTAssertEqual(reopened.access(f.path)?.resolvingSymlinksInPath().path, f.resolvingSymlinksInPath().path)
    }

    func testFileInsideRememberedFolderResolvesThroughTheFolder() throws {
        let folder = dir.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inner = try file("b.txt", in: folder)
        let store = BookmarkStore(directory: dir, enabled: true)
        store.remember(folder)
        XCTAssertFalse(store.hasBookmark(for: inner.path))
        XCTAssertNotNil(store.access(inner.path))
    }

    func testMissingFileIsDroppedWithoutCrashing() throws {
        let f = try file("gone.txt")
        let store = BookmarkStore(directory: dir, enabled: true)
        store.remember(f)
        try FileManager.default.removeItem(at: f)
        XCTAssertNil(store.access(f.path))
        XCTAssertFalse(store.hasBookmark(for: f.path))
        XCTAssertFalse(BookmarkStore(directory: dir, enabled: true).hasBookmark(for: f.path))
    }

    func testCorruptBookmarkDataIsDropped() throws {
        let f = try file("c.txt")
        let bad = ["\(f.resolvingSymlinksInPath().path)": Data([1, 2, 3])]
        try JSONEncoder().encode(bad).write(to: dir.appendingPathComponent("bookmarks.json"))
        let store = BookmarkStore(directory: dir, enabled: true)
        XCTAssertNil(store.access(f.path))
        XCTAssertFalse(store.hasBookmark(for: f.path))
    }

    func testMovedFileFollowsItsBookmark() throws {
        let f = try file("m.txt")
        let store = BookmarkStore(directory: dir, enabled: true)
        store.remember(f)
        let moved = dir.appendingPathComponent("m2.txt")
        try FileManager.default.moveItem(at: f, to: moved)
        XCTAssertEqual(store.access(f.path)?.resolvingSymlinksInPath().path, moved.resolvingSymlinksInPath().path)
    }

    func testForget() throws {
        let f = try file("d.txt")
        let store = BookmarkStore(directory: dir, enabled: true)
        store.remember(f)
        store.forget(f.path)
        XCTAssertFalse(store.hasBookmark(for: f.path))
        XCTAssertNil(store.access(f.path))
    }
}
