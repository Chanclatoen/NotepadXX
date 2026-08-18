import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class LanguageCommandTests: XCTestCase {
    private func makeController(_ text: String, fileNamed name: String? = nil) throws -> (MainWindowController, TextDocument) {
        let controller = MainWindowController()
        var url: URL?
        if let name {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("npxx-lang-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = dir.appendingPathComponent(name)
            try Data(text.utf8).write(to: target)
            url = target
        }
        let document = url.flatMap { try? TextDocument.load(contentsOf: $0) } ?? TextDocument(text: text)
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        return (controller, document)
    }

    func testLanguageIsAutoDetectedFromExtension() throws {
        let (_, document) = try makeController("let x = 1\n", fileNamed: "main.swift")
        XCTAssertEqual(document.languageName, "Swift")
    }

    func testLanguageIsAutoDetectedFromShebang() throws {
        let (_, document) = try makeController("#!/usr/bin/env python3\nx = 1\n", fileNamed: "script")
        XCTAssertEqual(document.languageName, "Python")
    }

    func testUntitledBufferGetsNoLanguage() throws {
        let (_, document) = try makeController("plain text")
        XCTAssertNil(document.languageName)
    }

    func testExplicitSelectionOverridesDetection() throws {
        let (controller, document) = try makeController("let x = 1\n", fileNamed: "main.swift")
        XCTAssertEqual(document.languageName, "Swift")
        controller.applyLanguage(named: "Python")
        XCTAssertEqual(document.languageName, "Python")
        XCTAssertEqual(controller.currentEditor?.language?.name, "Python")
    }

    func testSelectingNormalTextClearsTheLanguage() throws {
        let (controller, document) = try makeController("let x = 1\n", fileNamed: "main.swift")
        controller.applyLanguage(named: nil)
        XCTAssertNil(document.languageName)
        XCTAssertNil(controller.currentEditor?.language)
    }

    func testLanguageMenuListsBuiltInsAndUserDefined() {
        let registry = LanguageRegistry()
        registry.register(LanguageDefinition(name: "ZZCustom", fileExtensions: ["zz"]))
        let menu = MainWindowController.buildLanguageMenu(registry: registry)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(titles.first, "Normal Text")
        XCTAssertTrue(titles.contains("Swift"))
        XCTAssertTrue(titles.contains("ZZCustom"), "user-defined languages appear alongside built-ins")
    }

    func testLanguageSurvivesASessionRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-langsession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try SessionStore(directory: dir)

        let document = TextDocument(text: "let x = 1")
        document.languageName = "Swift"
        try store.save(documents: [document], activeIndex: 0)

        let restored = try SessionStore(directory: dir).restoreDocuments()
        XCTAssertEqual(restored.documents.first?.languageName, "Swift")
    }
}
