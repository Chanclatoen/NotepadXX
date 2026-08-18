import Foundation

/// A text encoding plus whether the file carries a byte-order mark.
///
/// Notepad++ treats "UTF-8" and "UTF-8-BOM" as distinct menu entries, so the BOM
/// flag is part of the document's identity rather than a save-time option.
public struct FileEncoding: Equatable, Sendable {
    public var encoding: String.Encoding
    public var hasBOM: Bool

    public init(_ encoding: String.Encoding, hasBOM: Bool = false) {
        self.encoding = encoding
        self.hasBOM = hasBOM
    }

    public static let utf8 = FileEncoding(.utf8)
    public static let utf8BOM = FileEncoding(.utf8, hasBOM: true)
    public static let utf16LE = FileEncoding(.utf16LittleEndian, hasBOM: true)
    public static let utf16BE = FileEncoding(.utf16BigEndian, hasBOM: true)
    /// Notepad++ labels the system legacy codepage "ANSI". macOS has no ambient
    /// codepage, so we map it to Windows-1252, the overwhelmingly common case.
    public static let ansi = FileEncoding(.windowsCP1252)

    public var displayName: String {
        switch (encoding, hasBOM) {
        case (.utf8, false): return "UTF-8"
        case (.utf8, true): return "UTF-8-BOM"
        case (.utf16LittleEndian, _): return "UCS-2 LE BOM"
        case (.utf16BigEndian, _): return "UCS-2 BE BOM"
        case (.windowsCP1252, _): return "ANSI"
        default: return String(describing: encoding)
        }
    }

    /// The bytes that must prefix the file on save, if any.
    public var bomBytes: [UInt8] {
        guard hasBOM else { return [] }
        switch encoding {
        case .utf8: return [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: return [0xFF, 0xFE]
        case .utf16BigEndian: return [0xFE, 0xFF]
        default: return []
        }
    }
}

public enum EncodingDetector {
    /// Detects encoding from a BOM when present, then falls back to a UTF-8
    /// validity check, then to ANSI. This mirrors Notepad++'s precedence: a BOM
    /// is authoritative and is never second-guessed.
    public static func detect(data: Data) -> FileEncoding {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8BOM }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LE }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BE }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        return .ansi
    }

    /// Decodes `data` as `encoding`, stripping the BOM if one is present.
    public static func decode(data: Data, as encoding: FileEncoding) -> String? {
        var payload = data
        let bom = encoding.bomBytes
        if !bom.isEmpty && payload.starts(with: bom) {
            payload = payload.dropFirst(bom.count)
        }
        return String(data: payload, encoding: encoding.encoding)
    }

    /// Encodes `string` as `encoding`, prefixing a BOM when the encoding wants one.
    public static func encode(string: String, as encoding: FileEncoding) -> Data? {
        guard let body = string.data(using: encoding.encoding) else { return nil }
        return Data(encoding.bomBytes) + body
    }
}
