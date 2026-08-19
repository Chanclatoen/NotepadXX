import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXEditor

@MainActor
final class AutoIndentWiringTests: XCTestCase {
    private func make(_ text: String, language: LanguageDefinition? = BuiltInLanguages.swift)
        -> (MainWindowController, EditorViewController) {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        document.languageName = language?.name
        controller.adopt(documents: [document], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        let editor = controller.currentEditor!
        editor.setLanguage(language)
        return (controller, editor)
    }

    /// Pressing Return keeps the indentation of the line above.
    func testReturnKeepsIndentation() {
        let (_, editor) = make("    let x = 1")
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.textView.insertText("\n", replacementRange: editor.selectedRange)
        XCTAssertTrue(editor.text.hasSuffix("\n    "), "got: \(editor.text.debugDescription)")
    }

    func testReturnAfterABraceIndentsFurther() {
        let (_, editor) = make("func a() {")
        editor.indentUsesSpaces = true
        editor.indentWidth = 4
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.textView.insertText("\n", replacementRange: editor.selectedRange)
        XCTAssertTrue(editor.text.hasSuffix("\n    "), "got: \(editor.text.debugDescription)")
    }

    func testDisablingAutoIndentLeavesTheLineBare() {
        let (_, editor) = make("    let x = 1")
        editor.autoIndentEnabled = false
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.textView.insertText("\n", replacementRange: editor.selectedRange)
        XCTAssertTrue(editor.text.hasSuffix("\n"), "no indent was added")
        XCTAssertFalse(editor.text.hasSuffix("\n    "))
    }

    /// Inserting the indent triggers the change handler again; without a guard
    /// this recurses until the stack blows.
    func testAutoIndentDoesNotRecurse() {
        let (_, editor) = make("    x")
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.textView.insertText("\n", replacementRange: editor.selectedRange)
        XCTAssertEqual(editor.text, "    x\n    ", "exactly one indent was inserted")
    }

    func testPreferencesDriveAutoIndent() {
        let (controller, editor) = make("x")
        var preferences = Preferences()
        preferences.autoIndent = false
        preferences.replaceTabsBySpaces = true
        preferences.tabWidth = 2
        controller.applyPreferences(preferences)

        XCTAssertFalse(editor.autoIndentEnabled)
        XCTAssertTrue(editor.indentUsesSpaces)
        XCTAssertEqual(editor.indentWidth, 2)
    }
}

@MainActor
final class SyncScrollTests: XCTestCase {
    private func splitController() -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: String(repeating: "line\n", count: 500)),
                                     TextDocument(text: String(repeating: "other\n", count: 500))],
                         activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 1200, height: 700))
        window.contentView?.layoutSubtreeIfNeeded()
        controller.selectTab(at: 1)
        controller.moveToOtherViewAction(nil)
        controller.selectTab(at: 0)
        window.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    func testSyncIsOffByDefault() {
        let c = splitController()
        XCTAssertFalse(c.syncVerticalScroll)
        XCTAssertFalse(c.syncHorizontalScroll)
    }

    func testTogglingArmsAndDisarmsObservers() {
        let c = splitController()
        c.toggleSyncVerticalScrollAction(nil)
        XCTAssertTrue(c.syncVerticalScroll)
        XCTAssertFalse(c.scrollSyncObservers.isEmpty, "observers were installed")

        c.toggleSyncVerticalScrollAction(nil)
        XCTAssertFalse(c.syncVerticalScroll)
        XCTAssertTrue(c.scrollSyncObservers.isEmpty, "observers were removed")
    }

    func testBothPanesAreObservedWhenSplit() {
        let c = splitController()
        XCTAssertEqual(c.visiblePaneEditors.count, 2, "a split has two visible editors")
        c.toggleSyncVerticalScrollAction(nil)
        XCTAssertEqual(c.scrollSyncObservers.count, 2)
    }

    func testNoObserversWithoutASplit() {
        let c = MainWindowController()
        c.adopt(documents: [TextDocument(text: "a")], activeIndex: 0)
        _ = c.window
        c.toggleSyncVerticalScrollAction(nil)
        XCTAssertTrue(c.scrollSyncObservers.isEmpty, "nothing to sync with one pane")
    }
}

@MainActor
final class DocumentSwitcherTests: XCTestCase {
    private func make(_ names: [String]) -> MainWindowController {
        let controller = MainWindowController()
        let documents = names.map { name -> TextDocument in
            let document = TextDocument(text: "x")
            document.untitledName = name
            return document
        }
        controller.adopt(documents: documents, activeIndex: 0)
        _ = controller.window
        return controller
    }

    /// The point of Ctrl+Tab: the previous document is one press away.
    func testMRUPutsTheMostRecentFirst() {
        let c = make(["a", "b", "c"])
        c.selectTab(at: 2)
        c.selectTab(at: 1)
        let order = c.mruOrder
        XCTAssertEqual(order.first, 1, "the current document leads")
        XCTAssertEqual(order.dropFirst().first, 2, "then the one before it")
    }

    func testEveryTabAppearsExactlyOnce() {
        let c = make(["a", "b", "c", "d"])
        c.selectTab(at: 3)
        c.selectTab(at: 1)
        let order = c.mruOrder
        XCTAssertEqual(order.count, 4)
        XCTAssertEqual(Set(order).count, 4, "no duplicates or omissions")
    }

    func testSwitcherSelectsAnotherDocument() {
        let c = make(["a", "b"])
        c.selectTab(at: 1)
        c.selectTab(at: 0)
        c.showDocumentSwitcherAction(nil)
        // Row 1 is the previous document in MRU order.
        c.documentSwitcher?.onChoose?(1)
        XCTAssertEqual(c.activeDocument?.displayName, "b")
    }

    func testSwitcherWrapsWhenCycling() {
        let panel = DocumentSwitcherPanel()
        panel.present(entries: [("a", ""), ("b", "")], selecting: 0)
        panel.moveSelection(by: -1)   // wraps to the end
        var chosen: Int?
        panel.onChoose = { chosen = $0 }
        panel.choose()
        XCTAssertEqual(chosen, 1, "moving up from the first wraps to the last")
    }

    func testSwitcherIsUselessWithOneTabAndSaysSo() {
        let c = make(["only"])
        c.showDocumentSwitcherAction(nil)
        XCTAssertNil(c.documentSwitcher, "no switcher for a single document")
    }
}
