import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// The full "browse a catalogue, install with one click, run it" journey,
/// against the real bundled catalogue format.
@MainActor
final class PluginStoreFlowTests: XCTestCase {
    private func workspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Packages the repo's own bundled plugins exactly as the build script does.
    private func buildCatalogue(in dir: URL) throws -> URL {
        let resources = dir.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotepadXXUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("scripts/build-plugin-catalogue.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, resources.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "catalogue build failed")
        return resources.appendingPathComponent("plugin-catalogue.json")
    }

    func testBundledCatalogueListsTheShippedPlugins() async throws {
        let dir = try workspace()
        let catalogue = try buildCatalogue(in: dir)
        let repository = PluginRepository(directory: dir, sourceURLs: [catalogue])
        let failures = await repository.refresh()

        XCTAssertTrue(failures.isEmpty, "the shipped catalogue must parse")
        let names = repository.allListings.map(\.name).sorted()
        XCTAssertEqual(names, ["JSON Tools", "MIME Tools", "Text Statistics"])
        XCTAssertTrue(repository.allListings.allSatisfy { $0.sha256.count == 64 },
                      "every entry carries a real checksum")
    }

    /// Install from the catalogue, then actually run the plugin's command.
    func testInstallFromCatalogueThenRunIt() async throws {
        let dir = try workspace()
        let catalogue = try buildCatalogue(in: dir)
        let repository = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repository.refresh()

        let registry = try PluginRegistry(directory: dir)
        guard let jsonTools = repository.allListings.first(where: { $0.identifier.contains("jsontools") })
        else { return XCTFail("JSON Tools missing from the catalogue") }

        _ = try await repository.install(jsonTools, into: registry.pluginsDirectory)
        registry.reload()
        XCTAssertEqual(registry.enabledPlugins.map(\.id), ["com.notepadxx.jsontools"])

        // Load it into a real host over a real document and run Format.
        let controller = MainWindowController()
        let document = TextDocument(text: "{\"b\":2,\"a\":1}")
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window

        let host = PluginHost(bridge: controller)
        host.loadAll(registry.enabledPlugins)
        XCTAssertNil(host.invoke(pluginIdentifier: "com.notepadxx.jsontools", commandID: "format"))

        let formatted = controller.currentEditor?.text ?? ""
        XCTAssertTrue(formatted.contains("\n"), "the document was pretty-printed")
        XCTAssertTrue(formatted.contains("\"a\""), "content survived formatting")
    }

    func testMimeToolsRoundTripsBase64() async throws {
        let dir = try workspace()
        let catalogue = try buildCatalogue(in: dir)
        let repository = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repository.refresh()
        let registry = try PluginRegistry(directory: dir)

        guard let mime = repository.allListings.first(where: { $0.identifier.contains("mimetools") })
        else { return XCTFail("MIME Tools missing") }
        _ = try await repository.install(mime, into: registry.pluginsDirectory)
        registry.reload()

        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "hello")], activeIndex: 0)
        _ = controller.window

        let host = PluginHost(bridge: controller)
        host.loadAll(registry.enabledPlugins)
        host.invoke(pluginIdentifier: "com.notepadxx.mimetools", commandID: "base64Encode")
        XCTAssertEqual(controller.currentEditor?.text, "aGVsbG8=")

        host.invoke(pluginIdentifier: "com.notepadxx.mimetools", commandID: "base64Decode")
        XCTAssertEqual(controller.currentEditor?.text, "hello", "decode reverses encode")
    }

    /// An installed plugin appears in the Plugins menu, which is how the user
    /// actually reaches it.
    func testInstalledPluginAppearsInTheMenu() async throws {
        let dir = try workspace()
        let catalogue = try buildCatalogue(in: dir)
        let repository = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repository.refresh()
        let registry = try PluginRegistry(directory: dir)
        guard let stats = repository.allListings.first(where: { $0.identifier.contains("textstats") })
        else { return XCTFail("Text Statistics missing") }
        _ = try await repository.install(stats, into: registry.pluginsDirectory)
        registry.reload()

        let controller = MainWindowController()
        _ = controller.window
        controller.pluginRegistry = registry
        NSApp.mainMenu = MainMenu.build()
        controller.reloadPlugins()

        let pluginsMenu = NSApp.mainMenu?.items.first { $0.title == "Plugins" }?.submenu
        let titles = pluginsMenu?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Text Statistics"), "the plugin is reachable from the menu")
    }
}
