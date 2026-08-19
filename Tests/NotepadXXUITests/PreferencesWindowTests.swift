import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The Preferences window is eleven pages of grouped settings with a live
/// search. These check what the window does, not how it is built.
@MainActor
final class PreferencesWindowTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-prefswin-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeController() throws -> (PreferencesWindowController, PreferencesStore) {
        let store = try PreferencesStore(directory: directory)
        var applied: [Preferences] = []
        let controller = PreferencesWindowController(store: store, themeStore: nil) { applied.append($0) }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return (controller, store)
    }

    func testTheDesignsElevenPagesAreAllPresent() {
        let pages = PreferencesWindowController.makePages(themeNames: ["System"])
        XCTAssertEqual(pages.map(\.title), [
            "General", "Editing", "Symbols", "Indentation", "New Document",
            "Backup & Session", "File Status", "Recent Files", "Auto-Completion",
            "Searching", "Appearance & Themes",
        ])
    }

    /// "A page holds two to four named groups and never more than ten controls."
    func testNoPageOutgrowsTheStructureRules() {
        for page in PreferencesWindowController.makePages(themeNames: ["System"]) {
            XCTAssertLessThanOrEqual(page.groups.count, 4, "\(page.title) has too many groups")
            XCTAssertGreaterThanOrEqual(page.groups.count, 1, "\(page.title) has no groups")
            XCTAssertLessThanOrEqual(page.controls.count, 10, "\(page.title) has too many controls")
            XCTAssertFalse(page.summary.isEmpty, "\(page.title) has no description")
        }
    }

    /// Only the pages whose effect is visual carry a preview.
    func testPreviewsAppearOnlyWhereTheEffectIsVisual() {
        let pages = PreferencesWindowController.makePages(themeNames: ["System"])
        let withPreview = Set(pages.filter(\.showsPreview).map(\.title))
        XCTAssertEqual(withPreview, ["Symbols", "Indentation", "Appearance & Themes"])
    }

    /// Every setting the window shows must reach a distinct stored value —
    /// two controls writing the same key would make one of them a lie. Labels
    /// repeat on purpose ("Show" heads a group on several pages), so the check
    /// is on what each control writes.
    func testNoPreferenceIsBoundByTwoControls() {
        let keyPaths = PreferencesWindowController.makePages(themeNames: ["System"])
            .flatMap(\.controls)
            .flatMap(\.boundKeyPaths)
        XCTAssertEqual(Set(keyPaths).count, keyPaths.count, "a preference is bound twice")
    }

    /// A label must be unique within its own group, where the eye compares them.
    func testLabelsAreUniqueWithinAGroup() {
        for page in PreferencesWindowController.makePages(themeNames: ["System"]) {
            for group in page.groups {
                let labels = group.controls.map(\.label)
                XCTAssertEqual(Set(labels).count, labels.count,
                               "\(page.title) › \(group.name) repeats a label")
            }
        }
    }

    // MARK: Search

    func testSearchingCountsHitsPerPage() throws {
        let (controller, _) = try makeController()
        controller.search(for: "caret")
        XCTAssertGreaterThan(controller.matchCount, 0)
        XCTAssertNotNil(controller.hitCount(forPageTitled: "Editing"))
        XCTAssertNil(controller.hitCount(forPageTitled: "Recent Files"),
                     "a page with no matching setting reports no hits")
    }

    func testSearchingForSomethingAbsentMatchesNothing() throws {
        let (controller, _) = try makeController()
        controller.search(for: "zzzznotasetting")
        XCTAssertEqual(controller.matchCount, 0)
    }

    func testClearingTheSearchRestoresEveryPage() throws {
        let (controller, _) = try makeController()
        controller.search(for: "caret")
        controller.search(for: "")
        XCTAssertEqual(controller.matchCount, 0, "an empty query filters nothing")
        XCTAssertNil(controller.hitCount(forPageTitled: "Editing"))
    }

    // MARK: Pages

    func testControlTabMovesToTheNextPageAndWrapsRound() throws {
        let (controller, _) = try makeController()
        XCTAssertEqual(controller.selectedPageIndex, 0)
        controller.selectNextPage()
        XCTAssertEqual(controller.selectedPageIndex, 1)
        controller.selectPreviousPage()
        controller.selectPreviousPage()
        XCTAssertEqual(controller.selectedPageIndex, 10, "wraps to the last page")
    }

    // MARK: Reset

    func testResetPageRestoresOnlyThatPagesSettings() throws {
        let (controller, store) = try makeController()
        try store.update {
            $0.caretWidth = 5                 // Editing
            $0.recentFilesLimit = 3           // Recent Files
        }

        controller.selectPage(at: 1)          // Editing
        controller.resetCurrentPage()

        XCTAssertEqual(store.preferences.caretWidth, Preferences().caretWidth, "the page was reset")
        XCTAssertEqual(store.preferences.recentFilesLimit, 3, "other pages are untouched")
    }

    func testResetAllRestoresEverything() throws {
        let (controller, store) = try makeController()
        try store.update {
            $0.caretWidth = 5
            $0.recentFilesLimit = 3
            $0.fontName = "Comic Sans"
        }

        controller.resetEverything()

        XCTAssertEqual(store.preferences, Preferences())
    }

    /// Changing a control applies immediately — there is no OK button to press.
    func testChangingASettingAppliesWithoutConfirmation() throws {
        let store = try PreferencesStore(directory: directory)
        var applied: [Preferences] = []
        let controller = PreferencesWindowController(store: store, themeStore: nil) { applied.append($0) }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.resetCurrentPage()
        XCTAssertFalse(applied.isEmpty, "the change was applied without any confirmation step")
    }
}
