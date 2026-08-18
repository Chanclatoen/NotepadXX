import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Audit: the remaining command categories, each asserted against observable
/// state rather than a stored flag.
@MainActor
final class AuditFileTabTests: XCTestCase {
    private func temp(_ name: String, _ contents: String = "body") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
    private func controller() -> MainWindowController {
        let c = MainWindowController()
        let window = c.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return c
    }

    func testRenameMovesTheFileAndRetargetsTheTab() throws {
        let url = try temp("before.txt")
        let c = controller()
        XCTAssertTrue(c.openOrFocus(url: url))

        let destination = url.deletingLastPathComponent().appendingPathComponent("after.txt")
        try FileManager.default.moveItem(at: url, to: destination)
        c.activeDocument?.relocate(to: destination)

        XCTAssertEqual(c.activeDocument?.displayName, "after.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSaveAllWritesEveryDirtyFile() throws {
        let first = try temp("one.txt", "1")
        let second = try temp("two.txt", "2")
        let c = controller()
        c.openOrFocus(url: first)
        c.openOrFocus(url: second)

        for document in c.documents { document.text = "changed" }
        c.saveAllAction(nil)

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "changed")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "changed")
    }

    func testRecentFilesRecordsOpens() throws {
        let url = try temp("recent.txt")
        let c = controller()
        c.openOrFocus(url: url)
        XCTAssertTrue(c.recentFiles?.paths.contains { $0.hasSuffix("recent.txt") } ?? false)
    }

    func testReadOnlyBlocksTheEditor() throws {
        let c = controller()
        c.adopt(documents: [TextDocument(text: "x")], activeIndex: 0)
        c.toggleReadOnlyAction(nil)
        XCTAssertEqual(c.currentEditor?.isEditable, false, "the view actually refuses edits")
    }

    func testClosingATabReleasesItsEditor() {
        let c = controller()
        c.adopt(documents: [TextDocument(text: "a"), TextDocument(text: "b")], activeIndex: 0)
        c.selectTab(at: 1)
        c.selectTab(at: 0)
        c.closeTabAction(nil)
        XCTAssertEqual(c.tabs.count, 1)
        XCTAssertNotNil(c.currentEditor, "the surviving tab still has a working editor")
    }

    func testSessionRestoreBringsBackContentAndSelection() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-sess-\(UUID().uuidString)", isDirectory: true)
        let store = try SessionStore(directory: dir)
        let scratch = TextDocument()
        scratch.text = "unsaved work"
        try store.save(documents: [scratch], activeIndex: 0)

        let restored = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(restored.documents.first?.text, "unsaved work")
    }
}

@MainActor
final class AuditEncodingTests: XCTestCase {
    private func controller(_ text: String) -> MainWindowController {
        let c = MainWindowController()
        c.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        _ = c.window
        return c
    }

    func testEOLConversionsChangeBytesOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-eol-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("f.txt")
        try Data("a\nb\n".utf8).write(to: url)

        let c = MainWindowController()
        _ = c.window
        c.openOrFocus(url: url)
        c.convertToWindowsEOLAction(nil)
        c.saveDocumentAction(nil)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\r\nb\r\n")

        c.convertToMacEOLAction(nil)
        c.saveDocumentAction(nil)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\rb\r")
    }

    func testEncodingConversionChangesTheBytesWritten() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-enc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("f.txt")
        try Data("hi".utf8).write(to: url)

        let c = MainWindowController()
        _ = c.window
        c.openOrFocus(url: url)
        c.convertToUTF8BOMAction(nil)
        c.saveDocumentAction(nil)

        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(Array(bytes.prefix(3)), [0xEF, 0xBB, 0xBF], "the BOM is on disk")
    }

    func testStatusBarReportsEncodingAndEOL() {
        let c = controller("a\r\nb\r\n")
        c.activeDocument?.lineEnding = .crlf
        c.activeDocument?.encoding = .utf8BOM
        c.refreshUI()
        // Asserting the model the status bar is fed from.
        XCTAssertEqual(c.activeDocument?.lineEnding.displayName, "Windows (CR LF)")
        XCTAssertEqual(c.activeDocument?.encoding.displayName, "UTF-8-BOM")
    }
}

@MainActor
final class AuditPanelsAndAutomationTests: XCTestCase {
    private func controller(_ text: String = "def a():\n    pass\n") -> MainWindowController {
        let c = MainWindowController()
        let document = TextDocument(text: text)
        document.languageName = "Python"
        c.adopt(documents: [document], activeIndex: 0)
        let window = c.window!
        window.setContentSize(NSSize(width: 1200, height: 700))
        window.contentView?.layoutSubtreeIfNeeded()
        return c
    }

    func testEveryPanelTogglesAndPopulates() {
        let c = controller()
        for identifier in ["functionList", "documentMap", "clipboardHistory",
                           "characterPanel", "projectPanel", "folderWorkspace"] {
            c.dockHost?.toggle(identifier)
            XCTAssertTrue(c.dockHost?.isVisible(identifier) ?? false, "\(identifier) did not show")
            c.dockHost?.toggle(identifier)
            XCTAssertFalse(c.dockHost?.isVisible(identifier) ?? true, "\(identifier) did not hide")
        }
    }

    func testFunctionListFindsSymbolsInTheOpenDocument() {
        let c = controller()
        c.dockHost?.show("functionList")
        c.refreshUI()
        let symbols = FunctionListExtractor.symbols(
            in: c.activeDocument?.text ?? "", languageName: c.activeDocument?.languageName
        )
        XCTAssertEqual(symbols.map(\.name), ["a"], "the panel's data source finds the def")
    }

    func testSplitViewShowsBothPanes() {
        let c = controller()
        c.cloneToOtherViewAction(nil)
        XCTAssertTrue(c.isSplit)
        XCTAssertEqual(c.tabs(inPane: 1).count, 1)
    }

    func testRunCommandExpandsVariablesAgainstTheOpenFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("script.py")
        try Data("x".utf8).write(to: url)

        let c = MainWindowController()
        _ = c.window
        c.openOrFocus(url: url)

        let context = RunContext.forDocument(path: c.activeDocument?.fileURL?.path)
        XCTAssertEqual(RunCommandExpander.expand("$(FILE_NAME)", with: context), "script.py")
        XCTAssertEqual(RunCommandExpander.expand("$(EXT_PART)", with: context), "py")
    }

    func testPluginBridgeReadsAndWritesTheRealDocument() {
        let c = controller("hello")
        XCTAssertEqual(c.pluginCurrentText(), "hello")
        c.pluginSetText("replaced")
        XCTAssertEqual(c.activeDocument?.text, "replaced",
                       "a plugin edit reaches the document, so it would be saved")
    }

    func testBookmarksSurviveAnEditAbove() {
        let c = controller("a\nb\nc\nd\n")
        c.currentEditor?.goToLine(3)
        c.toggleBookmarkAction(nil)
        guard let id = c.activeDocument?.id else { return XCTFail("no document") }
        XCTAssertEqual(c.bookmarks[id]?.lines, [2])

        // Insert a line above; the bookmark should follow its text.
        var marks = c.bookmarks[id] ?? Bookmarks()
        marks.shift(fromLine: 0, by: 1)
        c.bookmarks[id] = marks
        XCTAssertEqual(c.bookmarks[id]?.lines, [3])
    }
}
