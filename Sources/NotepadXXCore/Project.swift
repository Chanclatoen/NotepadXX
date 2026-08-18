import Foundation

/// A curated file list, as in Notepad++'s Project Panels.
///
/// Distinct from Folder as Workspace: a workspace mirrors a directory, whereas
/// a project is a hand-picked set of files that may live anywhere. Notepad++
/// offers both and they are not interchangeable.
public struct Project: Codable, Equatable, Hashable, Sendable {
    public struct Folder: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var filePaths: [String]
        public var folders: [Folder]

        public init(id: UUID = UUID(), name: String, filePaths: [String] = [], folders: [Folder] = []) {
            self.id = id
            self.name = name
            self.filePaths = filePaths
            self.folders = folders
        }

        /// Every file in this folder and below, in tree order.
        public var allFilePaths: [String] {
            filePaths + folders.flatMap(\.allFilePaths)
        }
    }

    public var name: String
    public var root: Folder

    public init(name: String, root: Folder? = nil) {
        self.name = name
        self.root = root ?? Folder(name: name)
    }

    public var allFilePaths: [String] { root.allFilePaths }

    /// Files that no longer exist. A project quietly full of dead entries is a
    /// common complaint, so surface them rather than hiding them.
    public func missingFilePaths() -> [String] {
        allFilePaths.filter { !FileManager.default.fileExists(atPath: $0) }
    }
}

public final class ProjectStore {
    private let directory: URL
    public private(set) var projects: [Project] = []

    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        projects = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Project.self, from: data)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent("\(sanitize(name)).json")
    }

    public func save(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: url(for: project.name), options: .atomic)
        reload()
    }

    public func delete(named name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        reload()
    }

    public func project(named name: String) -> Project? {
        projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Exports to an arbitrary location, for sharing a project file.
    public func export(_ project: Project, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: url, options: .atomic)
    }

    public func `import`(from url: URL) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: try Data(contentsOf: url))
        try save(project)
        return project
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let cleaned = name.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == ".", result.last == "." { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return cleaned.isEmpty ? "project" : cleaned
    }
}

/// Named sessions: save the current set of open documents under a name and
/// restore it later, alongside the automatic previous-session restore.
public final class NamedSessionStore {
    private let directory: URL
    public private(set) var names: [String] = []

    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        names = files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    private func url(for name: String) -> URL {
        directory.appendingPathComponent("\(name.replacingOccurrences(of: "/", with: "-")).json")
    }

    /// Only file-backed documents are recorded: a named session is a list of
    /// files to reopen, not a snapshot of unsaved scratch buffers (those are
    /// already covered by crash-safe autosave).
    public func save(name: String, documents: [TextDocument], activeIndex: Int) throws {
        let paths = documents.compactMap { $0.fileURL?.path }
        let session = NamedSession(name: name, filePaths: paths,
                                   activeIndex: min(activeIndex, max(0, paths.count - 1)))
        try JSONEncoder().encode(session).write(to: url(for: name), options: .atomic)
        reload()
    }

    public func load(name: String) -> NamedSession? {
        guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
        return try? JSONDecoder().decode(NamedSession.self, from: data)
    }

    public func delete(name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        reload()
    }
}

public struct NamedSession: Codable, Equatable, Sendable {
    public var name: String
    public var filePaths: [String]
    public var activeIndex: Int

    public init(name: String, filePaths: [String], activeIndex: Int) {
        self.name = name
        self.filePaths = filePaths
        self.activeIndex = activeIndex
    }
}
