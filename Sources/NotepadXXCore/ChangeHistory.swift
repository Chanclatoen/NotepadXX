import Foundation

/// Tracks which lines changed since the file was opened or last saved, feeding
/// Notepad++'s change-history margin and its navigation commands.
///
/// Lines are tracked in two tiers, as Notepad++ does: *modified* (edited since
/// the last save) and *saved* (edited earlier in this session but since written
/// to disk). That distinction is the whole value of the margin — it shows both
/// what is unsaved and what you have touched this session.
public struct ChangeHistory: Equatable, Sendable {
    public private(set) var modifiedLines: Set<Int> = []
    public private(set) var savedLines: Set<Int> = []

    public init() {}

    public var isEmpty: Bool { modifiedLines.isEmpty && savedLines.isEmpty }

    public enum State: Equatable, Sendable { case unchanged, modified, saved }

    public func state(of line: Int) -> State {
        if modifiedLines.contains(line) { return .modified }
        if savedLines.contains(line) { return .saved }
        return .unchanged
    }

    public mutating func recordEdit(atLine line: Int) {
        modifiedLines.insert(line)
        savedLines.remove(line)
    }

    public mutating func recordEdit(inLines range: ClosedRange<Int>) {
        for line in range { recordEdit(atLine: line) }
    }

    /// Saving promotes modified lines to saved: they are on disk now, but the
    /// user still edited them this session.
    public mutating func didSave() {
        savedLines.formUnion(modifiedLines)
        modifiedLines.removeAll()
    }

    /// Reloading or closing clears everything.
    public mutating func reset() {
        modifiedLines.removeAll()
        savedLines.removeAll()
    }

    /// Keeps marks aligned when whole lines are inserted or removed above them.
    public mutating func shift(fromLine line: Int, by delta: Int) {
        guard delta != 0 else { return }
        func move(_ set: Set<Int>) -> Set<Int> {
            Set(set.map { $0 >= line ? $0 + delta : $0 }.filter { $0 >= 0 })
        }
        modifiedLines = move(modifiedLines)
        savedLines = move(savedLines)
    }

    /// All changed lines, for next/previous navigation.
    public var allChangedLines: [Int] {
        modifiedLines.union(savedLines).sorted()
    }

    public func nextChange(after line: Int) -> Int? {
        let lines = allChangedLines
        guard !lines.isEmpty else { return nil }
        return lines.first { $0 > line } ?? lines.first
    }

    public func previousChange(before line: Int) -> Int? {
        let lines = allChangedLines
        guard !lines.isEmpty else { return nil }
        return lines.last { $0 < line } ?? lines.last
    }
}

/// Finds URLs in text so the editor can make them clickable.
public enum URLDetection {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Ranges of links within `text`, restricted to `range` when given.
    public static func links(in text: String, range: NSRange? = nil) -> [(range: NSRange, url: URL)] {
        let content = text as NSString
        let searchRange = range.map {
            NSIntersectionRange($0, NSRange(location: 0, length: content.length))
        } ?? NSRange(location: 0, length: content.length)
        guard searchRange.length > 0, let detector else { return [] }

        return detector.matches(in: text, options: [], range: searchRange).compactMap { match in
            guard let url = match.url else { return nil }
            return (match.range, url)
        }
    }

    /// The link at `location`, if any — used for click handling.
    public static func link(at location: Int, in text: String) -> URL? {
        // Only scan the surrounding line; scanning a huge document per click
        // would be wasteful and is never necessary.
        let content = text as NSString
        guard location >= 0, location <= content.length else { return nil }
        let lineRange = content.lineRange(for: NSRange(location: min(location, max(0, content.length - 1)), length: 0))
        return links(in: text, range: lineRange).first { NSLocationInRange(location, $0.range) }?.url
    }
}
