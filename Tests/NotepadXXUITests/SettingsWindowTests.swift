import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Layout assertions for the settings windows.
///
/// These exist because `--screenshot` cannot verify them: modern AppKit
/// controls are SwiftUI-hosted and neither `cacheDisplay` nor layer rendering
/// captures them off-screen, so a correct pane photographs as blank. Asserting
/// real frames is the reliable check.
@MainActor
final class SettingsWindowTests: XCTestCase {
    private func makeStore() throws -> PreferencesStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-prefs-\(UUID().uuidString)", isDirectory: true)
        return try PreferencesStore(directory: dir)
    }

    private func controls(in view: NSView) -> [NSControl] {
        var found = view.subviews.compactMap { $0 as? NSControl }
        for subview in view.subviews { found += controls(in: subview) }
        return found
    }

    func testPreferencesRendersTheFirstPageWithLaidOutControls() throws {
        let controller = PreferencesWindowController(store: try makeStore(), themeStore: nil) { _ in }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.contentView?.layoutSubtreeIfNeeded()

        // Labels live in the grid's own column now, so a checkbox carries its
        // name as an accessibility label rather than a title.
        let checkboxes = controls(in: window.contentView!).compactMap { $0 as? NSButton }
            .filter { $0.accessibilityLabel()?.isEmpty == false && $0.bezelStyle != .rounded }
        XCTAssertGreaterThan(checkboxes.count, 3, "the General page shows its toggles")
        XCTAssertTrue(checkboxes.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 },
                      "controls must have a real size, not collapse to zero")
    }

    func testEveryPageBuildsWithoutEmptyContent() throws {
        let store = try makeStore()
        let pages = PreferencesWindowController.makePages(themeNames: ["System"])
        XCTAssertGreaterThanOrEqual(pages.count, 10)
        for page in pages {
            XCTAssertFalse(page.controls.isEmpty, "\(page.title) has no controls")
        }
        _ = store
    }

    func testTogglingAPreferenceWritesThroughToTheStore() throws {
        let store = try makeStore()
        var seen: Preferences?
        let controller = PreferencesWindowController(store: store, themeStore: nil) { seen = $0 }
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()

        let toggle = controls(in: window.contentView!)
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Show Toolbar" }
        let button = try XCTUnwrap(toggle)
        button.state = .off
        _ = button.target?.perform(button.action, with: button)

        XCTAssertFalse(store.preferences.showToolbar, "the change reaches the store")
        XCTAssertNotNil(seen, "observers are notified")
    }

    func testShortcutMapperListsCommandsAndShowsBindings() throws {
        let map = ShortcutMap(commands: [
            ShortcutCommand(id: "find:", title: "Find", category: .main,
                            binding: KeyBinding(key: "f", modifiers: 1 << 20)),
            ShortcutCommand(id: "playMacro:", title: "Play Macro", category: .macro),
        ])
        let controller = ShortcutMapperWindowController(map: map) {}
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()

        let tables = controls(in: window.contentView!).compactMap { $0 as? NSTableView }
        XCTAssertFalse(tables.isEmpty, "the mapper has a command table")
        XCTAssertEqual(map.binding(for: "find:")?.displayString, "⌘F")
    }

    /// The mapper's command list is discovered from the menu bar so it cannot
    /// drift out of step with the menus.
    func testCommandDiscoveryFindsMenuActions() {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Find", action: Selector(("findAction:")), keyEquivalent: "f")
        item.keyEquivalentModifierMask = [.command]
        let sub = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        subMenu.addItem(withTitle: "Nested", action: Selector(("nestedAction:")), keyEquivalent: "")
        sub.submenu = subMenu
        menu.addItem(sub)

        let discovered = MainWindowController.discoverCommands(in: menu)
        XCTAssertTrue(discovered.contains { $0.id == "findAction:" && $0.binding?.key == "f" })
        XCTAssertTrue(discovered.contains { $0.id == "nestedAction:" }, "submenus are walked")
    }
}
