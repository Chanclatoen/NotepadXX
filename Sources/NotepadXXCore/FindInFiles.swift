import Foundation

/// One hit, with enough context to render a clickable Search Results row.
public struct FileSearchHit: Equatable, Sendable {
    public let url: URL
    public let lineNumber: Int
    public let lineText: String
    /// The match's range in the whole document.
    public let range: NSRange
    /// The same match, offset into `lineText`, so a results row can highlight
    /// it without recomputing where the line started.
    public let rangeInLine: NSRange

    public init(url: URL, lineNumber: Int, lineText: String, range: NSRange,
                rangeInLine: NSRange = NSRange(location: NSNotFound, length: 0)) {
        self.url = url
        self.lineNumber = lineNumber
        self.lineText = lineText
        self.range = range
        self.rangeInLine = rangeInLine
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
    /// Semicolon separated names to skip, e.g. "build/;.git/;*.xcodeproj". A
    /// trailing slash excludes a whole directory; otherwise it matches files.
    public var exclusions: String
    public var inSubfolders: Bool
    public var inHiddenFolders: Bool
    /// Skip files larger than this. Keeps a stray 2GB binary from stalling a search.
    public var maximumFileSize: Int

    public init(
        filters: String = "", exclusions: String = "", inSubfolders: Bool = true,
        inHiddenFolders: Bool = false, maximumFileSize: Int = 64 * 1024 * 1024
    ) {
        self.filters = filters
        self.exclusions = exclusions
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
            Self.glob(pattern, matches: name)
        }
    }

    /// Directory names to skip, written with a trailing slash.
    public var excludedDirectories: [String] {
        exclusionPatterns.filter { $0.hasSuffix("/") }.map { String($0.dropLast()) }
    }

    /// File globs to skip.
    public var excludedFiles: [String] {
        exclusionPatterns.filter { !$0.hasSuffix("/") }
    }

    private var exclusionPatterns: [String] {
        exclusions
            .split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public func isExcludedDirectory(_ name: String) -> Bool {
        excludedDirectories.contains { Self.glob($0, matches: name) }
    }

    public func isExcludedFile(_ name: String) -> Bool {
        excludedFiles.contains { Self.glob($0, matches: name) }
    }

    private static func glob(_ pattern: String, matches name: String) -> Bool {
        NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: name)
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
                url: url, lineNumber: index + 1, lineText: lineText, range: match.range,
                rangeInLine: NSRange(location: match.range.location - start,
                                     length: match.range.length)
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
                // Skipping descendants here is what makes an exclusion cheap:
                // an excluded build directory is never walked at all.
                if options.isExcludedDirectory(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if !options.inSubfolders && url != directory { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize, size > options.maximumFileSize { continue }
            guard options.matchesFilter(url.lastPathComponent) else { continue }
            guard !options.isExcludedFile(url.lastPathComponent) else { continue }
            files.append(url)
        }
        return files
    }
}
