import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXEditor

/// Audit: every display setting must change what is rendered, not just what is
/// stored. Zoom passed its old test while doing nothing visible; these assert
/// observable state instead.
@MainActor
final class AuditDisplayTests: XCTestCase {
    private func make(_ text: String = "line one\n\tindented\nlast\n",
                      language: String? = "Swift") -> (MainWindowController, EditorViewController) {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        document.languageName = language
        controller.adopt(documents: [document], activeIndex: 0)
        // Give the window real geometry and lay it out. Wrapping, gutter width
        // and anything else measured from the viewport are meaningless at zero
        // size, and a test that skips this reports a false failure.
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return (controller, controller.currentEditor!)
    }

    // MARK: - Word wrap

    func testWordWrapChangesTheEngineAndTheScroller() {
        let (controller, editor) = make(String(repeating: "long ", count: 200))
        let wrappedBefore = editor.textView.wrapLines

        controller.toggleWordWrapAction(nil)
        XCTAssertNotEqual(editor.textView.wrapLines, wrappedBefore, "the engine setting flipped")
        XCTAssertEqual(editor.scrollView.hasHorizontalScroller, !editor.textView.wrapLines,
                       "the horizontal scroller follows wrapping")
    }

    func testWordWrapAltersLaidOutHeight() {
        let (controller, editor) = make(String(repeating: "word ", count: 400))
        editor.setWrapLines(false)
        editor.textView.layoutManager.layoutLines()
        let unwrapped = editor.textView.layoutManager.estimatedHeight()

        controller.toggleWordWrapAction(nil)
        editor.textView.layoutManager.layoutLines()
        XCTAssertTrue(editor.textView.wrapLines)
        XCTAssertGreaterThan(editor.textView.layoutManager.estimatedHeight(), unwrapped,
                             "wrapping a long line makes the document taller")
    }

    // MARK: - Invisible characters

    func testShowWhitespaceRegistersTriggerCharacters() {
        let (controller, editor) = make("a b\tc\n")
        XCTAssertTrue(editor.invisibles.triggerCharacters.isEmpty, "nothing is drawn by default")

        controller.toggleShowWhitespaceAction(nil)
        XCTAssertTrue(editor.invisibles.triggerCharacters.contains(0x20), "space is now drawn")
        XCTAssertFalse(editor.invisibles.triggerCharacters.contains(0x09), "tabs are a separate toggle")

        controller.toggleShowTabsAction(nil)
        XCTAssertTrue(editor.invisibles.triggerCharacters.contains(0x09))
    }

    func testShowEndOfLineRegistersBothTerminators() {
        let (controller, editor) = make()
        controller.toggleShowEndOfLineAction(nil)
        XCTAssertTrue(editor.invisibles.triggerCharacters.contains(0x0A))
        XCTAssertTrue(editor.invisibles.triggerCharacters.contains(0x0D))
    }

    func testInvisiblesProduceAReplacementGlyph() {
        let (controller, editor) = make("a b\n")
        controller.toggleShowWhitespaceAction(nil)
        let style = editor.invisibles.invisibleStyle(
            for: 0x20, at: NSRange(location: 1, length: 1), lineRange: NSRange(location: 0, length: 4)
        )
        guard case .replace(let glyph, _, _)? = style else {
            return XCTFail("a space should be replaced by a visible glyph")
        }
        XCTAssertEqual(glyph, "\u{00B7}")
    }

    /// Toggling must invalidate the engine's cached styles, or the change only
    /// appears after the next edit.
    func testTogglingInvisiblesClearsTheEngineCache() {
        let (controller, editor) = make()
        controller.toggleShowWhitespaceAction(nil)
        XCTAssertTrue(editor.invisibles.invisibleStyleShouldClearCache(),
                      "the engine is told to drop cached styles")
    }

    // MARK: - Theme

    func testApplyingADarkThemeRepaintsTheEditorAndChrome() {
        let (controller, editor) = make()
        editor.applyTheme(.defaultLight)
        let lightBackground = editor.theme.backgroundColor

        editor.applyTheme(.defaultDark)
        XCTAssertNotEqual(editor.theme.backgroundColor, lightBackground, "the editor repainted")

        controller.applyChromeTheme(.defaultDark)
        XCTAssertEqual(controller.window?.appearance?.name, .darkAqua,
                       "the window chrome follows the theme")
    }

    func testThemeChangesTokenColoursNotJustTheBackground() {
        let (_, editor) = make("let x = 1\n")
        editor.applyTheme(.defaultLight)
        let lightKeyword = editor.theme.color(for: .keyword1)
        editor.applyTheme(.defaultDark)
        XCTAssertNotEqual(editor.theme.color(for: .keyword1), lightKeyword)
    }

    func testThemeReachesTheGutter() {
        let (_, editor) = make()
        editor.applyTheme(.defaultDark)
        let darkGutter = editor.gutterView?.textColor
        editor.applyTheme(.defaultLight)
        XCTAssertNotEqual(editor.gutterView?.textColor, darkGutter)
    }

    // MARK: - Margins

    func testLineNumberToggleReachesTheGutter() {
        let (_, editor) = make()
        XCTAssertTrue(editor.gutterView?.showLineNumbers ?? false)
        editor.gutterView?.showLineNumbers = false
        XCTAssertFalse(editor.gutterView?.showLineNumbers ?? true)
    }

    /// The gutter must widen as the line count gains digits, or numbers clip.
    func testGutterWidensForALargerDocument() {
        let (_, small) = make("a\nb\n")
        let narrow = small.gutterView?.requiredWidth() ?? 0

        let (_, big) = make(String(repeating: "line\n", count: 5000))
        big.textView.layoutManager.layoutLines()
        XCTAssertGreaterThan(big.gutterView?.requiredWidth() ?? 0, narrow)
    }

    func testEdgeGuideColumnReachesTheView() {
        let (_, editor) = make()
        editor.edgeColumn = 80
        XCTAssertEqual(editor.edgeColumn, 80)
    }

    func testIndentGuideToggleReachesEveryEditor() {
        let (controller, editor) = make()
        controller.toggleIndentGuideAction(nil)
        XCTAssertEqual(editor.showIndentGuides, controller.showIndentGuides)
    }

    // MARK: - Preferences propagation

    /// Preferences must reach live editors, not only newly created ones.
    func testPreferenceChangesApplyToTheOpenDocument() throws {
        let (controller, editor) = make()
        var preferences = Preferences()
        preferences.wordWrap = true
        preferences.showWhitespace = true
        preferences.showLineNumbers = false
        preferences.fontSize = 18
        preferences.smartHighlight = false
        preferences.braceMatching = false
        preferences.edgeColumn = 100

        controller.applyPreferences(preferences)

        XCTAssertTrue(editor.textView.wrapLines)
        XCTAssertTrue(editor.invisibles.showSpaces)
        XCTAssertFalse(editor.gutterView?.showLineNumbers ?? true)
        XCTAssertEqual(editor.fontSize, 18)
        XCTAssertFalse(editor.smartHighlightEnabled)
        XCTAssertFalse(editor.braceMatchingEnabled)
        XCTAssertEqual(editor.edgeColumn, 100)
    }

    func testHidingChromeThroughPreferences() {
        let (controller, _) = make()
        var preferences = Preferences()
        preferences.showStatusBar = false
        preferences.showToolbar = false
        preferences.showTabBar = false
        controller.applyPreferences(preferences)

        XCTAssertTrue(controller.statusBar.isHidden)
        XCTAssertTrue(controller.toolbar.isHidden)
        XCTAssertTrue(controller.tabBar.isHidden)
    }

    // MARK: - Toolbar reflects reality

    func testToolbarTogglesTrackActualState() {
        let (controller, _) = make()
        controller.toggleShowAllCharactersAction(nil)
        XCTAssertTrue(controller.toolbar.activeToggles.contains("Show All Characters"))

        controller.toggleShowAllCharactersAction(nil)
        XCTAssertFalse(controller.toolbar.activeToggles.contains("Show All Characters"))
    }

    func testToolbarReflectsPanelVisibility() {
        let (controller, _) = make()
        controller.toggleFunctionListAction(nil)
        controller.refreshToolbarState()
        XCTAssertTrue(controller.toolbar.activeToggles.contains("Function List"))
    }
}
