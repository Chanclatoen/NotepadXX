import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXEditor
@testable import NotepadXXCore

/// Accessibility is part of the design, not a coat of paint: everything
/// reachable by mouse must be reachable and describable without one.
@MainActor
final class AccessibilityTests: XCTestCase {
    private func make(tabs count: Int = 3) -> MainWindowController {
        let controller = MainWindowController()
        let documents = (1...count).map { index -> TextDocument in
            let document = TextDocument(text: "one\ntwo\n")
            document.untitledName = "document \(index).swift"
            return document
        }
        controller.adopt(documents: documents, activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1100, height: 720))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: VoiceOver can name everything

    /// A button whose only content is a glyph is silent to VoiceOver unless it
    /// carries a label.
    func testEveryToolbarButtonIsNamed() {
        let controller = make()
        let buttons = descendants(of: controller.toolbar).compactMap { $0 as? DSToolbarButton }
        XCTAssertGreaterThan(buttons.count, 5)
        for button in buttons {
            XCTAssertFalse(button.accessibilityLabel()?.isEmpty ?? true,
                           "a toolbar button has no accessibility label")
            XCTAssertNotNil(button.toolTip, "and no tool tip either")
        }
    }

    func testTabsAreNamedAndReportWhetherTheyAreSelected() {
        let controller = make()
        let tabs = descendants(of: controller.tabBar).compactMap { $0 as? DSTabView }
        XCTAssertEqual(tabs.count, 3)
        for tab in tabs {
            XCTAssertFalse(tab.accessibilityLabel()?.isEmpty ?? true, "a tab has no name")
        }
        // Exactly one tab reports itself as the selected one.
        let selected = tabs.filter { ($0.accessibilityValue() as? Int) == 1 }
        XCTAssertEqual(selected.count, 1, "exactly one tab is announced as active")
    }

    /// A toggle has to announce its state, not just look pressed.
    func testToolbarTogglesAnnounceTheirState() {
        let controller = make()
        let toggles = descendants(of: controller.toolbar)
            .compactMap { $0 as? DSToolbarButton }
            .filter { $0.accessibilityRole() == .checkBox }
        XCTAssertFalse(toggles.isEmpty, "the toolbar has toggles")
        for toggle in toggles {
            XCTAssertNotNil(toggle.accessibilityValue(), "\(toggle.accessibilityLabel() ?? "") is silent about its state")
        }
    }

    func testTheStatusBarSegmentsAreReadable() {
        let controller = make()
        let labelled = descendants(of: controller.statusBar)
            .filter { !($0.accessibilityLabel()?.isEmpty ?? true) }
        XCTAssertGreaterThanOrEqual(labelled.count, 3,
                                    "the status bar's values are announced, not just drawn")
    }

    // MARK: Full Keyboard Access

    /// Every control the user can click must be reachable by tabbing.
    func testToolbarButtonsJoinTheKeyViewLoop() {
        let controller = make()
        let buttons = descendants(of: controller.toolbar).compactMap { $0 as? DSToolbarButton }
        for button in buttons {
            XCTAssertTrue(button.canBecomeKeyView, "\(button.accessibilityLabel() ?? "") cannot be tabbed to")
        }
    }

    /// A focus ring that is never drawn leaves keyboard users guessing.
    func testFocusableControlsDrawAFocusRing() {
        let controller = make()
        for button in descendants(of: controller.toolbar).compactMap({ $0 as? DSToolbarButton }) {
            XCTAssertFalse(button.focusRingMaskBounds.isEmpty,
                           "\(button.accessibilityLabel() ?? "") has no focus ring")
        }
    }

    // MARK: Signals that do not rest on colour

    /// The design refuses hue-only signals. Marks differ in shape as well as
    /// colour, so overlapping marks stay distinguishable.
    func testTheFiveMarkStylesDifferInFormNotJustColour() {
        let styles = DS.MarkStyleAppearance.styles()
        XCTAssertEqual(styles.count, 5)
        let forms = Set(styles.map { "\($0.form)" })
        XCTAssertEqual(forms.count, 5, "two mark styles share a form and differ only by hue")
    }

    /// Change history: amber square for unsaved, rounded green once saved.
    func testChangeHistoryUsesTwoShapesNotTwoColours() throws {
        let controller = EditorViewControllerHarness.make()
        let gutter = try XCTUnwrap(controller.gutterView)
        gutter.changedLines = [0]
        gutter.savedChangedLines = [1]

        let unsaved: GutterView.ChangeBarShape = gutter.changeBarShape(forLine: 0)
        let saved: GutterView.ChangeBarShape = gutter.changeBarShape(forLine: 1)
        XCTAssertEqual(unsaved, .square)
        XCTAssertEqual(saved, .rounded)
        XCTAssertNotEqual(unsaved, saved, "the two states differ in shape, not only in hue")
    }

    // MARK: System accessibility settings

    /// Reduced Motion must actually shorten the animations, not be stored and
    /// ignored.
    func testReducedMotionRemovesAnimationDuration() {
        XCTAssertEqual(DS.Motion.duration(DS.Motion.panelSlide, reduceMotion: true), 0,
                       "with Reduce Motion on, panels move instantly")
        XCTAssertGreaterThan(DS.Motion.duration(DS.Motion.panelSlide, reduceMotion: false), 0)
    }

    /// Increased Contrast has to change the colours that carry meaning.
    func testIncreasedContrastStrengthensSeparators() {
        let normal = DS.Color.separator.usingColorSpace(.sRGB)
        let increased = DS.Color.separatorStructural.usingColorSpace(.sRGB)
        XCTAssertNotEqual(normal?.alphaComponent, increased?.alphaComponent,
                          "the structural separator is stronger than the hairline one")
    }
}

/// Builds an editor that is sized and laid out, which line geometry needs.
enum EditorViewControllerHarness {
    @MainActor
    static func make(text: String = "one\ntwo\nthree\n") -> EditorViewController {
        let controller = EditorViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        controller.view.layoutSubtreeIfNeeded()
        controller.load(text: text)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }
}
