import XCTest
@testable import NotepadXXCore

final class SessionStoreTests: XCTestCase {
    private func makeStore() throws -> (SessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try SessionStore(directory: dir), dir)
    }

    /// The headline behaviour: an untitled buffer with unsaved text must come
    /// back after an abrupt termination, with no save prompt and no data loss.
    func testUntitledDirtyBufferSurvivesSimulatedCrash() throws {
        let (store, dir) = try makeStore()
        let scratch = TextDocument(text: "notes I never saved")
        scratch.untitledName = "new 1"
        try store.save(documents: [scratch], activeIndex: 0)

        // Simulate a crash: no clean shutdown, just a brand new store over the
        // same directory, as would happen on relaunch.
        let reopened = try SessionStore(directory: dir)
        let (documents, active) = reopened.restoreDocuments()

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].text, "notes I never saved")
        XCTAssertTrue(documents[0].isUntitled)
        XCTAssertEqual(documents[0].untitledName, "new 1")
        XCTAssertEqual(documents[0].id, scratch.id, "identity is preserved across restore")
        XCTAssertEqual(active, 0)
    }

    /// Unsaved edits to a file-backed document must win over the stale bytes
    /// still sitting on disk.
    func testUnsavedEditsBeatOnDiskContent() throws {
        let (store, dir) = try makeStore()
        let fileURL = dir.appendingPathComponent("doc.txt")
        try Data("saved version".utf8).write(to: fileURL)

        let document = try TextDocument.load(contentsOf: fileURL)
        document.text = "edited but never saved"
        try store.save(documents: [document], activeIndex: 0)

        let (documents, _) = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(documents[0].text, "edited but never saved")
        XCTAssertTrue(documents[0].isDirty)
        XCTAssertEqual(documents[0].fileURL, fileURL)
    }

    /// A clean file-backed document needs no snapshot; it reloads from disk and
    /// should pick up whatever is there now.
    func testCleanDocumentRestoresFromDisk() throws {
        let (store, dir) = try makeStore()
        let fileURL = dir.appendingPathComponent("clean.txt")
        try Data("original".utf8).write(to: fileURL)

        let document = try TextDocument.load(contentsOf: fileURL)
        try store.save(documents: [document], activeIndex: 0)

        let (documents, _) = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(documents[0].text, "original")
        XCTAssertFalse(documents[0].isDirty)
    }

    func testSnapshotsArePrunedOnceDocumentIsSaved() throws {
        let (store, dir) = try makeStore()
        let backups = dir.appendingPathComponent("backups")
        let fileURL = dir.appendingPathComponent("doc.txt")
        try Data("v1".utf8).write(to: fileURL)

        let document = try TextDocument.load(contentsOf: fileURL)
        document.text = "v2 unsaved"
        try store.save(documents: [document], activeIndex: 0)
        var names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(names.count, 1, "dirty document is snapshotted")

        try document.save()
        try store.save(documents: [document], activeIndex: 0)
        names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(names.count, 0, "snapshot is dropped once content is safely on disk")
    }

    func testClosedDocumentSnapshotIsCleanedUp() throws {
        let (store, dir) = try makeStore()
        let backups = dir.appendingPathComponent("backups")
        let a = TextDocument(text: "keep me")
        let b = TextDocument(text: "close me")
        try store.save(documents: [a, b], activeIndex: 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 2)

        try store.save(documents: [a], activeIndex: 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(names, ["\(a.id.uuidString).txt"])
    }

    func testEncodingAndLineEndingSurviveRestore() throws {
        let (store, dir) = try makeStore()
        let document = TextDocument(text: "x", encoding: .utf8BOM, lineEnding: .crlf)
        try store.save(documents: [document], activeIndex: 0)

        let (documents, _) = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(documents[0].encoding, .utf8BOM)
        XCTAssertEqual(documents[0].lineEnding, .crlf)
    }

    func testRestoresActiveTabAndClampsOutOfRangeIndex() throws {
        let (store, dir) = try makeStore()
        let documents = [TextDocument(text: "a"), TextDocument(text: "b"), TextDocument(text: "c")]
        try store.save(documents: documents, activeIndex: 2)
        XCTAssertEqual(try SessionStore(directory: dir).restoreDocuments().activeIndex, 2)

        // A deleted file whose snapshot is also gone must not leave a dangling index.
        try store.save(documents: [documents[0]], activeIndex: 0)
        let restored = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(restored.documents.count, 1)
        XCTAssertEqual(restored.activeIndex, 0)
    }

    func testMissingSessionYieldsEmptyRestore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-empty-\(UUID().uuidString)", isDirectory: true)
        let store = try SessionStore(directory: dir)
        let (documents, active) = store.restoreDocuments()
        XCTAssertTrue(documents.isEmpty)
        XCTAssertEqual(active, 0)
    }

    func testDeletedFileStillRestoresFromSnapshot() throws {
        let (store, dir) = try makeStore()
        let fileURL = dir.appendingPathComponent("gone.txt")
        try Data("on disk".utf8).write(to: fileURL)
        let document = try TextDocument.load(contentsOf: fileURL)
        document.text = "unsaved work"
        try store.save(documents: [document], activeIndex: 0)

        try FileManager.default.removeItem(at: fileURL)
        let (documents, _) = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].text, "unsaved work", "work survives even if the file is deleted")
    }
}
