import AppKit
import XCTest
import NotepadXXCore
@testable import NotepadXXUI

/// What the sandboxed flavour must and must not offer. Under the direct build
/// the same checks pin today's menus.
@MainActor
final class AppStoreFlavourTests: XCTestCase {
    func testRunAndPluginsMenusOnlyInTheDirectBuild() {
        let titles = MainMenu.build().items.map(\.title)
        XCTAssertEqual(titles.contains("Run"), !BuildFlavour.isAppStore)
        XCTAssertEqual(titles.contains("Plugins"), !BuildFlavour.isAppStore)
    }

    func testRunHasNoToolbarButtonInTheAppStoreBuild() {
        let labels = ToolbarCatalogue.groups().flatMap { $0 }.map(\.label)
        XCTAssertEqual(labels.contains("Run…"), !BuildFlavour.isAppStore)
    }
}
