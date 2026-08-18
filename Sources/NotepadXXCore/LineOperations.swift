import Foundation

/// Notepad++'s Edit > Line Operations and Blank Operations menus.
///
/// Everything here works on LF-separated text, which is the in-memory
/// normalisation guaranteed by `TextDocument`. Operating on `[String]` lines
/// keeps these independent of the editor and cheap to test.
public enum LineOperations {

    /// Splits into lines, remembering whether the text ended with a terminator
    /// so it can be reconstructed exactly.
    public static func split(_ text: String) -> (lines: [String], hadTrailingNewline: Bool) {
        guard !text.isEmpty else { return ([], false) }
        let trailing = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if trailing { lines.removeLast() }
        return (lines, trailing)
    }

    public static func join(_ lines: [String], hadTrailingNewline: Bool) -> String {
        let body = lines.joined(separator: "\n")
        return hadTrailingNewline ? body + "\n" : body
    }

    private static func transform(_ text: String, _ body: ([String]) -> [String]) -> String {
        let (lines, trailing) = split(text)
        return join(body(lines), hadTrailingNewline: trailing)
    }

    // MARK: - Duplicate / remove / move

    public static func duplicate(_ text: String, range: ClosedRange<Int>) -> String {
        transform(text) { lines in
            guard let clamped = clamp(range, to: lines) else { return lines }
            var result = lines
            result.insert(contentsOf: lines[clamped], at: clamped.upperBound + 1)
            return result
        }
    }

    public static func remove(_ text: String, range: ClosedRange<Int>) -> String {
        transform(text) { lines in
            guard let clamped = clamp(range, to: lines) else { return lines }
            var result = lines
            result.removeSubrange(clamped)
            return result
        }
    }

    public static func moveUp(_ text: String, range: ClosedRange<Int>) -> String {
        transform(text) { lines in
            guard let clamped = clamp(range, to: lines), clamped.lowerBound > 0 else { return lines }
            var result = lines
            let block = Array(result[clamped])
            result.removeSubrange(clamped)
            result.insert(contentsOf: block, at: clamped.lowerBound - 1)
            return result
        }
    }

    public static func moveDown(_ text: String, range: ClosedRange<Int>) -> String {
        transform(text) { lines in
            guard let clamped = clamp(range, to: lines), clamped.upperBound < lines.count - 1 else { return lines }
            var result = lines
            let block = Array(result[clamped])
            result.removeSubrange(clamped)
            result.insert(contentsOf: block, at: clamped.lowerBound + 1)
            return result
        }
    }

    /// Joins the given lines into one, as Edit > Line Operations > Join Lines.
    /// Joins lines, inserting a single space at any boundary that does not
    /// already have whitespace on one side.
    ///
    /// This matches Scintilla's SCI_LINESJOIN, which is what Notepad++ uses:
    /// plain concatenation would run the last word of one line into the first
    /// word of the next.
    public static func joinLines(_ text: String, range: ClosedRange<Int>) -> String {
        transform(text) { lines in
            guard let clamped = clamp(range, to: lines), clamped.count > 1 else { return lines }
            var result = lines
            var merged = ""
            for line in lines[clamped] {
                if merged.isEmpty {
                    merged = line
                    continue
                }
                let needsSpace = !(merged.last?.isWhitespace ?? true)
                    && !(line.first?.isWhitespace ?? true)
                merged += (needsSpace ? " " : "") + line
            }
            result.replaceSubrange(clamped, with: [merged])
            return result
        }
    }

    // MARK: - Duplicate removal

    /// Removes consecutive duplicates only — Notepad++ distinguishes this from
    /// removing every duplicate anywhere in the file.
    public static func removeConsecutiveDuplicates(_ text: String) -> String {
        transform(text) { lines in
            var result: [String] = []
            for line in lines where result.last != line { result.append(line) }
            return result
        }
    }

    public static func removeAllDuplicates(_ text: String) -> String {
        transform(text) { lines in
            var seen = Set<String>()
            return lines.filter { seen.insert($0).inserted }
        }
    }

    // MARK: - Sorting

    public enum SortMode: Sendable {
        case lexicographic(caseSensitive: Bool)
        case integer
        case decimal
        case byLength
        case reverseOrder
        case randomize
    }

    public static func sort(_ text: String, mode: SortMode, ascending: Bool = true,
                            shuffle: ([String]) -> [String] = { $0.shuffled() }) -> String {
        transform(text) { lines in
            var result: [String]
            switch mode {
            case .reverseOrder:
                return lines.reversed()
            case .randomize:
                return shuffle(lines)
            case .lexicographic(let caseSensitive):
                result = lines.sorted { a, b in
                    caseSensitive ? a < b : a.lowercased() < b.lowercased()
                }
            case .byLength:
                result = lines.sorted { $0.count < $1.count }
            case .integer:
                result = lines.sorted { numericKey($0, decimal: false) < numericKey($1, decimal: false) }
            case .decimal:
                result = lines.sorted { numericKey($0, decimal: true) < numericKey($1, decimal: true) }
            }
            return ascending ? result : result.reversed()
        }
    }

    /// Lines without a leading number sort before numbered ones, matching
    /// Notepad++'s behaviour of treating them as the lowest value.
    private static func numericKey(_ line: String, decimal: Bool) -> Double {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        for character in trimmed {
            if character.isNumber || (digits.isEmpty && (character == "-" || character == "+")) {
                digits.append(character)
            } else if decimal && character == "." && !digits.contains(".") {
                digits.append(character)
            } else {
                break
            }
        }
        return Double(digits) ?? -Double.greatestFiniteMagnitude
    }

    // MARK: - Blank operations

    public static func trimTrailingWhitespace(_ text: String) -> String {
        transform(text) { $0.map { line in
            var result = line
            while let last = result.last, last == " " || last == "\t" { result.removeLast() }
            return result
        } }
    }

    public static func trimLeadingWhitespace(_ text: String) -> String {
        transform(text) { $0.map { line in
            var result = Substring(line)
            while let first = result.first, first == " " || first == "\t" { result = result.dropFirst() }
            return String(result)
        } }
    }

    public static func trimBothEnds(_ text: String) -> String {
        trimLeadingWhitespace(trimTrailingWhitespace(text))
    }

    public static func removeEmptyLines(_ text: String, keepingWhitespaceOnly: Bool) -> String {
        transform(text) { lines in
            lines.filter { line in
                keepingWhitespaceOnly
                    ? !line.isEmpty
                    : !line.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    // MARK: - Tab / space conversion

    /// Expands tabs to the next tab stop, which is column-aware rather than a
    /// blind replace — a tab mid-line advances to the stop, not by `width`.
    /// Converts runs of spaces to tabs. `leadingOnly` matches Notepad++'s
    /// "Space to TAB (Leading)", which is the safer of the two: converting
    /// spaces inside a string literal or aligned comment would change meaning.
    public static func spacesToTabs(_ text: String, width: Int, leadingOnly: Bool = false) -> String {
        guard width > 0 else { return text }
        let run = String(repeating: " ", count: width)
        let (lines, trailing) = split(text)

        let converted = lines.map { line -> String in
            if leadingOnly {
                let body = line.drop { $0 == " " }
                let indent = line.count - body.count
                let tabs = String(repeating: "\t", count: indent / width)
                let remainder = String(repeating: " ", count: indent % width)
                return tabs + remainder + body
            }
            return line.replacingOccurrences(of: run, with: "\t")
        }
        return join(converted, hadTrailingNewline: trailing)
    }

    public static func tabsToSpaces(_ text: String, width: Int) -> String {
        precondition(width > 0, "tab width must be positive")
        return transform(text) { $0.map { line in
            var result = ""
            var column = 0
            for character in line {
                if character == "\t" {
                    let advance = width - (column % width)
                    result += String(repeating: " ", count: advance)
                    column += advance
                } else {
                    result.append(character)
                    column += 1
                }
            }
            return result
        } }
    }

    /// Converts runs of spaces that reach a tab stop back into tabs. Only leading
    /// indentation is converted, matching Notepad++'s "Space to Tab (Leading)".
    public static func leadingSpacesToTabs(_ text: String, width: Int) -> String {
        precondition(width > 0, "tab width must be positive")
        return transform(text) { $0.map { line in
            var indentWidth = 0
            var index = line.startIndex
            while index < line.endIndex {
                if line[index] == " " { indentWidth += 1 }
                else if line[index] == "\t" { indentWidth += width - (indentWidth % width) }
                else { break }
                index = line.index(after: index)
            }
            let tabs = indentWidth / width
            let spaces = indentWidth % width
            return String(repeating: "\t", count: tabs)
                + String(repeating: " ", count: spaces)
                + String(line[index...])
        } }
    }

    // MARK: - Helpers

    private static func clamp(_ range: ClosedRange<Int>, to lines: [String]) -> ClosedRange<Int>? {
        guard !lines.isEmpty else { return nil }
        let lower = max(0, range.lowerBound)
        let upper = min(lines.count - 1, range.upperBound)
        guard lower <= upper else { return nil }
        return lower...upper
    }
}
