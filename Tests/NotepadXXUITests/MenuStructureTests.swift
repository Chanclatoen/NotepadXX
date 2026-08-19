import XCTest
import AppKit
@testable import NotepadXXUI

/// The menu bar has to look like a Mac app's: the standard application menu,
/// a real Window and Help menu, and no command offered twice under two names.
@MainActor
final class MenuStructureTests: XCTestCase {
    private func menu(_ title: String) throws -> NSMenu {
        let root = MainMenu.build()
        let item = try XCTUnwrap(root.items.first { $0.title == title }, "no \(title) menu")
        return try XCTUnwrap(item.submenu)
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            [item] + (item.submenu.map(allItems) ?? [])
        }
    }

    func testApplicationMenuCarriesTheStandardItems() throws {
        let app = try menu("NotepadXX")
        let titles = app.items.map(\.title)
        for expected in ["About NotepadXX", "Settings…", "Services", "Hide NotepadXX",
                         "Hide Others", "Show All", "Quit NotepadXX"] {
            XCTAssertTrue(titles.contains(expected), "the application menu is missing \(expected)")
        }
    }

    func testSettingsHasTheStandardShortcut() throws {
        let app = try menu("NotepadXX")
        let settings = try XCTUnwrap(app.items.first { $0.title == "Settings…" })
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask, [.command])
    }

    func testWindowMenuCarriesTheStandardItems() throws {
        let window = try menu("Window")
        let titles = window.items.map(\.title)
        for expected in ["Minimize", "Zoom", "Enter Full Screen", "Bring All to Front"] {
            XCTAssertTrue(titles.contains(expected), "the Window menu is missing \(expected)")
        }
    }

    func testThereIsAHelpMenu() throws {
        let help = try menu("Help")
        XCTAssertFalse(help.items.isEmpty)
    }

    /// Full Screen appeared in both View and Window with different shortcuts,
    /// and Preferences in both the application menu and Settings.
    func testNoCommandIsOfferedTwice() {
        let root = MainMenu.build()
        var byAction: [String: [String]] = [:]
        for item in allItems(root) where item.action != nil && item.submenu == nil {
            // Menu items that carry an argument (a language, a recent file, a
            // mark style) legitimately share one action.
            guard item.representedObject == nil else { continue }
            byAction[NSStringFromSelector(item.action!), default: []].append(item.title)
        }

        for (action, titles) in byAction {
            let distinct = Set(titles)
            XCTAssertEqual(distinct.count, titles.count,
                           "\(action) is offered under repeated titles: \(titles)")
            XCTAssertLessThanOrEqual(
                titles.count, 1,
                "\(action) appears \(titles.count) times: \(titles)")
        }
    }

    /// A shortcut must mean one thing.
    func testNoShortcutIsBoundTwice() {
        let root = MainMenu.build()
        var seen: [String: String] = [:]
        for item in allItems(root) where !item.keyEquivalent.isEmpty {
            let key = "\(item.keyEquivalentModifierMask.rawValue):\(item.keyEquivalent)"
            if let existing = seen[key] {
                XCTFail("\(item.title) and \(existing) share a shortcut")
            }
            seen[key] = item.title
        }
    }
}
