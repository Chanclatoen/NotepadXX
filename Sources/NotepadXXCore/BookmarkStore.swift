import Foundation

/// Security-scoped bookmarks: the way a sandboxed app reaches a file or folder
/// the user picked in an earlier launch (recent files, session restore, the
/// backup folder, find-in-files folders). Persisted as `bookmarks.json`.
///
/// Inactive (`enabled == false`) in the direct build, where every method is a
/// pass-through and nothing is written.
public final class BookmarkStore {
    /// The app-wide store, set once at launch.
    nonisolated(unsafe) public static var shared: BookmarkStore?

    public let enabled: Bool
    private let url: URL
    private var table: [String: Data] = [:]
    private var started: [String: URL] = [:]
    private let lock = NSLock()

    public init(directory: URL, enabled: Bool = BuildFlavour.isAppStore) {
        self.enabled = enabled
        self.url = directory.appendingPathComponent("bookmarks.json")
        if enabled, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            table = decoded
        }
    }

    deinit { started.values.forEach { $0.stopAccessingSecurityScopedResource() } }

    /// One key per file whether the caller holds /var or /private/var.
    private static func key(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public func hasBookmark(for path: String) -> Bool { lock.withLock { table[Self.key(path)] != nil } }

    /// Call while the grant is live (right after the user picked it). Creating
    /// is skipped when a bookmark exists; a file we cannot reach is ignored.
    public func remember(_ target: URL) {
        guard enabled else { return }
        let path = Self.key(target.path)
        lock.withLock {
            guard table[path] == nil,
                  let data = try? target.bookmarkData(options: .withSecurityScope) else { return }
            table[path] = data
            save()
        }
    }

    public func forget(_ path: String) {
        let path = Self.key(path)
        lock.withLock {
            started.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
            if table.removeValue(forKey: path) != nil { save() }
        }
    }

    /// Opens access to `path` (or to the nearest remembered folder above it)
    /// and returns the URL to use. A stale bookmark is refreshed; one that no
    /// longer resolves is dropped. Returns nil when nothing grants access.
    @discardableResult
    public func access(_ path: String) -> URL? {
        guard enabled else { return URL(fileURLWithPath: path) }
        return lock.withLock {
            let path = Self.key(path)
            var candidate = path
            while true {
                if let resolved = resolve(candidate) {
                    return candidate == path ? resolved : URL(fileURLWithPath: path)
                }
                let parent = (candidate as NSString).deletingLastPathComponent
                if parent == candidate || parent.isEmpty || parent == "/" { return nil }
                candidate = parent
            }
        }
    }

    // Callers hold `lock`.
    private func resolve(_ key: String) -> URL? {
        if let live = started[key] { return live }
        guard let data = table[key] else { return nil }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
              resolved.startAccessingSecurityScopedResource() else {
            table[key] = nil
            save()
            return nil
        }
        if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope) {
            table[key] = fresh
            save()
        }
        started[key] = resolved
        return resolved
    }

    private func save() {
        try? JSONEncoder().encode(table).write(to: url, options: .atomic)
    }
}
