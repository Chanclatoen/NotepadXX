import AppKit
import CodeEditTextView

/// Renders whitespace, tabs and line endings as visible glyphs, matching
/// Notepad++'s View > Show Symbol submenu.
///
/// The engine asks this delegate per character, so each class of invisible can
/// be toggled independently rather than all-or-nothing.
public final class InvisibleCharacterRenderer: InvisibleCharactersDelegate {
    public var showSpaces = false
    public var showTabs = false
    public var showLineEndings = false
    public var color: NSColor = .tertiaryLabelColor
    public var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Bumped whenever an option changes so the engine drops its cached styles.
    private var generation = 0
    private var lastSeenGeneration = -1

    public init() {}

    public var showsAnything: Bool { showSpaces || showTabs || showLineEndings }

    public func optionsChanged() { generation += 1 }

    // UTF-16 code units the engine should call us about.
    public var triggerCharacters: Set<UInt16> {
        var set: Set<UInt16> = []
        if showSpaces { set.insert(0x20) }
        if showTabs { set.insert(0x09) }
        if showLineEndings { set.insert(0x0A); set.insert(0x0D) }
        return set
    }

    public func invisibleStyleShouldClearCache() -> Bool {
        guard lastSeenGeneration != generation else { return false }
        lastSeenGeneration = generation
        return true
    }

    public func invisibleStyle(
        for character: UInt16, at range: NSRange, lineRange: NSRange
    ) -> InvisibleCharacterStyle? {
        switch character {
        case 0x20 where showSpaces:
            // Middle dot, the conventional space marker.
            return .replace(replacementCharacter: "\u{00B7}", color: color, font: font)
        case 0x09 where showTabs:
            return .replace(replacementCharacter: "\u{2192}", color: color, font: font)
        case 0x0A where showLineEndings:
            return .replace(replacementCharacter: "\u{00B6}", color: color, font: font)
        case 0x0D where showLineEndings:
            return .replace(replacementCharacter: "\u{00A4}", color: color, font: font)
        default:
            return nil
        }
    }
}
