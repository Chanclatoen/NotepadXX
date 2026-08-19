import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Auto-close asserted through the editor: what the document holds and where
/// the caret ends up after typing.
@MainActor
final class AutoCloseEditorTests: XCTestCase {
    private func editor(closingBrackets: Bool = true, closingTags: Bool = true) -> EditorViewController {
        let controller = EditorViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        controller.view.layoutSubtreeIfNeeded()
        controller.load(text: "")
        controller.closeBracketsEnabled = closingBrackets
        controller.closeTagsEnabled = closingTags
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    /// Types a string one character at a time, as a person would.
    private func type(_ text: String, into controller: EditorViewController) {
        for character in text {
            controller.replaceSelection(with: String(character))
        }
    }

    func testTypingAnOpeningBracketClosesItAndKeepsTheCaretInside() {
        let controller = editor()
        type("call(", into: controller)
        XCTAssertEqual(controller.text, "call()")
        XCTAssertEqual(controller.selectedRange.location, 5, "the caret sits between the pair")
    }

    func testTypingTheCloserStepsOverIt() {
        let controller = editor()
        type("call()", into: controller)
        XCTAssertEqual(controller.text, "call()", "no second closer is added")
        XCTAssertEqual(controller.selectedRange.location, 6)
    }

    func testAnApostropheIsNotClosed() {
        let controller = editor()
        type("don't", into: controller)
        XCTAssertEqual(controller.text, "don't")
    }

    func testTagsAreClosed() {
        let controller = editor()
        type("<div>", into: controller)
        XCTAssertEqual(controller.text, "<div></div>")
        XCTAssertEqual(controller.selectedRange.location, 5, "the caret sits between the tags")
    }

    func testVoidElementsAreNotClosed() {
        let controller = editor()
        type("<br>", into: controller)
        XCTAssertEqual(controller.text, "<br>")
    }

    func testTheSettingTurnsItOff() {
        let controller = editor(closingBrackets: false, closingTags: false)
        type("call(", into: controller)
        XCTAssertEqual(controller.text, "call(")
        type("<div>", into: controller)
        XCTAssertEqual(controller.text, "call(<div>")
    }

    /// The setting reaches the editor from Preferences.
    func testThePreferenceReachesTheEditor() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        var preferences = Preferences()
        preferences.closeBracketsAndQuotes = false
        preferences.closeTags = false
        controller.applyPreferences(preferences)
        XCTAssertEqual(controller.currentEditor?.closeBracketsEnabled, false)
        XCTAssertEqual(controller.currentEditor?.closeTagsEnabled, false)

        preferences.closeBracketsAndQuotes = true
        preferences.closeTags = true
        controller.applyPreferences(preferences)
        XCTAssertEqual(controller.currentEditor?.closeBracketsEnabled, true)
        XCTAssertEqual(controller.currentEditor?.closeTagsEnabled, true)
    }
}

/// Inserting text programmatically has to leave the caret after it, or two
/// insertions land in the wrong order.
@MainActor
final class ProgrammaticInsertionTests: XCTestCase {
    private func make() -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 900, height: 600))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    func testTwoInsertionsKeepTheirOrder() throws {
        let editor = try XCTUnwrap(make().currentEditor)
        editor.replaceSelection(with: "first ")
        editor.replaceSelection(with: "second")
        XCTAssertEqual(editor.text, "first second")
    }

    /// A macro that types a word must produce that word.
    func testAMacroTypingAWordProducesIt() throws {
        let controller = make()
        let editor = try XCTUnwrap(controller.currentEditor)
        for character in "hello" { controller.macroInsertText(String(character)) }
        XCTAssertEqual(editor.text, "hello")
    }

    /// A case change leaves the same text selected, so it can be changed again.
    func testATransformKeepsItsTextSelected() throws {
        let controller = make()
        let editor = try XCTUnwrap(controller.currentEditor)
        editor.replaceAll(with: "hello world")
        editor.selectedRange = NSRange(location: 0, length: 5)

        controller.convertUpperCaseAction(nil)
        XCTAssertEqual(editor.text, "HELLO world")
        XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 5),
                       "the transformed text stays selected")
    }
}
