import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// The language editor's preview repaints as the rules are typed. A "Test"
/// button that has to be pressed hides the one thing the editor is for.
@MainActor
final class UDLPreviewTests: XCTestCase {
    private func colour(of word: String, in preview: UDLPreviewView,
                        sample: String) -> NSColor? {
        let range = (sample as NSString).range(of: word)
        guard range.location != NSNotFound else { return nil }
        return preview.highlighted.attribute(.foregroundColor, at: range.location,
                                             effectiveRange: nil) as? NSColor
    }

    func testAKeywordIsColouredOnceTheRuleExists() throws {
        let sample = "listen 8080;"
        let preview = UDLPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))

        var language = LanguageDefinition(name: "test")
        preview.update(with: language, sample: sample)
        let plain = colour(of: "listen", in: preview, sample: sample)

        language.keywords1 = ["listen"]
        preview.update(with: language, sample: sample)
        let highlighted = colour(of: "listen", in: preview, sample: sample)

        XCTAssertNotEqual(plain, highlighted, "adding the keyword changed how it is drawn")
        XCTAssertEqual(highlighted, DS.SyntaxPalette.xcodeKeyword)
    }

    func testACommentRuleTakesEffectImmediately() throws {
        let sample = "# a comment\nlisten 80;"
        let preview = UDLPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))

        var language = LanguageDefinition(name: "test")
        preview.update(with: language, sample: sample)
        XCTAssertNotEqual(colour(of: "#", in: preview, sample: sample),
                          DS.SyntaxPalette.xcodeComment)

        language.lineCommentTokens = ["#"]
        preview.update(with: language, sample: sample)
        XCTAssertEqual(colour(of: "#", in: preview, sample: sample),
                       DS.SyntaxPalette.xcodeComment)
    }

    /// The editor's preview is filled in when it opens, not left blank until
    /// something is typed.
    func testTheEditorShowsAPreviewAsSoonAsItOpens() throws {
        var saved: LanguageDefinition?
        let controller = UDLEditorWindowController(editing: nil, registry: LanguageRegistry.shared) {
            saved = $0
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        func descendants(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap { descendants(of: $0) }
        }
        let preview = try XCTUnwrap(
            descendants(of: controller.window!.contentView!).compactMap { $0 as? UDLPreviewView }.first)
        XCTAssertFalse(preview.highlighted.string.isEmpty, "the preview has content on open")
        XCTAssertNil(saved, "nothing is applied until Save")
    }
}

/// "Six sections, one language." The form was one long scroll, which buried
/// the keywords most edits are about.
@MainActor
final class UDLSectionTests: XCTestCase {
    private func makeEditor() -> UDLEditorWindowController {
        let controller = UDLEditorWindowController(editing: nil,
                                                   registry: LanguageRegistry.shared) { _ in }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    func testTheDesignsSixSectionsArePresent() {
        XCTAssertEqual(UDLEditorWindowController.Section.allCases.map(\.title),
                       ["General", "Keywords", "Comments & Numbers", "Operators",
                        "Folding", "Styling"])
    }

    func testItOpensOnGeneral() {
        XCTAssertEqual(makeEditor().section, .general)
    }

    /// Each section shows its own controls, and only those.
    func testSwitchingSectionsChangesWhatIsShown() throws {
        let controller = makeEditor()
        let content = try XCTUnwrap(controller.window?.contentView)

        controller.showSection(.general)
        content.layoutSubtreeIfNeeded()
        let generalLabels = descendants(of: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(generalLabels.contains { $0.hasPrefix("Name") }, "General shows the name")

        controller.showSection(.folding)
        content.layoutSubtreeIfNeeded()
        let foldingLabels = descendants(of: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(foldingLabels.contains { $0.hasPrefix("Fold open") }, "Folding shows fold rules")
        XCTAssertFalse(foldingLabels.contains { $0.hasPrefix("Name") },
                       "and not the ones belonging to another section")
    }

    /// The preview stays visible whichever section is showing.
    func testThePreviewSurvivesASectionChange() throws {
        let controller = makeEditor()
        let content = try XCTUnwrap(controller.window?.contentView)
        for section in UDLEditorWindowController.Section.allCases {
            controller.showSection(section)
            content.layoutSubtreeIfNeeded()
            XCTAssertFalse(descendants(of: content).compactMap { $0 as? UDLPreviewView }.isEmpty,
                           "the preview vanished on \(section.title)")
        }
    }
}
