import Foundation

/// A colour theme for the Style Configurator: one entry per token type plus the
/// editor chrome colours. Colours are stored as hex so themes are portable and
/// diffable, rather than as archived NSColor blobs.
public struct EditorTheme: Codable, Equatable, Sendable {
    public var name: String
    public var isDark: Bool
    /// Hex strings like "#RRGGBB", keyed by `TokenType.rawValue`.
    public var tokenColors: [String: String]
    public var background: String
    public var foreground: String
    public var currentLineBackground: String
    public var selectionBackground: String
    public var gutterForeground: String
    public var fontName: String?
    public var fontSize: Double?
    /// Token types rendered italic or bold.
    public var italicTokens: [String]
    public var boldTokens: [String]

    public init(
        name: String, isDark: Bool, tokenColors: [String: String],
        background: String, foreground: String,
        currentLineBackground: String, selectionBackground: String,
        gutterForeground: String,
        fontName: String? = nil, fontSize: Double? = nil,
        italicTokens: [String] = [TokenType.comment.rawValue, TokenType.commentLine.rawValue],
        boldTokens: [String] = []
    ) {
        self.name = name
        self.isDark = isDark
        self.tokenColors = tokenColors
        self.background = background
        self.foreground = foreground
        self.currentLineBackground = currentLineBackground
        self.selectionBackground = selectionBackground
        self.gutterForeground = gutterForeground
        self.fontName = fontName
        self.fontSize = fontSize
        self.italicTokens = italicTokens
        self.boldTokens = boldTokens
    }

    public func color(for token: TokenType) -> String? { tokenColors[token.rawValue] }

    /// The design's dark palette. The values are the design's own, so the
    /// editor and the window chrome are the same set of colours rather than
    /// two palettes that happen to sit next to each other.
    public static let defaultDark = EditorTheme(
        name: "Default Dark", isDark: true,
        tokenColors: [
            TokenType.comment.rawValue: "#7F8C98",
            TokenType.commentLine.rawValue: "#7F8C98",
            TokenType.string.rawValue: "#FF8170",
            TokenType.character.rawValue: "#FF8170",
            TokenType.number.rawValue: "#D0BF69",
            TokenType.keyword1.rawValue: "#FC5FA3",
            TokenType.keyword2.rawValue: "#6BDFFF",
            TokenType.keyword3.rawValue: "#67B7A4",
            TokenType.keyword4.rawValue: "#D9C97C",
            TokenType.preprocessor.rawValue: "#D9C97C",
            TokenType.operatorToken.rawValue: "#E3E3E6",
        ],
        background: "#1D1E20", foreground: "#E3E3E6",
        currentLineBackground: "#25272B", selectionBackground: "#2C4A73",
        gutterForeground: "#6C6D72"
    )

    /// The design's light palette.
    public static let defaultLight = EditorTheme(
        name: "Default Light", isDark: false,
        tokenColors: [
            TokenType.comment.rawValue: "#5D6C79",
            TokenType.commentLine.rawValue: "#5D6C79",
            TokenType.string.rawValue: "#C41A16",
            TokenType.character.rawValue: "#C41A16",
            TokenType.number.rawValue: "#1C00CF",
            TokenType.keyword1.rawValue: "#9B2393",
            TokenType.keyword2.rawValue: "#0F68A0",
            TokenType.keyword3.rawValue: "#326D74",
            TokenType.keyword4.rawValue: "#836C28",
            TokenType.preprocessor.rawValue: "#836C28",
            TokenType.operatorToken.rawValue: "#1F2024",
        ],
        background: "#FFFFFF", foreground: "#1F2024",
        currentLineBackground: "#F5F7FC", selectionBackground: "#B4D5FE",
        gutterForeground: "#B2B2B8"
    )

    public static let builtIn: [EditorTheme] = [.defaultDark, .defaultLight]

    /// The name that means "whatever appearance the Mac is in".
    public static let systemThemeName = "System"
}

/// Loads and saves user themes alongside the built-ins.
public final class ThemeStore {
    private let directory: URL
    public private(set) var userThemes: [EditorTheme] = []

    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    public var allThemes: [EditorTheme] { EditorTheme.builtIn + userThemes }

    public func theme(named name: String) -> EditorTheme? {
        allThemes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        userThemes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(EditorTheme.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }

    /// Saves a user theme. Built-in names are rejected so a shipped theme
    /// cannot be shadowed and then fail to reset.
    public enum ThemeError: Error, Equatable { case reservedName(String) }

    public func save(_ theme: EditorTheme) throws {
        guard !EditorTheme.builtIn.contains(where: {
            $0.name.caseInsensitiveCompare(theme.name) == .orderedSame
        }) else { throw ThemeError.reservedName(theme.name) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let safeName = theme.name.replacingOccurrences(of: "/", with: "-")
        try encoder.encode(theme).write(
            to: directory.appendingPathComponent("\(safeName).json"), options: .atomic
        )
        reload()
    }

    public func delete(named name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(safeName).json"))
        reload()
    }
}

/// Hex <-> component conversion, kept in Core so themes stay AppKit-free and
/// therefore testable without a window server.
public enum HexColor {
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        // Expand shorthand like #FFF.
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return (
            Double((number >> 16) & 0xFF) / 255.0,
            Double((number >> 8) & 0xFF) / 255.0,
            Double(number & 0xFF) / 255.0
        )
    }

    public static func string(red: Double, green: Double, blue: Double) -> String {
        func clamp(_ value: Double) -> Int { Int((min(max(0, value), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}
