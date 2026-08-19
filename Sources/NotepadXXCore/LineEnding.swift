import Foundation

/// The three line terminators Notepad++ exposes in its EOL menu and status bar.
public enum LineEnding: String, CaseIterable, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    /// Matches the wording Notepad++ uses in its status bar.
    public var displayName: String {
        switch self {
        case .lf: return "Unix (LF)"
        case .crlf: return "Windows (CR LF)"
        case .cr: return "Macintosh (CR)"
        }
    }

    /// The abbreviated form the status bar falls back to when space is short.
    public var shortName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }

    public static var platformDefault: LineEnding { .lf }

    /// Counts each terminator. CR and LF are only counted when they are *not*
    /// part of a CRLF pair, so a pure-CRLF document reports zero bare CR/LF.
    public static func counts(in string: String) -> (lf: Int, crlf: Int, cr: Int) {
        var lf = 0, crlf = 0, cr = 0
        var iterator = string.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()
        while let scalar = pending {
            if scalar == "\r" {
                let next = iterator.next()
                if next == "\n" {
                    crlf += 1
                    pending = iterator.next()
                } else {
                    cr += 1
                    pending = next
                }
            } else {
                if scalar == "\n" { lf += 1 }
                pending = iterator.next()
            }
        }
        return (lf, crlf, cr)
    }

    /// The dominant line ending, or `nil` for a document with no terminators.
    /// Ties break toward LF, matching macOS convention.
    public static func detect(in string: String) -> LineEnding? {
        let c = counts(in: string)
        let maximum = max(c.lf, c.crlf, c.cr)
        guard maximum > 0 else { return nil }
        if c.lf == maximum { return .lf }
        if c.crlf == maximum { return .crlf }
        return .cr
    }

    /// True when the document mixes terminators — Notepad++ warns about this.
    public static func isMixed(in string: String) -> Bool {
        let c = counts(in: string)
        return [c.lf, c.crlf, c.cr].filter { $0 > 0 }.count > 1
    }

    /// Rewrites every terminator to `target`, collapsing mixed input.
    public static func normalize(_ string: String, to target: LineEnding) -> String {
        var out = String()
        out.reserveCapacity(string.count)
        var iterator = string.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()
        while let scalar = pending {
            if scalar == "\r" {
                let next = iterator.next()
                out += target.rawValue
                pending = (next == "\n") ? iterator.next() : next
            } else if scalar == "\n" {
                out += target.rawValue
                pending = iterator.next()
            } else {
                out.unicodeScalars.append(scalar)
                pending = iterator.next()
            }
        }
        return out
    }
}
