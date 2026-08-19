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
