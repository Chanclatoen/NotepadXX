import Foundation

/// The recently-opened file list behind File > Open Recent.
public final class RecentFiles {
    private let url: URL
    public private(set) var paths: [String] = []
    public var limit: Int {
        didSet { trim(); save() }
    }

    public init(directory: URL, limit: Int = 15) {
        self.url = directory.appendingPathComponent("recent-files.json")
        self.limit = limit
        load()
    }

    /// Most recent first, de-duplicated. Paths are resolved through symlinks so
    /// /var and /private/var forms of one file do not both appear.
    public func record(_ path: String) {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        paths.removeAll { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }
        paths.insert(resolved, at: 0)
        trim()
        save()
    }

    public func remove(_ path: String) {
        paths.removeAll { $0 == path }
        save()
    }

    public func clear() {
        paths.removeAll()
        save()
    }

    /// Drops entries whose file no longer exists — a recent list full of dead
    /// paths is worse than a short one.
    public func pruneMissing() {
        paths.removeAll { !FileManager.default.fileExists(atPath: $0) }
        save()
    }

    private func trim() {
        if paths.count > limit { paths.removeLast(paths.count - limit) }
    }

    private func save() {
        try? JSONEncoder().encode(paths).write(to: url, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        paths = decoded
        trim()
    }
}
