import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXEditor

/// These features all had a working engine that nothing called. The tests here
/// assert the wiring, not the engine — a green engine test told us nothing
/// about whether the feature actually happened.
@MainActor
final class ConnectedFeatureTests: XCTestCase {
    private func controller(_ text: String = "", language: String? = nil) -> MainWindowController {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        document.languageName = language
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        return controller
    }

    // MARK: - Macro recording

    func testTypingIsRecordedWhileAMacroIsCapturing() {
        let controller = self.controller("")
        controller.toggleMacroRecordingAction(nil)
        controller.currentEditor?.textView.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
        controller.toggleMacroRecordingAction(nil)

        XCTAssertEqual(controller.lastRecordedSteps, [.insertText("abc")],
                       "the recorder actually saw the typing")
    }

    func testNothingIsRecordedWhenNotCapturing() {
        let controller = self.controller("")
        controller.currentEditor?.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(controller.lastRecordedSteps.isEmpty)
    }

    func testRecordedMacroReplaysIntoTheDocument() {
        let controller = self.controller("")
        controller.toggleMacroRecordingAction(nil)
        controller.currentEditor?.textView.insertText("hi ", replacementRange: NSRange(location: 0, length: 0))
        controller.toggleMacroRecordingAction(nil)

        let before = controller.currentEditor?.text ?? ""
        controller.playbackMacroAction(nil)
        XCTAssertEqual(controller.currentEditor?.text, before + "hi ")
    }

    // MARK: - Folding

    func testFoldingHidesTheRegionBodyAndUnfoldingRestoresIt() {
        let source = "func a() {\n    one\n    two\n}\nafter\n"
        let controller = self.controller(source, language: "Swift")
        controller.currentEditor?.setLanguage(BuiltInLanguages.swift)

        controller.toggleFold(atLine: 0)
        let folded = controller.currentEditor?.text ?? ""
        XCTAssertFalse(folded.contains("one"), "the body is hidden")
        XCTAssertTrue(folded.contains("func a() {"), "the header stays visible")
        XCTAssertTrue(folded.contains("after"), "text after the fold is untouched")

        controller.toggleFold(atLine: 0)
        XCTAssertEqual(controller.currentEditor?.text, source, "unfolding restores exactly")
    }

    /// A folded region is physically absent from the buffer, so saving while
    /// folded would write a truncated file.
    func testSavingUnfoldsFirstSoNoLinesAreLost() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-fold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("f.swift")
        let source = "func a() {\n    body\n}\n"
        try Data(source.utf8).write(to: url)

        let controller = MainWindowController()
        _ = controller.window
        XCTAssertTrue(controller.openOrFocus(url: url))
        controller.toggleFold(atLine: 0)
        XCTAssertFalse(controller.currentEditor?.text.contains("body") ?? true)

        controller.saveDocumentAction(nil)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("body"),
                      "the folded line is on disk, not lost")
    }

    func testFoldMarkersAppearForAFoldableDocument() {
        let controller = self.controller("func a() {\n    x\n}\n", language: "Swift")
        controller.currentEditor?.setLanguage(BuiltInLanguages.swift)
        controller.currentEditor?.refreshFoldMarkers()
        XCTAssertTrue(controller.currentEditor?.gutterView?.foldStartLines.contains(0) ?? false)
    }

    // MARK: - Autocomplete

    /// Types one character at a time, as a keyboard does. A multi-character
    /// insert is a paste and deliberately does not open the list.
    private func type(_ text: String, into editor: EditorViewController) {
        for character in text {
            let caret = editor.selectedRange.location
            editor.textView.insertText(String(character),
                                       replacementRange: NSRange(location: caret, length: 0))
        }
    }

    func testTypingEnoughCharactersOffersSuggestions() {
        let controller = self.controller("widget wonderful\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.autoCompleteMinimumCharacters = 3

        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        type("wid", into: editor)

        XCTAssertTrue(editor.completionPopup.isVisible, "the list appeared")
        XCTAssertTrue(editor.completionPopup.selectedItem?.text.hasPrefix("wid") ?? false)
    }

    func testPastingDoesNotOpenTheList() {
        let controller = self.controller("widget\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.autoCompleteMinimumCharacters = 3
        let end = (editor.text as NSString).length
        editor.selectedRange = NSRange(location: end, length: 0)
        // A multi-character insert is a paste.
        editor.textView.insertText("widget", replacementRange: NSRange(location: end, length: 0))
        XCTAssertFalse(editor.completionPopup.isVisible)
    }

    func testTooFewCharactersDoesNotOfferSuggestions() {
        let controller = self.controller("widget\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.autoCompleteMinimumCharacters = 4
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        type("wi", into: editor)
        XCTAssertFalse(editor.completionPopup.isVisible)
    }

    func testDisablingAutocompleteSuppressesTheList() {
        let controller = self.controller("widget\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.autoCompleteEnabled = false
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        type("wid", into: editor)
        XCTAssertFalse(editor.completionPopup.isVisible)
    }

    /// Accepting a suggestion must replace the typed prefix, not append to it.
    func testCommittingACompletionReplacesThePrefix() {
        let controller = self.controller("widget\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        type("wid", into: editor)

        editor.insertCompletion("widget")
        XCTAssertTrue(editor.text.hasSuffix("widget"), "the prefix became the full word")
        XCTAssertFalse(editor.text.hasSuffix("widwidget"), "the prefix was replaced, not appended")
    }

    func testApiEntriesReachTheEditorForCallTips() {
        let controller = self.controller("", language: "C")
        XCTAssertFalse(controller.currentEditor?.completionEntries.isEmpty ?? true,
                       "the editor was given the language's API data")
    }
}
