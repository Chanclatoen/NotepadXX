import AppKit
import NotepadXXCore

/// Applies a theme to the window chrome as well as the text.
///
/// Notepad++'s toolbar, tab bar and status bar follow its theme. Leaving them
/// on the system appearance produced a light editor inside dark chrome, which
/// looked broken rather than themed.
public enum AppearanceTheme {
    /// Colours for the chrome derived from the editor theme.
    public struct Chrome {
        public let background: NSColor
        public let text: NSColor
        public let selectedTab: NSColor
        public let appearance: NSAppearance?
    }

    public static func chrome(for theme: EditorTheme?) -> Chrome {
        guard let theme else {
            return Chrome(background: .windowBackgroundColor, text: .labelColor,
                          selectedTab: .controlBackgroundColor, appearance: nil)
        }
        func colour(_ hex: String, fallback: NSColor) -> NSColor {
            guard let rgb = HexColor.components(hex) else { return fallback }
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        let background = colour(theme.background, fallback: .windowBackgroundColor)
        // Chrome sits slightly off the editor background so the panes read as
        // separate surfaces, the way Notepad++'s do.
        let chromeBackground = theme.isDark
            ? background.blended(withFraction: 0.12, of: .white) ?? background
            : background.blended(withFraction: 0.08, of: .black) ?? background

        return Chrome(
            background: chromeBackground,
            text: colour(theme.foreground, fallback: .labelColor),
            selectedTab: background,
            appearance: NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        )
    }
}
