import Foundation

/// A caret position as a 0-based line and column.
public struct TextPosition: Equatable, Sendable, Comparable {
    public var line: Int
    public var column: Int
    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.line == rhs.line ? lhs.column < rhs.column : lhs.line < rhs.line
    }
}

/// Rectangular (column) selection and the Column Editor.
///
/// The underlying text engine has multi-selection but no rectangular selection,
/// so column mode is expressed as one range per spanned line, all covering the
/// same column span. That is also exactly what makes column *editing* work:
/// typing with N ranges selected edits all N lines at once.
///
/// Lines shorter than the selection's start column contribute an empty range at
/// their end, which is how Notepad++ lets you select and then type into a
/// ragged block ("virtual space").
public enum ColumnSelection {

    /// Start offset of every line, plus each line's length excluding terminator.
    static func lineIndex(of text: String) -> [(start: Int, length: Int)] {
        let content = text as NSString
        var result: [(Int, Int)] = []
        var start = 0
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: [.byLines]
        ) { substring, substringRange, enclosingRange, _ in
            result.append((substringRange.location, (substring as NSString? ?? "").length))
            start = NSMaxRange(enclosingRange)
        }
        // A trailing terminator leaves a final empty line the enumerator skips.
        if result.isEmpty || start == content.length, content.length == 0 || text.hasSuffix("\n") {
            result.append((content.length, 0))
        }
        return result
    }

    public static func position(ofOffset offset: Int, in text: String) -> TextPosition {
        let lines = lineIndex(of: text)
        var low = 0, high = lines.count - 1, index = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= offset { index = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return TextPosition(line: index, column: offset - lines[index].start)
    }

    public static func offset(of position: TextPosition, in text: String) -> Int {
        let lines = lineIndex(of: text)
        guard !lines.isEmpty else { return 0 }
        let line = min(max(0, position.line), lines.count - 1)
        let column = min(max(0, position.column), lines[line].length)
        return lines[line].start + column
    }

    /// The ranges making up a rectangular selection between two corners.
    /// Order of the corners does not matter.
    public static func ranges(in text: String, from anchor: TextPosition, to target: TextPosition) -> [NSRange] {
        let lines = lineIndex(of: text)
        guard !lines.isEmpty else { return [] }

        let firstLine = min(anchor.line, target.line)
        let lastLine = max(anchor.line, target.line)
        let startColumn = min(anchor.column, target.column)
        let endColumn = max(anchor.column, target.column)

        var ranges: [NSRange] = []
        for line in max(0, firstLine)...min(lastLine, lines.count - 1) {
            let (start, length) = lines[line]
            // Clamp to the line: short lines yield an empty range at their end
            // rather than being dropped, so typing still affects them.
            let from = min(startColumn, length)
            let to = min(endColumn, length)
            ranges.append(NSRange(location: start + from, length: max(0, to - from)))
        }
        return ranges
    }

    // MARK: - Column Editor

    /// Notepad++'s Column Editor, "Text to insert" mode: the same text on every
    /// line of the block.
    public static func insertText(
        _ insertion: String, in text: String, lines lineRange: ClosedRange<Int>, column: Int
    ) -> String {
        applyPerLine(text, lineRange) { _, _ in insertion } columnProvider: { column }
    }

    /// Notepad++'s Column Editor, "Number to insert" mode: an incrementing
    /// number down the block, optionally zero-padded.
    public static func insertNumbers(
        in text: String, lines lineRange: ClosedRange<Int>, column: Int,
        initial: Int, increment: Int, repeatCount: Int = 1,
        leadingZeros: Bool = false, format: NumberFormat = .decimal
    ) -> String {
        var value = initial
        var emitted = 0
        // Width is computed from the largest value so padding is stable.
        let lineCount = max(1, lineRange.count)
        let maximum = initial + increment * ((lineCount - 1) / max(1, repeatCount))
        let width = format.string(for: maximum).count

        return applyPerLine(text, lineRange) { _, _ in
            let rendered = format.string(for: value)
            let padded = leadingZeros
                ? String(repeating: "0", count: max(0, width - rendered.count)) + rendered
                : rendered
            emitted += 1
            if emitted % max(1, repeatCount) == 0 { value += increment }
            return padded
        } columnProvider: { column }
    }

    public enum NumberFormat: Sendable {
        case decimal, octal, hexadecimal, binary

        public func string(for value: Int) -> String {
            switch self {
            case .decimal: return String(value)
            case .octal: return String(value, radix: 8)
            case .hexadecimal: return String(value, radix: 16)
            case .binary: return String(value, radix: 2)
            }
        }
    }

    /// Inserts a per-line string at `column`, padding short lines with spaces so
    /// the inserted block stays aligned.
    private static func applyPerLine(
        _ text: String, _ lineRange: ClosedRange<Int>,
        _ makeInsertion: (Int, String) -> String,
        columnProvider: () -> Int
    ) -> String {
        let (lines, trailing) = LineOperations.split(text)
        guard !lines.isEmpty else { return text }
        var result = lines
        let lower = max(0, lineRange.lowerBound)
        let upper = min(lines.count - 1, lineRange.upperBound)
        guard lower <= upper else { return text }

        let column = columnProvider()
        for index in lower...upper {
            let line = result[index]
            let insertion = makeInsertion(index, line)
            let content = line as NSString
            if column <= content.length {
                result[index] = content.replacingCharacters(in: NSRange(location: column, length: 0), with: insertion)
            } else {
                result[index] = line + String(repeating: " ", count: column - content.length) + insertion
            }
        }
        return LineOperations.join(result, hadTrailingNewline: trailing)
    }
}
