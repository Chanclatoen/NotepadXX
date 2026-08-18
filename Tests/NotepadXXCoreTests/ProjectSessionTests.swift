import XCTest
@testable import NotepadXXCore

final class ProjectTests: XCTestCase {
    private func makeStore() throws -> (ProjectStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-proj-\(UUID().uuidString)", isDirectory: true)
        return (try ProjectStore(directory: dir), dir)
    }

    func testNestedFoldersFlattenInTreeOrder() {
        let inner = Project.Folder(name: "inner", filePaths: ["/c.txt"])
        let root = Project.Folder(name: "root", filePaths: ["/a.txt", "/b.txt"], folders: [inner])
        let project = Project(name: "P", root: root)
        XCTAssertEqual(project.allFilePaths, ["/a.txt", "/b.txt", "/c.txt"])
    }

    func testSaveAndReload() throws {
        let (store, dir) = try makeStore()
        var project = Project(name: "Alpha")
        project.root.filePaths = ["/tmp/one.txt"]
        try store.save(project)

        let reopened = try ProjectStore(directory: dir)
        XCTAssertEqual(reopened.projects.map(\.name), ["Alpha"])
        XCTAssertEqual(reopened.project(named: "alpha")?.allFilePaths, ["/tmp/one.txt"])
    }

    func testDelete() throws {
        let (store, _) = try makeStore()
        try store.save(Project(name: "Gone"))
        store.delete(named: "Gone")
        XCTAssertTrue(store.projects.isEmpty)
    }

    /// A project quietly full of dead entries is a known annoyance; surface them.
    func testMissingFilesAreReported() throws {
        let (store, dir) = try makeStore()
        let real = dir.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)

        var project = Project(name: "Mixed")
        project.root.filePaths = [real.path, "/tmp/definitely-missing-\(UUID().uuidString)"]
        try store.save(project)

        XCTAssertEqual(project.missingFilePaths().count, 1)
    }

    func testProjectNameWithSlashesStaysInsideTheDirectory() throws {
        let (store, dir) = try makeStore()
        try store.save(Project(name: "../../escape"))
        let files = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("projects").path
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains(".."))
    }

    func testExportAndImport() throws {
        let (store, dir) = try makeStore()
        var project = Project(name: "Portable")
        project.root.filePaths = ["/tmp/x.txt"]
        let exported = dir.appendingPathComponent("exported.json")
        try store.export(project, to: exported)

        let (other, _) = try makeStore()
        let imported = try other.import(from: exported)
        XCTAssertEqual(imported.name, "Portable")
        XCTAssertEqual(other.projects.count, 1)
    }
}

final class NamedSessionTests: XCTestCase {
    private func makeStore() throws -> (NamedSessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-sess-\(UUID().uuidString)", isDirectory: true)
        return (try NamedSessionStore(directory: dir), dir)
    }

    func testSaveAndLoad() throws {
        let (store, _) = try makeStore()
        let documents = [
            TextDocument(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), text: "a"),
            TextDocument(fileURL: URL(fileURLWithPath: "/tmp/b.txt"), text: "b"),
        ]
        try store.save(name: "Work", documents: documents, activeIndex: 1)

        let loaded = store.load(name: "Work")
        XCTAssertEqual(loaded?.filePaths, ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(loaded?.activeIndex, 1)
    }

    /// A named session is a list of files to reopen; unsaved scratch buffers
    /// have no path and are already covered by crash-safe autosave.
    func testUntitledDocumentsAreNotRecorded() throws {
        let (store, _) = try makeStore()
        try store.save(
            name: "Mixed",
            documents: [TextDocument(text: "scratch"),
                        TextDocument(fileURL: URL(fileURLWithPath: "/tmp/real.txt"), text: "r")],
            activeIndex: 0
        )
        XCTAssertEqual(store.load(name: "Mixed")?.filePaths, ["/tmp/real.txt"])
    }

    func testActiveIndexIsClampedToTheRecordedFiles() throws {
        let (store, _) = try makeStore()
        try store.save(name: "Clamp",
                       documents: [TextDocument(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), text: "a")],
                       activeIndex: 5)
        XCTAssertEqual(store.load(name: "Clamp")?.activeIndex, 0)
    }

    func testNamesAreListedAndDeleted() throws {
        let (store, dir) = try makeStore()
        try store.save(name: "Beta", documents: [], activeIndex: 0)
        try store.save(name: "Alpha", documents: [], activeIndex: 0)
        XCTAssertEqual(store.names, ["Alpha", "Beta"], "listed alphabetically")

        store.delete(name: "Alpha")
        XCTAssertEqual(try NamedSessionStore(directory: dir).names, ["Beta"])
    }

    func testLoadingAnUnknownSessionIsNil() throws {
        let (store, _) = try makeStore()
        XCTAssertNil(store.load(name: "nope"))
    }
}
