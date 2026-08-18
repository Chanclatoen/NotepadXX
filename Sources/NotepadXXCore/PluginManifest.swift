import Foundation

/// A plugin's `plugin.json`.
public struct PluginManifest: Codable, Equatable, Sendable {
    public struct Command: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// JavaScript function name to invoke, defaulting to `id`.
        public var handler: String?
        public var keyEquivalent: String?
        public init(id: String, title: String, handler: String? = nil, keyEquivalent: String? = nil) {
            self.id = id
            self.title = title
            self.handler = handler
            self.keyEquivalent = keyEquivalent
        }
        public var handlerName: String { handler ?? id }
    }

    public var name: String
    public var identifier: String
    public var version: String
    public var description: String?
    public var author: String?
    /// Script file relative to the plugin directory.
    public var main: String
    public var commands: [Command]
    /// Minimum NotepadXX version, checked before loading.
    public var minimumAppVersion: String?

    public init(
        name: String, identifier: String, version: String, main: String,
        description: String? = nil, author: String? = nil,
        commands: [Command] = [], minimumAppVersion: String? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.version = version
        self.main = main
        self.description = description
        self.author = author
        self.commands = commands
        self.minimumAppVersion = minimumAppVersion
    }
}

/// A plugin found on disk.
public struct InstalledPlugin: Equatable, Sendable, Identifiable {
    public var manifest: PluginManifest
    public var directory: URL
    public var isEnabled: Bool
    public var loadError: String?

    public var id: String { manifest.identifier }
    public var scriptURL: URL { directory.appendingPathComponent(manifest.main) }

    public init(manifest: PluginManifest, directory: URL, isEnabled: Bool, loadError: String? = nil) {
        self.manifest = manifest
        self.directory = directory
        self.isEnabled = isEnabled
        self.loadError = loadError
    }
}

/// Discovers, installs and removes plugins — the model behind Plugins Admin.
public final class PluginRegistry {
    public let pluginsDirectory: URL
    private let stateURL: URL
    public private(set) var plugins: [InstalledPlugin] = []
    /// Identifiers explicitly disabled by the user.
    private var disabled: Set<String> = []

    public init(directory: URL) throws {
        self.pluginsDirectory = directory.appendingPathComponent("plugins", isDirectory: true)
        self.stateURL = directory.appendingPathComponent("plugin-state.json")
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        loadState()
        reload()
    }

    public enum PluginError: Error, Equatable {
        case notAPluginDirectory(String)
        case malformedManifest(String)
        case duplicateIdentifier(String)
        case notInstalled(String)
    }

    /// Scans the plugins directory. A broken plugin is listed with its error
    /// rather than dropped, so the user can see why it did not load.
    public func reload() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: pluginsDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        var found: [InstalledPlugin] = []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let manifestURL = entry.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            do {
                let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
                let plugin = InstalledPlugin(
                    manifest: manifest, directory: entry,
                    isEnabled: !disabled.contains(manifest.identifier),
                    loadError: FileManager.default.fileExists(atPath: entry.appendingPathComponent(manifest.main).path)
                        ? nil : "missing script \(manifest.main)"
                )
                if found.contains(where: { $0.id == plugin.id }) {
                    found.append(InstalledPlugin(
                        manifest: manifest, directory: entry, isEnabled: false,
                        loadError: "duplicate identifier \(manifest.identifier)"
                    ))
                } else {
                    found.append(plugin)
                }
            } catch {
                // Surface the parse failure against the folder name.
                let manifest = PluginManifest(
                    name: entry.lastPathComponent, identifier: entry.lastPathComponent,
                    version: "?", main: ""
                )
                found.append(InstalledPlugin(
                    manifest: manifest, directory: entry, isEnabled: false,
                    loadError: "malformed plugin.json"
                ))
            }
        }
        plugins = found.sorted { $0.manifest.name.lowercased() < $1.manifest.name.lowercased() }
    }

    public var enabledPlugins: [InstalledPlugin] {
        plugins.filter { $0.isEnabled && $0.loadError == nil }
    }

    public func setEnabled(_ enabled: Bool, forIdentifier identifier: String) {
        if enabled { disabled.remove(identifier) } else { disabled.insert(identifier) }
        saveState()
        reload()
    }

    /// Installs a plugin from a folder containing a plugin.json.
    @discardableResult
    public func install(from source: URL) throws -> InstalledPlugin {
        let manifestURL = source.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw PluginError.notAPluginDirectory(source.lastPathComponent)
        }
        guard let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            throw PluginError.malformedManifest(source.lastPathComponent)
        }
        if plugins.contains(where: { $0.id == manifest.identifier && $0.loadError == nil }) {
            throw PluginError.duplicateIdentifier(manifest.identifier)
        }

        // The identifier names the folder, so uninstall is unambiguous.
        let destination = pluginsDirectory.appendingPathComponent(
            Self.safeFolderName(for: manifest.identifier), isDirectory: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        reload()
        guard let installed = plugins.first(where: { $0.id == manifest.identifier }) else {
            throw PluginError.notInstalled(manifest.identifier)
        }
        return installed
    }

    /// A folder name derived from an identifier that cannot traverse out of
    /// the plugins directory, whatever the manifest claims.
    static func safeFolderName(for identifier: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = identifier.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                // Collapse any run of dots so no ".." component can survive.
                if character == ".", result.last == "." { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return cleaned.isEmpty ? "plugin" : cleaned
    }

    public func uninstall(identifier: String) throws {
        guard let plugin = plugins.first(where: { $0.id == identifier }) else {
            throw PluginError.notInstalled(identifier)
        }
        try FileManager.default.removeItem(at: plugin.directory)
        disabled.remove(identifier)
        saveState()
        reload()
    }

    // MARK: - Enabled/disabled state

    private func saveState() {
        try? JSONEncoder().encode(Array(disabled)).write(to: stateURL, options: .atomic)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        disabled = Set(list)
    }
}
