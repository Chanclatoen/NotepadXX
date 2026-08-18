import Foundation

/// Remembers what was searched for and replaced with, as Notepad++'s Find
/// dialog dropdowns do.
public final class SearchHistory: Codable {
    public private(set) var patterns: [String] = []
    public private(set) var replacements: [String] = []
    public private(set) var directories: [String] = []
    public private(set) var filters: [String] = []
    public var limit: Int = 20

    private enum CodingKeys: String, CodingKey {
        case patterns, replacements, directories, filters, limit
    }

    public init(limit: Int = 20) { self.limit = limit }

    public enum Field { case pattern, replacement, directory, filter }

    public func record(_ value: String, in field: Field) {
        // An empty entry is not worth remembering, and re-searching the same
        // thing should move it to the top rather than add a duplicate.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        func push(_ list: inout [String]) {
            list.removeAll { $0 == trimmed }
            list.insert(trimmed, at: 0)
            if list.count > limit { list.removeLast(list.count - limit) }
        }
        switch field {
        case .pattern: push(&patterns)
        case .replacement: push(&replacements)
        case .directory: push(&directories)
        case .filter: push(&filters)
        }
    }

    public func entries(for field: Field) -> [String] {
        switch field {
        case .pattern: return patterns
        case .replacement: return replacements
        case .directory: return directories
        case .filter: return filters
        }
    }

    public func clear() {
        patterns.removeAll()
        replacements.removeAll()
        directories.removeAll()
        filters.removeAll()
    }

    // MARK: - Persistence

    public static func load(from directory: URL) -> SearchHistory {
        let url = directory.appendingPathComponent("search-history.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SearchHistory.self, from: data) else {
            return SearchHistory()
        }
        return decoded
    }

    public func save(to directory: URL) {
        let url = directory.appendingPathComponent("search-history.json")
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// Notepad++'s Mark tab: highlight every match in one of five styles, and
/// clear them again.
public struct MarkStyle: Equatable, Sendable {
    /// 0-4, matching Notepad++'s five mark styles.
    public let index: Int
    public init(index: Int) { self.index = max(0, min(4, index)) }

    public static let all = (0..<5).map(MarkStyle.init(index:))
}

public struct MarkedRanges: Equatable, Sendable {
    public private(set) var byStyle: [Int: [NSRange]] = [:]

    public init() {}

    public mutating func set(_ ranges: [NSRange], for style: MarkStyle) {
        byStyle[style.index] = ranges
    }

    public mutating func clear(_ style: MarkStyle) {
        byStyle[style.index] = nil
    }

    public mutating func clearAll() { byStyle.removeAll() }

    public func ranges(for style: MarkStyle) -> [NSRange] { byStyle[style.index] ?? [] }

    public var allRanges: [NSRange] {
        byStyle.values.flatMap { $0 }.sorted { $0.location < $1.location }
    }

    public var isEmpty: Bool { byStyle.values.allSatisfy(\.isEmpty) }

    /// The text of every marked range, for Notepad++'s "Copy Marked Text".
    public func markedText(in text: String) -> String {
        let content = text as NSString
        return allRanges
            .filter { NSMaxRange($0) <= content.length }
            .map { content.substring(with: $0) }
            .joined(separator: "\n")
    }
}
