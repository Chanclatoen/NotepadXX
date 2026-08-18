import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXEditor

/// Zoom used to change the setting without moving the text: the highlighter
/// writes an explicit .font attribute onto every token, and line heights are
/// cached, so neither noticed a new typing font. These assert the rendered
/// result, not the stored preference.
@MainActor
final class ZoomTests: XCTestCase {
    private func makeController() -> (MainWindowController, EditorViewController) {
        let controller = MainWindowController()
        let document = TextDocument(text: "let x = 1\nlet y = 2\nlet z = 3\n")
        document.languageName = "Swift"
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        return (controller, controller.currentEditor!)
    }

    private func renderedFontSize(_ editor: EditorViewController) -> CGFloat? {
        guard let storage = editor.textView.textStorage, storage.length > 0 else { return nil }
        return (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
    }

    func testZoomInEnlargesTheRenderedText() {
        let (controller, editor) = makeController()
        let heightBefore = editor.textView.layoutManager.estimatedHeight()

        controller.zoomInAction(nil)

        XCTAssertEqual(renderedFontSize(editor), 13, "existing text is re-rendered, not just new text")
        XCTAssertGreaterThan(editor.textView.layoutManager.estimatedHeight(), heightBefore,
                             "line heights were re-measured, so the text actually moves")
    }

    func testZoomOutShrinksTheRenderedText() {
        let (controller, editor) = makeController()
        let heightBefore = editor.textView.layoutManager.estimatedHeight()

        controller.zoomOutAction(nil)

        XCTAssertEqual(renderedFontSize(editor), 11)
        XCTAssertLessThan(editor.textView.layoutManager.estimatedHeight(), heightBefore)
    }

    func testZoomRestoreReturnsToTheDefaultSize() {
        let (controller, editor) = makeController()
        for _ in 0..<5 { controller.zoomInAction(nil) }
        XCTAssertEqual(renderedFontSize(editor), 17)

        controller.zoomRestoreAction(nil)
        XCTAssertEqual(controller.editorFontSize, 12)
        XCTAssertEqual(renderedFontSize(editor), 12)
    }

    func testZoomClampsAndStillRenders() {
        let (controller, editor) = makeController()
        for _ in 0..<200 { controller.zoomInAction(nil) }
        XCTAssertEqual(controller.editorFontSize, 96)
        XCTAssertEqual(renderedFontSize(editor), 96, "the clamped size is what renders")

        for _ in 0..<400 { controller.zoomOutAction(nil) }
        XCTAssertEqual(controller.editorFontSize, 6)
        XCTAssertEqual(renderedFontSize(editor), 6)
    }

    /// Notepad++ scales the line numbers with the text; a fixed gutter next to
    /// 40pt text looks broken.
    func testGutterScalesWithZoom() {
        let (controller, editor) = makeController()
        let before = editor.gutterView?.font.pointSize ?? 0
        for _ in 0..<8 { controller.zoomInAction(nil) }
        XCTAssertGreaterThan(editor.gutterView?.font.pointSize ?? 0, before)
    }

    /// Zoom applies to every open editor, not only the focused one.
    func testZoomAppliesToAllOpenDocuments() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "a"), TextDocument(text: "b")],
                         activeIndex: 0)
        _ = controller.window
        controller.selectTab(at: 1)   // realise the second editor
        controller.selectTab(at: 0)

        controller.zoomInAction(nil)
        XCTAssertTrue(controller.allEditors.allSatisfy { $0.fontSize == 13 })
    }

    func testTypingAfterZoomKeepsTheNewSize() {
        let (controller, editor) = makeController()
        controller.zoomInAction(nil)
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.textView.insertText("Z", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(renderedFontSize(editor), 13, "newly typed text matches the zoomed size")
    }
}
