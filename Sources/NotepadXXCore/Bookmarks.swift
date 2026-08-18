import Foundation

/// Bookmarked lines for one document, plus the line-oriented operations
/// Notepad++ offers on them (cut/copy/remove/inverse).
public struct Bookmarks: Equatable, Sendable, Codable {
    /// 0-based line numbers.
    public private(set) var lines: Set<Int> = []

    public init(lines: Set<Int> = []) { self.lines = lines }

    public var isEmpty: Bool { lines.isEmpty }
    public func contains(_ line: Int) -> Bool { lines.contains(line) }

    public mutating func toggle(_ line: Int) {
        if lines.contains(line) { lines.remove(line) } else { lines.insert(line) }
    }

    public mutating func clear() { lines.removeAll() }

    /// Bookmarks every line that is not currently bookmarked.
    public mutating func invert(totalLines: Int) {
        lines = Set(0..<max(0, totalLines)).subtracting(lines)
    }

    /// The next bookmark after `line`, wrapping to the first.
    public func next(after line: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        return lines.filter { $0 > line }.min() ?? lines.min()
    }

    /// The previous bookmark before `line`, wrapping to the last.
    public func previous(before line: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        return lines.filter { $0 < line }.max() ?? lines.max()
    }

    /// Keeps bookmarks pointing at the right lines after an edit inserted or
    /// removed whole lines above them.
    public mutating func shift(fromLine line: Int, by delta: Int) {
        guard delta != 0 else { return }
        lines = Set(lines.map { $0 >= line ? $0 + delta : $0 }.filter { $0 >= 0 })
    }

    /// The text of the bookmarked lines, in document order.
    public func markedText(in text: String) -> String {
        let (all, _) = LineOperations.split(text)
        return lines.sorted().compactMap { all.indices.contains($0) ? all[$0] : nil }
            .joined(separator: "\n")
    }

    /// Removes the bookmarked lines from `text`, returning the remainder.
    public func removingMarkedLines(from text: String) -> String {
        let (all, trailing) = LineOperations.split(text)
        let kept = all.enumerated().filter { !lines.contains($0.offset) }.map(\.element)
        return LineOperations.join(kept, hadTrailingNewline: trailing)
    }
}
