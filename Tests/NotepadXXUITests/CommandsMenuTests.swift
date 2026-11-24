import XCTest
import AppKit
import NotepadXXEditor
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The commands that used to exist in no menu (comment toggling, indent,
/// split lines, reload, save a copy, print), driven through the controller.
@MainActor
final class CommandsMenuTests: XCTestCase {
    private func makeController(_ text: String, language: String? = nil,
                                url: URL? = nil) -> (MainWindowController, TextDocument) {
        MainWindowController.presentsAlerts = false
        let controller = MainWindowController()
        let document = TextDocument(fileURL: url, text: text)
        document.languageName = language
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        return (controller, document)
    }

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-cmds-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name)
    }

    // MARK: - Reachable in menus

    private func items(_ title: String) throws -> [NSMenuItem] {
        let root = MainMenu.build()
        let top = try XCTUnwrap(root.items.first { $0.title == title }?.submenu, "no \(title) menu")
        func walk(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(walk) ?? []) }
        }
        return walk(top)
    }

    func testTheSevenCommandsAreInTheMenus() throws {
        let file = try items("File"), edit = try items("Edit")
        let expectations: [(String, [NSMenuItem], Selector)] = [
            ("Toggle Line Comment", edit, #selector(MainWindowController.toggleLineCommentAction(_:))),
            ("Toggle Block Comment", edit, #selector(MainWindowController.toggleBlockCommentAction(_:))),
            ("Indent", edit, #selector(MainWindowController.indentLinesAction(_:))),
            ("Unindent", edit, #selector(MainWindowController.unindentLinesAction(_:))),
            ("Split Lines", edit, #selector(MainWindowController.splitLinesAction(_:))),
            ("Reload from Disk", file, #selector(MainWindowController.reloadFromDiskAction(_:))),
            ("Save a Copy As…", file, #selector(MainWindowController.saveACopyAsAction(_:))),
            ("Print…", file, #selector(MainWindowController.printDocumentAction(_:))),
        ]
        for (title, menu, action) in expectations {
            let item = try XCTUnwrap(menu.first { $0.title == title }, "\(title) is not in a menu")
            XCTAssertEqual(item.action, action, title)
        }
    }

    func testNoTwoMenuItemsShareAShortcut() {
        var seen: [String: String] = [:]
        func walk(_ menu: NSMenu, path: String) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    let key = "\(item.keyEquivalentModifierMask.rawValue)+\(item.keyEquivalent)"
                    if let other = seen[key] {
                        XCTFail("\(path)/\(item.title) and \(other) both use \(key)")
                    }
                    seen[key] = "\(path)/\(item.title)"
                }
                if let sub = item.submenu { walk(sub, path: path + "/" + item.title) }
            }
        }
        walk(MainMenu.build(), path: "")
        XCTAssertFalse(seen.isEmpty)
    }

    func testNoCommandTakesTabOrAQuitShortcut() {
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.title != "Quit NotepadXX" {
                    XCTAssertNotEqual(item.keyEquivalent, "q", "\(item.title) would collide with Quit or Log Out")
                }
                XCTAssertNotEqual(item.keyEquivalent, "\t", "\(item.title) would take Tab away from typing")
                if let sub = item.submenu { walk(sub) }
            }
        }
        walk(MainMenu.build())
    }

    // MARK: - Comments

    func testToggleLineCommentUsesTheLanguagesToken() throws {
        let (swift, swiftDoc) = makeController("let a = 1\nlet b = 2\n", language: "Swift")
        swift.currentEditor?.selectedRange = NSRange(location: 0, length: 12)
        swift.toggleLineCommentAction(nil)
        XCTAssertEqual(swiftDoc.text, "// let a = 1\n// let b = 2\n")
        swift.toggleLineCommentAction(nil)
        XCTAssertEqual(swiftDoc.text, "let a = 1\nlet b = 2\n", "the selection still covers both lines, so it toggles back")

        let (python, pythonDoc) = makeController("x = 1\n", language: "Python")
        python.toggleLineCommentAction(nil)
        XCTAssertEqual(pythonDoc.text, "# x = 1\n")
    }

    func testToggleBlockCommentWrapsTheSelection() {
        let (controller, document) = makeController("int a; int b;", language: "C")
        controller.currentEditor?.selectedRange = NSRange(location: 7, length: 6)
        controller.toggleBlockCommentAction(nil)
        XCTAssertEqual(document.text, "int a; /* int b; */")
        controller.toggleBlockCommentAction(nil)
        XCTAssertEqual(document.text, "int a; int b;")
    }

    func testALanguageWithOnlyBlockCommentsWrapsTheLines() {
        let (controller, document) = makeController("<p>hi</p>\n", language: "HTML")
        controller.toggleLineCommentAction(nil)
        XCTAssertEqual(document.text, "<!-- <p>hi</p> -->\n")
    }

    func testPlainTextHasNoCommentSyntax() {
        let (controller, document) = makeController("plain\n", language: nil)
        controller.toggleLineCommentAction(nil)
        XCTAssertEqual(document.text, "plain\n")
        XCTAssertFalse(document.isDirty)
    }

    // MARK: - Indent and split

    func testIndentAndUnindentTheSelectedLines() {
        let (controller, document) = makeController("a\nb\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        controller.indentLinesAction(nil)
        let indented = document.text
        XCTAssertTrue(indented.hasPrefix("\ta\n\tb\nc") || indented.hasPrefix("    a\n    b\nc"), indented)
        controller.unindentLinesAction(nil)
        XCTAssertEqual(document.text, "a\nb\nc\n")
    }

    func testSplitLinesBreaksAtTheEdgeColumn() throws {
        let (controller, document) = makeController(String(repeating: "word ", count: 30) + "\nshort\n")
        let store = try XCTUnwrap(controller.preferencesStore)
        try store.update { $0.edgeColumn = 40 }
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.splitLinesAction(nil)
        let lines = document.text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines.dropLast(2).allSatisfy { $0.count <= 40 }, "\(lines)")
        XCTAssertEqual(lines.suffix(2).first, "short")
    }

    // MARK: - File commands

    func testReloadFromDiskPicksUpTheChangedFile() throws {
        let url = tempURL("r.txt")
        try "one\n".write(to: url, atomically: true, encoding: .utf8)
        let (controller, document) = makeController("one\n", url: url)
        try "two\nthree\n".write(to: url, atomically: true, encoding: .utf8)

        // A clean document reloads without asking; one with edits asks first.
        controller.reloadFromDiskAction(nil)

        XCTAssertEqual(document.text, "two\nthree\n")
        XCTAssertEqual(controller.currentEditor?.text, "two\nthree\n")
        XCTAssertFalse(document.isDirty)
    }

    func testSaveACopyWritesANewFileAndLeavesTheDocumentAlone() throws {
        let original = tempURL("orig.txt")
        try "one\n".write(to: original, atomically: true, encoding: .utf8)
        let (controller, document) = makeController("one\n", url: original)
        controller.currentEditor?.replaceAll(with: "changed\n")
        controller.currentEditor?.onEdit?()
        let copy = tempURL("copy.txt")

        controller.writeCopy(of: document, to: copy)

        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "changed\n")
        XCTAssertEqual(document.fileURL, original, "the document keeps its own file")
        XCTAssertTrue(document.isDirty, "and its unsaved state")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "one\n")
    }

    func testPrintableTextIsTheWholeDocumentWithLFEndings() {
        let (controller, document) = makeController("a\nb\n")
        document.lineEnding = .crlf
        XCTAssertEqual(controller.printableText(for: document), "a\nb\n")
    }
}
