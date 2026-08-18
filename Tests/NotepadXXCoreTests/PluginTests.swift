import XCTest
@testable import NotepadXXCore

@MainActor
private final class StubBridge: PluginEditorBridge {
    var text = "hello world"
    var selection = NSRange(location: 0, length: 5)
    var path: String? = "/tmp/a.txt"
    var messages: [String] = []
    var logs: [String] = []

    func pluginCurrentText() -> String { text }
    func pluginSetText(_ newText: String) { text = newText }
    func pluginSelectedRange() -> NSRange { selection }
    func pluginSetSelectedRange(_ range: NSRange) { selection = range }
    func pluginReplaceSelection(with replacement: String) {
        text = (text as NSString).replacingCharacters(in: selection, with: replacement)
        selection = NSRange(location: selection.location, length: (replacement as NSString).length)
    }
    func pluginCurrentFilePath() -> String? { path }
    func pluginDocumentCount() -> Int { 3 }
    func pluginShowMessage(_ message: String) { messages.append(message) }
    func pluginLog(_ message: String) { logs.append(message) }
}

final class PluginRegistryTests: XCTestCase {
    private func makeRegistry() throws -> (PluginRegistry, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-plugins-\(UUID().uuidString)", isDirectory: true)
        return (try PluginRegistry(directory: dir), dir)
    }

    /// Writes a plugin folder outside the registry, ready to install.
    private func makePluginSource(
        identifier: String, script: String, commands: [PluginManifest.Command] = [],
        main: String = "main.js"
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-src-\(UUID().uuidString)/\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            name: identifier, identifier: identifier, version: "1.0",
            main: main, commands: commands
        )
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("plugin.json"))
        try Data(script.utf8).write(to: dir.appendingPathComponent(main))
        return dir
    }

    func testEmptyRegistry() throws {
        let (registry, _) = try makeRegistry()
        XCTAssertTrue(registry.plugins.isEmpty)
    }

    func testInstallAndDiscover() throws {
        let (registry, _) = try makeRegistry()
        let source = try makePluginSource(identifier: "com.test.one", script: "exports.run = function(){};")
        try registry.install(from: source)

        XCTAssertEqual(registry.plugins.map(\.id), ["com.test.one"])
        XCTAssertTrue(registry.plugins[0].isEnabled)
        XCTAssertNil(registry.plugins[0].loadError)
    }

    func testInstallRejectsAFolderWithoutAManifest() throws {
        let (registry, _) = try makeRegistry()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try registry.install(from: dir))
    }

    func testDuplicateIdentifierIsRejected() throws {
        let (registry, _) = try makeRegistry()
        let source = try makePluginSource(identifier: "com.test.dup", script: "exports.run = function(){};")
        try registry.install(from: source)
        XCTAssertThrowsError(try registry.install(from: source)) { error in
            XCTAssertEqual(error as? PluginRegistry.PluginError, .duplicateIdentifier("com.test.dup"))
        }
    }

    /// A broken plugin must be listed with its reason, not silently vanish.
    func testMalformedManifestIsListedWithAnError() throws {
        let (registry, dir) = try makeRegistry()
        let bad = dir.appendingPathComponent("plugins/broken", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: bad.appendingPathComponent("plugin.json"))
        registry.reload()

        XCTAssertEqual(registry.plugins.count, 1)
        XCTAssertEqual(registry.plugins[0].loadError, "malformed plugin.json")
        XCTAssertFalse(registry.plugins[0].isEnabled)
        XCTAssertTrue(registry.enabledPlugins.isEmpty)
    }

    func testMissingScriptIsReported() throws {
        let (registry, _) = try makeRegistry()
        let source = try makePluginSource(identifier: "com.test.missing", script: "x", main: "main.js")
        try FileManager.default.removeItem(at: source.appendingPathComponent("main.js"))
        try registry.install(from: source)
        XCTAssertEqual(registry.plugins.first?.loadError, "missing script main.js")
    }

    func testEnableDisableSurvivesReload() throws {
        let (registry, dir) = try makeRegistry()
        let source = try makePluginSource(identifier: "com.test.toggle", script: "exports.run=function(){};")
        try registry.install(from: source)

        registry.setEnabled(false, forIdentifier: "com.test.toggle")
        XCTAssertFalse(registry.plugins[0].isEnabled)

        let reopened = try PluginRegistry(directory: dir)
        XCTAssertFalse(reopened.plugins[0].isEnabled, "the disabled state persists")
    }

    func testUninstallRemovesTheDirectory() throws {
        let (registry, _) = try makeRegistry()
        let source = try makePluginSource(identifier: "com.test.gone", script: "exports.run=function(){};")
        let installed = try registry.install(from: source)
        try registry.uninstall(identifier: "com.test.gone")

        XCTAssertTrue(registry.plugins.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directory.path))
    }

    /// An identifier with traversal components must not write outside the
    /// plugins directory, whatever the manifest claims.
    func testIdentifierWithTraversalIsSanitised() throws {
        let (registry, dir) = try makeRegistry()
        let source = try makePluginSource(identifier: "../../escape", script: "exports.run=function(){};")
        try? registry.install(from: source)

        let pluginsPath = dir.appendingPathComponent("plugins").path
        let contents = try FileManager.default.contentsOfDirectory(atPath: pluginsPath)
        XCTAssertEqual(contents.count, 1, "exactly one folder, inside the plugins directory")
        XCTAssertFalse(contents[0].contains(".."), "no traversal component survives")
        XCTAssertFalse(contents[0].contains("/"))
    }

    func testSafeFolderNameRules() {
        XCTAssertEqual(PluginRegistry.safeFolderName(for: "com.example.plugin"), "com.example.plugin")
        XCTAssertEqual(PluginRegistry.safeFolderName(for: "../../escape"), "escape")
        XCTAssertEqual(PluginRegistry.safeFolderName(for: "a/b"), "a-b")
        XCTAssertEqual(PluginRegistry.safeFolderName(for: "..."), "plugin", "an empty result falls back")
    }
}

@MainActor
final class PluginHostTests: XCTestCase {
    private func makePlugin(_ script: String, commands: [PluginManifest.Command]) throws -> InstalledPlugin {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: dir.appendingPathComponent("main.js"))
        let manifest = PluginManifest(
            name: "T", identifier: "com.test.host", version: "1", main: "main.js", commands: commands
        )
        return InstalledPlugin(manifest: manifest, directory: dir, isEnabled: true)
    }

    func testPluginCanReadAndWriteTheDocument() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)
        let plugin = try makePlugin(
            "exports.upper = function() { notepadxx.setText(notepadxx.getText().toUpperCase()); };",
            commands: [PluginManifest.Command(id: "upper", title: "Upper")]
        )
        XCTAssertTrue(host.load(plugin))
        XCTAssertNil(host.invoke(pluginIdentifier: "com.test.host", commandID: "upper"))
        XCTAssertEqual(bridge.text, "HELLO WORLD")
    }

    func testPluginCanReplaceTheSelection() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)
        let plugin = try makePlugin(
            "exports.wrap = function() { notepadxx.replaceSelection('<' + notepadxx.getText().substr(0,5) + '>'); };",
            commands: [PluginManifest.Command(id: "wrap", title: "Wrap")]
        )
        XCTAssertTrue(host.load(plugin))
        host.invoke(pluginIdentifier: "com.test.host", commandID: "wrap")
        XCTAssertEqual(bridge.text, "<hello> world")
    }

    func testPluginReadsSelectionAndPath() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)
        let plugin = try makePlugin("""
        exports.report = function() {
            var s = notepadxx.getSelection();
            notepadxx.showMessage(notepadxx.getFilePath() + ':' + s.location + '+' + s.length
                                  + ' of ' + notepadxx.getDocumentCount());
        };
        """, commands: [PluginManifest.Command(id: "report", title: "Report")])
        XCTAssertTrue(host.load(plugin))
        host.invoke(pluginIdentifier: "com.test.host", commandID: "report")
        XCTAssertEqual(bridge.messages, ["/tmp/a.txt:0+5 of 3"])
    }

    func testConsoleLogIsBridged() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)
        let plugin = try makePlugin(
            "exports.talk = function() { console.log('from a plugin'); };",
            commands: [PluginManifest.Command(id: "talk", title: "Talk")]
        )
        host.load(plugin)
        host.invoke(pluginIdentifier: "com.test.host", commandID: "talk")
        XCTAssertEqual(bridge.logs, ["from a plugin"])
    }

    /// A plugin that throws must report the error, not fail silently.
    func testThrowingCommandReportsTheError() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)
        let plugin = try makePlugin(
            "exports.boom = function() { throw new Error('kaboom'); };",
            commands: [PluginManifest.Command(id: "boom", title: "Boom")]
        )
        host.load(plugin)
        let error = host.invoke(pluginIdentifier: "com.test.host", commandID: "boom")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("kaboom") ?? false)
    }

    func testSyntaxErrorIsReportedAtLoad() throws {
        let host = PluginHost(bridge: StubBridge())
        let plugin = try makePlugin("this is not javascript {{{",
                                    commands: [PluginManifest.Command(id: "x", title: "X")])
        XCTAssertFalse(host.load(plugin))
        XCTAssertNotNil(host.loadErrors["com.test.host"])
    }

    func testCommandWithNoExportedHandlerIsReported() throws {
        let host = PluginHost(bridge: StubBridge())
        let plugin = try makePlugin("exports.other = function(){};",
                                    commands: [PluginManifest.Command(id: "missing", title: "Missing")])
        _ = host.load(plugin)
        XCTAssertFalse(host.hasHandler(pluginIdentifier: "com.test.host", commandID: "missing"))
        XCTAssertNotNil(host.loadErrors["com.test.host"])
    }

    /// Two plugins must not be able to clobber each other's globals.
    func testPluginsAreIsolatedFromEachOther() throws {
        let bridge = StubBridge()
        let host = PluginHost(bridge: bridge)

        let dirA = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-a-\(UUID().uuidString)", isDirectory: true)
        let dirB = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-b-\(UUID().uuidString)", isDirectory: true)
        for dir in [dirA, dirB] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("var shared = 'A'; exports.who = function(){ notepadxx.showMessage(shared); };".utf8)
            .write(to: dirA.appendingPathComponent("main.js"))
        try Data("var shared = 'B'; exports.who = function(){ notepadxx.showMessage(shared); };".utf8)
            .write(to: dirB.appendingPathComponent("main.js"))

        let command = [PluginManifest.Command(id: "who", title: "Who")]
        host.load(InstalledPlugin(
            manifest: PluginManifest(name: "A", identifier: "com.a", version: "1", main: "main.js", commands: command),
            directory: dirA, isEnabled: true))
        host.load(InstalledPlugin(
            manifest: PluginManifest(name: "B", identifier: "com.b", version: "1", main: "main.js", commands: command),
            directory: dirB, isEnabled: true))

        host.invoke(pluginIdentifier: "com.a", commandID: "who")
        host.invoke(pluginIdentifier: "com.b", commandID: "who")
        XCTAssertEqual(bridge.messages, ["A", "B"], "each plugin keeps its own scope")
    }

    func testEvaluateReturnsValuesAndErrors() {
        let host = PluginHost(bridge: StubBridge())
        XCTAssertEqual(host.evaluate("1 + 2").value, "3")
        XCTAssertNotNil(host.evaluate("throw new Error('nope')").error)
    }
}
