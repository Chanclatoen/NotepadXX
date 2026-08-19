import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class ToolbarTests: XCTestCase {
    /// A missing SF Symbol silently degrades to the button's title, which shows
    /// as clipped words in the toolbar. This caught exactly that with
    /// "text.wrap", which does not exist.
    func testEveryToolbarSymbolExists() {
        var missing: [String] = []
        for item in ToolbarView.defaultGroups().flatMap({ $0 }) {
            if NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) == nil {
                missing.append("\(item.tooltip): \(item.symbol)")
            }
        }
        XCTAssertTrue(missing.isEmpty, "unknown SF Symbols: \(missing)")
    }

    func testToolbarCoversTheNotepadPlusPlusGroups() {
        let groups = ToolbarView.defaultGroups()
        let tooltips = groups.flatMap { $0 }.map(\.tooltip)
        for expected in ["New", "Open", "Save", "Save All", "Print", "Cut", "Copy", "Paste",
                         "Undo", "Redo", "Find", "Replace", "Zoom In", "Zoom Out",
                         "Word Wrap", "Document Map", "Function List", "Run"] {
            XCTAssertTrue(tooltips.contains(expected), "toolbar is missing \(expected)")
        }
        XCTAssertGreaterThan(groups.count, 5, "buttons are grouped, not one long row")
    }

    func testEveryToolbarButtonHasAnImageAndNoTitle() {
        let toolbar = ToolbarView()
        toolbar.configure(groups: ToolbarView.defaultGroups())
        toolbar.frame = NSRect(x: 0, y: 0, width: 1200, height: 32)
        toolbar.layoutSubtreeIfNeeded()

        func buttons(in view: NSView) -> [NSButton] {
            var found = view.subviews.compactMap { $0 as? NSButton }
            for sub in view.subviews { found += buttons(in: sub) }
            return found
        }
        let all = buttons(in: toolbar)
        XCTAssertGreaterThan(all.count, 20)
        XCTAssertTrue(all.allSatisfy { $0.image != nil }, "a button with no image renders as text")
        XCTAssertTrue(all.allSatisfy { $0.title.isEmpty }, "titles must not leak into the toolbar")
    }

    func testToggleStateIsReflected() {
        let toolbar = ToolbarView()
        toolbar.configure(groups: ToolbarView.defaultGroups())
        toolbar.activeToggles = ["Word Wrap"]
        XCTAssertTrue(toolbar.activeToggles.contains("Word Wrap"))
    }
}

@MainActor
final class StatusBarTests: XCTestCase {
    private func labels(in view: NSView) -> [String] {
        var found = view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        for sub in view.subviews { found += labels(in: sub) }
        return found
    }

    /// Notepad++ shows six segments; the order and wording are muscle memory.
    func testAllSixSegmentsArePopulated() {
        let bar = StatusBarView()
        bar.update(documentType: "Swift", length: 278, lines: 14,
                   selection: 0, selectedLines: 0, line: 1, column: 1,
                   lineEnding: "Unix (LF)", encoding: "UTF-8", isOverwrite: false)
        let text = labels(in: bar).joined(separator: " | ")

        XCTAssertTrue(text.contains("Swift"), "document type")
        XCTAssertTrue(text.contains("length : 278"))
        XCTAssertTrue(text.contains("lines : 14"))
        XCTAssertTrue(text.contains("Ln : 1"))
        XCTAssertTrue(text.contains("Col : 1"))
        XCTAssertTrue(text.contains("Unix (LF)"))
        XCTAssertTrue(text.contains("UTF-8"))
        XCTAssertTrue(text.contains("INS"))
    }

    func testOverwriteModeIsShown() {
        let bar = StatusBarView()
        bar.update(documentType: "Normal text file", length: 0, lines: 1,
                   selection: 0, selectedLines: 0, line: 1, column: 1,
                   lineEnding: "Unix (LF)", encoding: "UTF-8", isOverwrite: true)
        XCTAssertTrue(labels(in: bar).contains("OVR"))
    }

    /// Notepad++ reports a selection as characters and lines.
    func testSelectionShowsCharactersAndLines() {
        let bar = StatusBarView()
        bar.update(documentType: "Swift", length: 100, lines: 10,
                   selection: 42, selectedLines: 3, line: 5, column: 2,
                   lineEnding: "Windows (CR LF)", encoding: "UTF-8-BOM", isOverwrite: false)
        XCTAssertTrue(labels(in: bar).joined().contains("Sel : 42 | 3"))
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
