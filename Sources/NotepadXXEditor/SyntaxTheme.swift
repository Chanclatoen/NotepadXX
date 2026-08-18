import AppKit
import NotepadXXCore

/// Maps token types to text attributes. One entry per `TokenType`, so the
/// Style Configurator can eventually edit these directly.
public struct SyntaxTheme: Sendable {
    public var colors: [TokenType: NSColor]
    public var italicTokens: Set<TokenType>
    public var boldTokens: Set<TokenType>
    public var plainColor: NSColor
    public var backgroundColor: NSColor

    public init(
        colors: [TokenType: NSColor],
        italicTokens: Set<TokenType> = [.comment, .commentLine],
        boldTokens: Set<TokenType> = [],
        plainColor: NSColor = .labelColor,
        backgroundColor: NSColor = .textBackgroundColor
    ) {
        self.colors = colors
        self.italicTokens = italicTokens
        self.boldTokens = boldTokens
        self.plainColor = plainColor
        self.backgroundColor = backgroundColor
    }

    /// Follows the system appearance, so it reads correctly in light and dark.
    public static let system = SyntaxTheme(colors: [
        .comment: .systemGreen,
        .commentLine: .systemGreen,
        .string: .systemRed,
        .character: .systemRed,
        .number: .systemOrange,
        .keyword1: .systemBlue,
        .keyword2: .systemPurple,
        .keyword3: .systemTeal,
        .keyword4: .systemIndigo,
        .preprocessor: .systemBrown,
        .operatorToken: .secondaryLabelColor,
        .delimiter: .secondaryLabelColor,
    ])

    public func color(for token: TokenType) -> NSColor {
        colors[token] ?? plainColor
    }

    public func attributes(for token: TokenType, baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        var font = baseFont
        if italicTokens.contains(token) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        if boldTokens.contains(token) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        return [.foregroundColor: color(for: token), .font: font]
    }
}
