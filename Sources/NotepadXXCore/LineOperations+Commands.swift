import Foundation

/// Comment toggling, indent/unindent and Split Lines: the line commands that
/// Notepad++ binds to Ctrl+Q, Ctrl+Shift+Q, Tab/Shift+Tab and Ctrl+I.
extension LineOperations {

    /// The lines of `text`, or one empty line for an empty document, so a
    /// command on an empty buffer still has a line to work on.
    private static func linesForEditing(_ text: String) -> (lines: [String], trailing: Bool) {
        let (lines, trailing) = split(text)
        return (lines.isEmpty ? [""] : lines, trailing)
    }

    private static func leadingWhitespace(_ line: String) -> Substring {
        line.prefix { $0 == " " || $0 == "\t" }
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    // MARK: - Line comments

    /// True when every non-blank line in `range` already starts with `token`
    /// (after its indentation), which is what makes the toggle remove it.
    public static func isLineCommented(_ text: String, range: ClosedRange<Int>, token: String) -> Bool {
        let (lines, _) = linesForEditing(text)
        let selected = lines[max(0, range.lowerBound)...min(lines.count - 1, range.upperBound)]
            .filter { !isBlank($0) }
        return !selected.isEmpty && selected.allSatisfy {
            $0.dropFirst(leadingWhitespace($0).count).hasPrefix(token)
        }
    }

    /// Notepad++ "Toggle Single Line Comment": comments the lines, or
    /// uncomments them when they are all commented already. The token goes in
    /// at the shallowest indentation of the range so the block stays aligned,
    /// followed by one space; blank lines are left alone.
    public static func toggleLineComment(_ text: String, range: ClosedRange<Int>, token: String) -> String {
        guard !token.isEmpty else { return text }
        var (lines, trailing) = linesForEditing(text)
        let lower = max(0, range.lowerBound), upper = min(lines.count - 1, range.upperBound)
        guard lower <= upper else { return text }

        if isLineCommented(text, range: range, token: token) {
            for index in lower...upper where !isBlank(lines[index]) {
                let indent = leadingWhitespace(lines[index])
                var rest = lines[index].dropFirst(indent.count + token.count)
                if rest.first == " " { rest = rest.dropFirst() }
                lines[index] = String(indent) + rest
            }
        } else {
            let depth = lines[lower...upper].filter { !isBlank($0) }
                .map { leadingWhitespace($0).count }.min() ?? 0
            for index in lower...upper where !isBlank(lines[index]) {
                let line = lines[index]
                let split = line.index(line.startIndex, offsetBy: depth)
                lines[index] = String(line[..<split]) + token + " " + String(line[split...])
            }
            // A lone empty line (an empty document) still takes the marker.
            if lower == upper, isBlank(lines[lower]) { lines[lower] += token + " " }
        }
        return join(lines, hadTrailingNewline: trailing)
    }

    // MARK: - Block comments

    /// Result of an edit that also moves the selection.
    public struct SelectionEdit: Equatable, Sendable {
        public var text: String
        public var selection: NSRange
    }

    /// Notepad++ "Toggle Block Comment": wraps `selection` in the delimiters,
    /// or removes them when the selection is already wrapped. With no
    /// selection the current line's text (without its indentation) is used.
    public static func toggleBlockComment(
        _ text: String, selection: NSRange, open: String, close: String
    ) -> SelectionEdit {
        let content = text as NSString
        var target = NSIntersectionRange(selection, NSRange(location: 0, length: content.length))
        if target.length == 0 {
            let line = content.lineRange(for: NSRange(location: min(selection.location, content.length), length: 0))
            var body = line
            while body.length > 0, content.character(at: NSMaxRange(body) - 1) == 10 { body.length -= 1 }
            let indent = leadingWhitespace(content.substring(with: body)).utf16.count
            target = NSRange(location: body.location + indent, length: body.length - indent)
        }
        let selected = content.substring(with: target)
        let wrapped = selected.hasPrefix(open) && selected.hasSuffix(close)
            && selected.utf16.count >= open.utf16.count + close.utf16.count
        let replacement: String
        if wrapped {
            var inner = String(selected.dropFirst(open.count).dropLast(close.count))
            if inner.hasPrefix(" ") && inner.hasSuffix(" ") && inner.count >= 2 {
                inner = String(inner.dropFirst().dropLast())
            }
            replacement = inner
        } else {
            replacement = open + " " + selected + " " + close
        }
        let result = content.replacingCharacters(in: target, with: replacement)
        return SelectionEdit(text: result,
                             selection: NSRange(location: target.location, length: replacement.utf16.count))
    }

    // MARK: - Indent

    /// Adds one level of indentation to every non-empty line in `range`.
    public static func indent(_ text: String, range: ClosedRange<Int>, unit: String) -> String {
        var (lines, trailing) = linesForEditing(text)
        let lower = max(0, range.lowerBound), upper = min(lines.count - 1, range.upperBound)
        guard lower <= upper else { return text }
        for index in lower...upper where !lines[index].isEmpty || lower == upper {
            lines[index] = unit + lines[index]
        }
        return join(lines, hadTrailingNewline: trailing)
    }

    /// Removes one level of indentation from every line in `range`: a tab, or
    /// up to `width` spaces.
    public static func unindent(_ text: String, range: ClosedRange<Int>, width: Int) -> String {
        var (lines, trailing) = linesForEditing(text)
        let lower = max(0, range.lowerBound), upper = min(lines.count - 1, range.upperBound)
        guard lower <= upper else { return text }
        for index in lower...upper {
            let line = lines[index]
            if line.hasPrefix("\t") {
                lines[index] = String(line.dropFirst())
            } else {
                let spaces = line.prefix(while: { $0 == " " }).count
                lines[index] = String(line.dropFirst(min(spaces, max(1, width))))
            }
        }
        return join(lines, hadTrailingNewline: trailing)
    }

    // MARK: - Split lines

    /// Notepad++ "Split Lines": breaks every line in `range` longer than
    /// `width` characters, at the last space before the limit when there is
    /// one and in the middle of a word otherwise. Indentation carries over.
    public static func splitLines(_ text: String, range: ClosedRange<Int>, width: Int) -> String {
        guard width > 0 else { return text }
        let (lines, trailing) = linesForEditing(text)
        let lower = max(0, range.lowerBound), upper = min(lines.count - 1, range.upperBound)
        guard lower <= upper else { return text }
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            guard index >= lower, index <= upper else { result.append(line); continue }
            result.append(contentsOf: wrap(line, width: width))
        }
        return join(result, hadTrailingNewline: trailing)
    }

    private static func wrap(_ line: String, width: Int) -> [String] {
        let indent = String(leadingWhitespace(line))
        // Room for text after the carried-over indentation; always at least one character.
        let room = max(1, width - indent.count)
        var pieces: [String] = []
        var rest = Substring(line)
        var first = true
        while rest.count > (first ? width : room) {
            let limit = first ? width : room
            let window = rest.prefix(limit + 1)
            var cut = window.lastIndex(of: " ").flatMap { space -> Substring.Index? in
                // A space inside the indentation is not a place to break.
                window.distance(from: window.startIndex, to: space) > (first ? indent.count : 0) ? space : nil
            }
            if cut == nil { cut = rest.index(rest.startIndex, offsetBy: limit) }
            let head = rest[..<cut!]
            pieces.append(String((first ? "" : indent) + head))
            rest = rest[cut!...].drop(while: { $0 == " " })
            first = false
        }
        pieces.append(String((first ? "" : indent) + rest))
        return pieces
    }

    /// The UTF-16 range covering `lines` in `text`, without the final line
    /// terminator, for reselecting what a line command just changed.
    public static func characterRange(ofLines range: ClosedRange<Int>, in text: String) -> NSRange {
        let (lines, _) = linesForEditing(text)
        let lower = max(0, min(range.lowerBound, lines.count - 1))
        let upper = max(lower, min(range.upperBound, lines.count - 1))
        let start = lines[..<lower].reduce(0) { $0 + $1.utf16.count + 1 }
        let length = lines[lower...upper].reduce(0) { $0 + $1.utf16.count + 1 } - 1
        return NSRange(location: start, length: max(0, length))
    }
}
