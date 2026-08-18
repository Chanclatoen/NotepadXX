import Foundation

/// One hit, with enough context to render a clickable Search Results row.
public struct FileSearchHit: Equatable, Sendable {
    public let url: URL
    public let lineNumber: Int
    public let lineText: String
    public let range: NSRange

    public init(url: URL, lineNumber: Int, lineText: String, range: NSRange) {
        self.url = url
        self.lineNumber = lineNumber
        self.lineText = lineText
        self.range = range
    }
}

public struct FileSearchResult: Equatable, Sendable {
    public let url: URL
    public let hits: [FileSearchHit]

    public init(url: URL, hits: [FileSearchHit]) {
        self.url = url
        self.hits = hits
    }
}

public struct FindInFilesOptions: Sendable {
    /// Semicolon or space separated globs, e.g. "*.swift *.txt". Empty means all.
    public var filters: String
    public var inSubfolders: Bool
    public var inHiddenFolders: Bool
    /// Skip files larger than this. Keeps a stray 2GB binary from stalling a search.
    public var maximumFileSize: Int

    public init(
        filters: String = "", inSubfolders: Bool = true,
        inHiddenFolders: Bool = false, maximumFileSize: Int = 64 * 1024 * 1024
    ) {
        self.filters = filters
        self.inSubfolders = inSubfolders
        self.inHiddenFolders = inHiddenFolders
        self.maximumFileSize = maximumFileSize
    }

    /// Parsed glob list; empty means "match everything".
    public var filterPatterns: [String] {
        filters
            .split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public func matchesFilter(_ name: String) -> Bool {
        let patterns = filterPatterns
        guard !patterns.isEmpty else { return true }
        return patterns.contains { pattern in
            NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: name)
        }
    }
}

/// Recursive find across a directory tree.
///
/// Content for a path present in `openBuffers` is taken from memory rather than
/// disk, so unsaved edits are searched — Notepad++ does the same, and getting it
/// wrong produces results that don't match what the user sees.
public struct FindInFiles {
    public let engine: SearchEngine
    public let options: FindInFilesOptions

    public init(engine: SearchEngine, options: FindInFilesOptions = FindInFilesOptions()) {
        self.engine = engine
        self.options = options
    }

    public func search(
        directory: URL,
        openBuffers: [String: String] = [:],
        isCancelled: () -> Bool = { false }
    ) throws -> [FileSearchResult] {
        var results: [FileSearchResult] = []
        // Key buffers by resolved path: /var/folders is a symlink to
        // /private/var/folders, so a caller's path and the enumerator's path can
        // refer to the same file yet compare unequal.
        let buffers = Dictionary(
            openBuffers.map { (Self.canonicalPath($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        for url in try enumerateFiles(in: directory) {
            if isCancelled() { break }
            let content: String?
            if let buffered = buffers[Self.canonicalPath(url.path)] {
                content = buffered
            } else {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            guard let text = content else { continue }
            let hits = try search(text: text, url: url)
            if !hits.isEmpty { results.append(FileSearchResult(url: url, hits: hits)) }
        }
        return results
    }

    /// Matches within one document, resolved to line numbers and line text.
    public func search(text: String, url: URL) throws -> [FileSearchHit] {
        let matches = try engine.matches(in: text)
        guard !matches.isEmpty else { return [] }

        // Build line start offsets once, then binary search per match, so a file
        // with many hits stays linear rather than rescanning from the top.
        let content = text as NSString
        var lineStarts: [Int] = [0]
        content.enumerateSubstrings(in: NSRange(location: 0, length: content.length),
                                    options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            lineStarts.append(NSMaxRange(enclosing))
        }

        return matches.map { match in
            let index = lineIndex(for: match.range.location, in: lineStarts)
            let start = lineStarts[index]
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : content.length
            let lineRange = NSRange(location: start, length: max(0, end - start))
            let lineText = content.substring(with: lineRange)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n\r"))
            return FileSearchHit(
                url: url, lineNumber: index + 1, lineText: lineText, range: match.range
            )
        }
    }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func lineIndex(for location: Int, in starts: [Int]) -> Int {
        var low = 0, high = starts.count - 1, answer = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= location { answer = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return answer
    }

    private func enumerateFiles(in directory: URL) throws -> [URL] {
        let manager = FileManager.default
        var files: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isHiddenKey]

        guard let enumerator = manager.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: options.inHiddenFolders ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if !options.inSubfolders && url != directory { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize, size > options.maximumFileSize { continue }
            guard options.matchesFilter(url.lastPathComponent) else { continue }
            files.append(url)
        }
        return files
    }
}
