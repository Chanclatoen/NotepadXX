import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXDesign

@MainActor
final class ToolbarTests: XCTestCase {
    /// A missing SF Symbol silently degrades to the button's title, which shows
    /// as clipped words in the toolbar. This caught exactly that with
    /// "text.wrap", which does not exist.
    func testEveryToolbarSymbolExists() {
        var missing: [String] = []
        for item in ToolbarCatalogue.groups().flatMap({ $0 }) {
            if NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) == nil {
                missing.append("\(item.label): \(item.symbol)")
            }
        }
        XCTAssertTrue(missing.isEmpty, "unknown SF Symbols: \(missing)")
    }

    func testToolbarCoversTheNotepadPlusPlusGroups() {
        let groups = ToolbarCatalogue.groups()
        let labels = groups.flatMap { $0 }.map(\.label)
        for expected in ["New", "Open", "Save", "Save All", "Print", "Cut", "Copy", "Paste",
                         "Undo", "Redo", "Find", "Replace", "Zoom In", "Zoom Out",
                         "Word Wrap", "Document Map", "Function List", "Run…"] {
            XCTAssertTrue(labels.contains(expected), "toolbar is missing \(expected)")
        }
        XCTAssertGreaterThan(groups.count, 5, "buttons are grouped, not one long row")
    }

    func testEveryToolbarButtonHasAnImageAndNoTitle() {
        let toolbar = DSToolbar()
        toolbar.configure(groups: ToolbarCatalogue.groups())
        toolbar.frame = NSRect(x: 0, y: 0, width: 1200, height: DS.Metric.toolbar)
        toolbar.layoutSubtreeIfNeeded()

        // The command buttons only. The overflow control is a menu button and
        // legitimately carries a label.
        func commandButtons(in view: NSView) -> [DSToolbarButton] {
            view.subviews.compactMap { $0 as? DSToolbarButton }
                + view.subviews.flatMap { commandButtons(in: $0) }
        }
        let all = commandButtons(in: toolbar)
        XCTAssertGreaterThan(all.count, 20)
        XCTAssertTrue(all.allSatisfy { $0.image != nil }, "a button with no image renders as text")
        XCTAssertTrue(all.allSatisfy { $0.title.isEmpty }, "titles must not leak into the toolbar")
    }

    func testToggleStateIsReflected() {
        let toolbar = DSToolbar()
        toolbar.configure(groups: ToolbarCatalogue.groups())
        toolbar.activeToggles = ["Word Wrap"]
        XCTAssertTrue(toolbar.activeToggles.contains("Word Wrap"))
    }
}

@MainActor
final class StatusBarTests: XCTestCase {
    private func labels(in view: NSView) -> [String] {
        view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
            + view.subviews.flatMap { labels(in: $0) }
    }

    private func bar(_ model: DSStatusBar.Model, width: CGFloat = 1200) -> DSStatusBar {
        let bar = DSStatusBar()
        bar.frame = NSRect(x: 0, y: 0, width: width, height: DS.Metric.statusBar)
        bar.update(model)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    /// Notepad++ shows six segments; the order and wording are muscle memory.
    func testAllSixSegmentsArePopulated() {
        let text = labels(in: bar(DSStatusBar.Model(
            documentType: "Swift", length: 278, lines: 14,
            caretLine: 1, caretColumn: 1, lineEnding: "Unix (LF)", encoding: "UTF-8"
        ))).joined(separator: " | ")

        XCTAssertTrue(text.contains("Swift"), "document type")
        XCTAssertTrue(text.contains("278"), "length")
        XCTAssertTrue(text.contains("14"), "line count")
        XCTAssertTrue(text.contains("Ln 1"))
        XCTAssertTrue(text.contains("Col 1"))
        XCTAssertTrue(text.contains("Unix (LF)"))
        XCTAssertTrue(text.contains("UTF-8"))
        XCTAssertTrue(text.contains("INS"))
    }

    func testOverwriteModeIsShown() {
        let shown = labels(in: bar(DSStatusBar.Model(isOverwrite: true)))
        XCTAssertTrue(shown.contains("OVR"))
    }

    /// Notepad++ reports a selection as characters and lines.
    func testSelectionShowsCharactersAndLines() {
        let text = labels(in: bar(DSStatusBar.Model(
            documentType: "Swift", length: 100, lines: 10,
            caretLine: 5, caretColumn: 2, selectionCharacters: 42, selectionLines: 3,
            lineEnding: "Windows (CR LF)", encoding: "UTF-8-BOM"
        ))).joined()
        XCTAssertTrue(text.contains("Sel 42 | 3"), "got: \(text)")
    }
}

@MainActor
final class ChromeThemeTests: XCTestCase {
    func testLightThemeUsesAquaAppearance() {
        let chrome = AppearanceTheme.chrome(for: .defaultLight)
        XCTAssertEqual(chrome.appearance?.name, .aqua)
    }

    func testDarkThemeUsesDarkAquaAppearance() {
        let chrome = AppearanceTheme.chrome(for: .defaultDark)
        XCTAssertEqual(chrome.appearance?.name, .darkAqua)
    }

    /// The chrome must differ from the editor background, or the panes read as
    /// one undivided surface.
    func testChromeIsOffsetFromTheEditorBackground() {
        for theme in [EditorTheme.defaultLight, .defaultDark] {
            let chrome = AppearanceTheme.chrome(for: theme)
            XCTAssertNotEqual(chrome.background, chrome.selectedTab)
        }
    }

    func testNoThemeFallsBackToSystemColours() {
        let chrome = AppearanceTheme.chrome(for: nil)
        XCTAssertNil(chrome.appearance, "no theme means follow the system")
    }

    /// The default follows the Mac. Notepad++ ships light, and on a light Mac
    /// this resolves to the light palette; what it must never do is leave a
    /// light editor sitting inside dark chrome.
    func testDefaultThemeFollowsTheSystemAppearance() throws {
        XCTAssertEqual(Preferences().themeName, EditorTheme.systemThemeName)

        let controller = MainWindowController()
        let window = try XCTUnwrap(controller.window)

        window.appearance = NSAppearance(named: .aqua)
        XCTAssertFalse(controller.isDarkAppearance, "the window is in light mode")
        XCTAssertEqual(controller.resolvedTheme(named: EditorTheme.systemThemeName).name,
                       EditorTheme.defaultLight.name)

        window.appearance = NSAppearance(named: .darkAqua)
        XCTAssertTrue(controller.isDarkAppearance, "the window is in dark mode")
        XCTAssertEqual(controller.resolvedTheme(named: EditorTheme.systemThemeName).name,
                       EditorTheme.defaultDark.name)
    }

    /// A theme the user picked by name keeps its own palette whatever the Mac
    /// is doing.
    func testAnExplicitThemeIgnoresTheSystemAppearance() throws {
        let controller = MainWindowController()
        let window = try XCTUnwrap(controller.window)
        window.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(controller.resolvedTheme(named: "Default Light").name, "Default Light")
    }
}
