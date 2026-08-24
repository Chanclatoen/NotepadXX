import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Clipboard behaviour, the caret margin and the large-file threshold, checked
/// by what they do rather than by the flag that turns them on.
@MainActor
final class ClipboardBehaviourTests: XCTestCase {
    func testCopyingWithNoSelectionTakesTheWholeLine() {
        let text = "first line\nsecond line\nthird line\n"
        let range = ClipboardBehaviour.lineRange(around: 14, in: text)   // inside "second"
        XCTAssertEqual((text as NSString).substring(with: range), "second line\n",
                       "the newline comes too, so pasting puts back a whole line")
    }

    func testTrailingWhitespaceIsTrimmedFromEveryPastedLine() {
        let pasted = "one   \ntwo\t\t\nthree \n"
        XCTAssertEqual(ClipboardBehaviour.trimmingTrailingWhitespace(pasted), "one\ntwo\nthree\n")
    }

    /// Trimming must not damage characters that are more than one UTF-16 unit.
    func testTrimmingPreservesAstralCharacters() {
        let pasted = "  😀 café   \n\t🇳🇱 tail\t"
        let trimmed = ClipboardBehaviour.trimmingTrailingWhitespace(pasted)
        XCTAssertTrue(trimmed.contains("😀"), "an emoji was damaged: \(trimmed)")
        XCTAssertTrue(trimmed.contains("🇳🇱"), "a flag was damaged: \(trimmed)")
        XCTAssertTrue(trimmed.contains("café"))
        XCTAssertFalse(trimmed.hasSuffix("\t"))
    }

    func testTrimmingLeavesIndentationAlone() {
        let pasted = "    indented   \n\ttabbed\t"
        XCTAssertEqual(ClipboardBehaviour.trimmingTrailingWhitespace(pasted), "    indented\n\ttabbed")
    }

    /// The text view actually uses the rules.
    func testTheEditorCopiesTheWholeLine() throws {
        let controller = EditorViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        controller.view.layoutSubtreeIfNeeded()
        controller.load(text: "first line\nsecond line\n")
        controller.copiesWholeLineWhenEmpty = true
        controller.selectedRange = NSRange(location: 14, length: 0)

        NSPasteboard.general.clearContents()
        let view = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? NSScrollView }
            .first?.documentView as? NotepadTextView)
        view.copy(self)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "second line\n")
    }
}

/// A file too large to edit comfortably opens view-only.
@MainActor
final class LargeFileTests: XCTestCase {
    func testAFileOverTheThresholdOpensReadOnly() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-large-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        // Just over 1 MB.
        try String(repeating: "x", count: 1_100_000).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let store = try XCTUnwrap(controller.preferencesStore)
        let saved = store.preferences
        defer { try? store.update { $0 = saved } }
        try store.update { $0.readOnlyAboveMegabytes = 1 }

        XCTAssertTrue(controller.openOrFocus(url: url))
        XCTAssertTrue(controller.activeDocument?.isReadOnly ?? false,
                      "a file over the limit opens view-only")
    }

    func testASmallFileOpensEditable() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-small-\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try "small".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "")], activeIndex: 0)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let store = try XCTUnwrap(controller.preferencesStore)
        let saved = store.preferences
        defer { try? store.update { $0 = saved } }
        try store.update { $0.readOnlyAboveMegabytes = 1 }

        XCTAssertTrue(controller.openOrFocus(url: url))
        XCTAssertFalse(controller.activeDocument?.isReadOnly ?? true)
    }
}
