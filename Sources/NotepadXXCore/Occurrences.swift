import Foundation

/// Finds repeated occurrences of a string, for multi-cursor selection.
///
/// Separate from the search engine because this is always a literal,
/// case-sensitive, whole-token match against the live buffer — the semantics
/// people expect from "select next occurrence", regardless of what the Find
/// dialog is currently set to.
public enum Occurrences {

    /// The word surrounding `location`, and its range.
    public static func word(at location: Int, in text: String) -> (text: String, range: NSRange)? {
        let content = text as NSString
        guard location >= 0, location <= content.length, content.length > 0 else { return nil }

        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < content.length else { return false }
            let scalar = content.substring(with: NSRange(location: index, length: 1)).unicodeScalars.first
            guard let scalar else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }

        // A caret just past a word still counts as being on it.
        var start = location
        if !isWordCharacter(start) && isWordCharacter(start - 1) { start -= 1 }
        guard isWordCharacter(start) else { return nil }

        var end = start
        while isWordCharacter(start - 1) { start -= 1 }
        while isWordCharacter(end + 1) { end += 1 }

        let range = NSRange(location: start, length: end - start + 1)
        return (content.substring(with: range), range)
    }

    /// Every occurrence of `needle`, optionally requiring whole-word matches.
    public static func all(of needle: String, in text: String, wholeWord: Bool = false) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let content = text as NSString
        var found: [NSRange] = []
        var searchStart = 0

        while searchStart < content.length {
            let range = content.range(
                of: needle, options: [],
                range: NSRange(location: searchStart, length: content.length - searchStart)
            )
            guard range.location != NSNotFound else { break }
            if !wholeWord || isWholeWord(range, in: content) { found.append(range) }
            searchStart = range.location + max(1, range.length)
        }
        return found
    }

    /// The first occurrence starting after `location`, wrapping to the top.
    public static func next(
        of needle: String, in text: String, after location: Int, wholeWord: Bool = false
    ) -> NSRange? {
        let matches = all(of: needle, in: text, wholeWord: wholeWord)
        guard !matches.isEmpty else { return nil }
        return matches.first { $0.location > location } ?? matches.first
    }

    public static func previous(
        of needle: String, in text: String, before location: Int, wholeWord: Bool = false
    ) -> NSRange? {
        let matches = all(of: needle, in: text, wholeWord: wholeWord)
        guard !matches.isEmpty else { return nil }
        return matches.last { $0.location < location } ?? matches.last
    }

    private static func isWholeWord(_ range: NSRange, in content: NSString) -> Bool {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < content.length else { return false }
            let scalar = content.substring(with: NSRange(location: index, length: 1)).unicodeScalars.first
            guard let scalar else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        return !isWordCharacter(range.location - 1) && !isWordCharacter(NSMaxRange(range))
    }

    /// Merges overlapping or duplicate ranges, keeping document order.
    ///
    /// Two carets in the same place would double every keystroke, so this is
    /// what keeps a multi-selection well-formed as it grows.
    public static func normalized(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in sorted {
            guard let last = result.last else { result.append(range); continue }
            if range.location <= NSMaxRange(last) && NSMaxRange(range) >= last.location {
                // Overlapping: keep the union rather than two carets in one spot.
                let union = NSUnionRange(last, range)
                if union != last { result[result.count - 1] = union }
            } else {
                result.append(range)
            }
        }
        return result
    }
}
