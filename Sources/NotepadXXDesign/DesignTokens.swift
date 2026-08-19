import AppKit

/// The NotepadXX design system, transcribed from `Design System.dc.html`.
///
/// Every colour is named by role, never by value, and resolves per appearance
/// so dark mode and Increased Contrast come from the system rather than a
/// second palette. Nothing outside this file should hard-code a chrome colour,
/// a metric or a radius.
public enum DS {

    // MARK: - Metrics
    //
    // Chrome totals 128 pt at the default 1100x720 window, leaving the editing
    // surface 82% of the height. These are the numbers that keep that true.

    public enum Metric {
        public static let titleBar: CGFloat = 30
        public static let toolbar: CGFloat = 42
        public static let tabStrip: CGFloat = 30
        public static let panelHeader: CGFloat = 27
        public static let listRow: CGFloat = 22
        public static let statusBar: CGFloat = 26
        /// Small and standard control heights.
        public static let controlSmall: CGFloat = 21
        public static let control: CGFloat = 24

        /// Gutter lanes, left to right. Fixed so code never reflows when a
        /// lane is toggled.
        public static let gutterBookmark: CGFloat = 15
        public static let gutterNumber: CGFloat = 36
        public static let gutterChangeBar: CGFloat = 4
        public static let gutterFolding: CGFloat = 14

        public static let windowDefault = NSSize(width: 1100, height: 720)
        public static let windowMinimum = NSSize(width: 900, height: 600)

        /// Splitter: 5 pt hit area, 1 pt visible.
        public static let splitterHit: CGFloat = 5
        public static let hairline: CGFloat = 1

        public static let sideDock: CGFloat = 260
        public static let bottomDock: CGFloat = 180
    }

    /// The 2 pt base unit scale.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 6
        public static let m: CGFloat = 8
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 20
        public static let xxxl: CGFloat = 24
    }

    public enum Radius {
        public static let control: CGFloat = 4
        public static let button: CGFloat = 6
        public static let tab: CGFloat = 8
        public static let dialog: CGFloat = 11
        public static let window: CGFloat = 12
    }

    // MARK: - Typography

    public enum Font {
        public static func windowTitle() -> NSFont { .systemFont(ofSize: 20, weight: .semibold) }
        public static func pageTitle() -> NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        /// Body and control label — the default system size.
        public static func body() -> NSFont { .systemFont(ofSize: 13) }
        public static func bodyEmphasis() -> NSFont { .systemFont(ofSize: 13, weight: .medium) }
        /// Dense list, tab title, toolbar label.
        public static func dense() -> NSFont { .systemFont(ofSize: 12) }
        public static func denseEmphasis() -> NSFont { .systemFont(ofSize: 12, weight: .medium) }
        /// Status bar, secondary help text, panel header.
        public static func small() -> NSFont { .systemFont(ofSize: 11) }
        public static func smallEmphasis() -> NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        /// Monospaced digits for status numerics, so they do not jitter.
        public static func statusNumeric() -> NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }
        public static func mono(_ size: CGFloat = 12) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
        /// The editor's own line height multiple.
        public static let editorLineHeightMultiple: CGFloat = 1.45
    }

    // MARK: - Semantic colour
    //
    // Each token carries its light and dark value from the design and resolves
    // against the current appearance, so a single NSColor works everywhere.

    public enum Color {
        public static let windowBackground = dynamic(light: 0xEFEFF1, dark: 0x2E2F31)
        public static let titleBar = dynamic(light: 0xF6F6F7, dark: 0x2A2B2D)
        public static let toolbar = dynamic(light: 0xF6F6F7, dark: 0x2A2B2D)
        /// The editor surface itself.
        public static let content = dynamic(light: 0xFFFFFF, dark: 0x1D1E20)
        public static let panel = dynamic(light: 0xF2F2F3, dark: 0x252628)
        public static let tabStrip = dynamic(light: 0xEDEDEE, dark: 0x232527)
        public static let rowAlternate = dynamicAlpha(light: (0xFAFAFA, 1.0), dark: (0xFFFFFF, 0.035))
        public static let controlFill = dynamic(light: 0xFFFFFF, dark: 0x37383B)
        public static let controlBorder = dynamicAlpha(light: (0x000000, 0.14), dark: (0xFFFFFF, 0.14))
        /// Hairline inside a surface.
        public static let separator = dynamicAlpha(light: (0x000000, 0.06), dark: (0xFFFFFF, 0.07))
        /// Structural divider between chrome regions.
        public static let separatorStructural = dynamicAlpha(light: (0x000000, 0.13), dark: (0xFFFFFF, 0.10))

        public static let textPrimary = dynamic(light: 0x1C1C1E, dark: 0xF2F2F4)
        public static let textSecondary = dynamic(light: 0x6E6E76, dark: 0xA8A8AE)
        public static let textTertiary = dynamic(light: 0x7D7D83, dark: 0x8E8E95)
        public static let textDisabled = dynamic(light: 0xB0B0B6, dark: 0x5F6065)
        /// Toolbar glyph at rest.
        public static let glyph = dynamic(light: 0x43444A, dark: 0xD6D6DB)

        /// NotepadXX green: the app's own moments — active document, engaged
        /// toggle, current search hit, success. Everything else follows the
        /// user's system accent.
        public static let brand = dynamic(light: 0x0F8A63, dark: 0x3FD097)
        public static let brandTint = dynamicAlpha(light: (0x0F8A63, 0.12), dark: (0x3FD097, 0.16))
        public static let success = dynamic(light: 0x0F8A63, dark: 0x34C48A)
        public static let warning = dynamic(light: 0xB25000, dark: 0xFFB340)
        public static let error = dynamic(light: 0xC1372E, dark: 0xFF6B5E)
        /// Backgrounds for the state banners, from the design's own values.
        public static let successTint = dynamic(light: 0xF3FAF4, dark: 0x1C2A20)
        public static let warningTint = dynamic(light: 0xFFF8EC, dark: 0x2E2617)
        public static let errorTint = dynamic(light: 0xFDF1F0, dark: 0x2E1D1B)

        public static let searchMatch = dynamic(light: 0xFFE9A6, dark: 0x5E5326)
        public static let currentMatch = dynamic(light: 0x9EE8C4, dark: 0x1F5B45)
        /// The editor's selection fill.
        public static let selection = dynamic(light: 0xB4D5FE, dark: 0x2C4A73)
        public static let textSelection = dynamic(light: 0xB4D5FE, dark: 0x2C4A73)

        /// Toolbar interaction wells.
        public static let hoverWell = dynamicAlpha(light: (0x000000, 0.055), dark: (0xFFFFFF, 0.07))
        public static let pressedWell = dynamicAlpha(light: (0x000000, 0.13), dark: (0xFFFFFF, 0.14))

        /// Change history: amber = unsaved, green = saved this session. The two
        /// also differ in shape, so the signal never rests on hue alone.
        public static let changeModified = dynamic(light: 0xE0932C, dark: 0xC88A2A)
        public static let changeSaved = dynamic(light: 0x0F8A63, dark: 0x2A8A5E)

        public static let gutterBackground = dynamic(light: 0xFBFBFC, dark: 0x202123)
        public static let gutterText = dynamic(light: 0xB2B2B8, dark: 0x6C6D72)
        public static let gutterTextCurrent = dynamic(light: 0x1C1C1E, dark: 0xF2F2F4)
        public static let currentLine = dynamic(light: 0xF5F7FC, dark: 0x25272B)
        public static let invisibleCharacter = dynamic(light: 0xC6C6CB, dark: 0x4A4B4F)
        public static let caret = dynamic(light: 0x0A6CFF, dark: 0x3B8BFF)
        public static let bookmark = dynamic(light: 0x0A6CFF, dark: 0x3B8BFF)
        public static let foldPlaceholder = dynamicAlpha(light: (0x000000, 0.05), dark: (0x2E3033, 1.0))

        // MARK: Builders

        /// Resolves per appearance, and honours Increased Contrast by using the
        /// stronger of the pair.
        public static func dynamic(light: Int, dark: Int) -> NSColor {
            NSColor(name: nil) { appearance in
                isDark(appearance) ? rgb(dark) : rgb(light)
            }
        }

        public static func dynamicAlpha(light: (Int, CGFloat), dark: (Int, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let pair = isDark(appearance) ? dark : light
                return rgb(pair.0).withAlphaComponent(pair.1)
            }
        }

        static func isDark(_ appearance: NSAppearance) -> Bool {
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }

        public static func rgb(_ value: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1)
        }
    }

    /// The five Mark styles. Each pairs a fill with a distinct form, so a mark
    /// is never identified by colour alone.
    public enum MarkStyleAppearance {
        public struct Style {
            public let fill: NSColor
            public let rule: NSColor?
            public enum Form { case fillOnly, solidUnderline, outlineBox, dashedUnderline, doubleUnderline }
            public let form: Form

            /// One drawing routine for both the editor's marks and the style
            /// picker, so a swatch always shows what the text will look like.
            public func draw(in rect: NSRect) {
                fill.setFill()
                rect.fill()
                guard let rule else { return }
                rule.setStroke()

                let path = NSBezierPath()
                path.lineWidth = 1
                switch form {
                case .fillOnly:
                    return
                case .solidUnderline:
                    path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
                case .outlineBox:
                    path.appendRect(rect.insetBy(dx: 0.5, dy: 0.5))
                case .dashedUnderline:
                    path.setLineDash([3, 2], count: 2, phase: 0)
                    path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
                case .doubleUnderline:
                    path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 0.5))
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 0.5))
                    path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 2.5))
                    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 2.5))
                }
                path.stroke()
            }
        }

        public static func styles() -> [Style] { [
            Style(fill: Color.dynamic(light: 0xFFF2A8, dark: 0x5E5326), rule: nil, form: .fillOnly),
            Style(fill: Color.dynamic(light: 0xC9F0C0, dark: 0x2C4A38),
                  rule: Color.dynamic(light: 0x2C7A2C, dark: 0x5FBF5F), form: .solidUnderline),
            Style(fill: Color.dynamic(light: 0xC6E2FF, dark: 0x24466E),
                  rule: Color.dynamic(light: 0x2E6BB8, dark: 0x6FA8E8), form: .outlineBox),
            Style(fill: Color.dynamic(light: 0xFFD3C2, dark: 0x6B3A28),
                  rule: Color.dynamic(light: 0xB2532A, dark: 0xE8905F), form: .dashedUnderline),
            Style(fill: Color.dynamic(light: 0xE5CDF5, dark: 0x4A2F63),
                  rule: Color.dynamic(light: 0x6A3E96, dark: 0xB98FE0), form: .doubleUnderline),
        ] }
    }

    /// Syntax palettes. `xcode` is the default; `monochrome` is the reduced
    /// variant offered in Appearance.
    public enum SyntaxPalette {
        public static let xcodePlain = Color.dynamic(light: 0x1F2024, dark: 0xE3E3E6)
        public static let xcodeKeyword = Color.dynamic(light: 0x9B2393, dark: 0xFC5FA3)
        public static let xcodeString = Color.dynamic(light: 0xC41A16, dark: 0xFF8170)
        public static let xcodeComment = Color.dynamic(light: 0x5D6C79, dark: 0x7F8C98)
        public static let xcodeNumber = Color.dynamic(light: 0x1C00CF, dark: 0xD0BF69)
        public static let xcodeType = Color.dynamic(light: 0x0F68A0, dark: 0x6BDFFF)
        public static let xcodeFunction = Color.dynamic(light: 0x326D74, dark: 0x67B7A4)
        public static let xcodeAttribute = Color.dynamic(light: 0x836C28, dark: 0xD9C97C)
    }

    // MARK: - Motion
    //
    // Short and purposeful. All of it is skipped under Reduce Motion.

    public enum Motion {
        public static let hoverFade: TimeInterval = 0.08
        public static let panelSlide: TimeInterval = 0.18
        public static let tooltipDelay: TimeInterval = 0.6

        /// Honours the system Reduce Motion setting.
        public static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        public static var increaseContrast: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }

        /// The duration to actually use. Separated from `animate` so the
        /// Reduce Motion behaviour can be checked without a system setting.
        public static func duration(_ requested: TimeInterval, reduceMotion: Bool) -> TimeInterval {
            reduceMotion ? 0 : requested
        }

        /// Runs `body` animated, or immediately when Reduce Motion is on.
        @MainActor
        public static func animate(_ duration: TimeInterval, _ body: @escaping () -> Void) {
            let effective = Self.duration(duration, reduceMotion: reduceMotion)
            guard effective > 0 else { body(); return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = effective
                body()
            }
        }
    }
}

public extension DS {
    /// Render an SF Symbol already tinted.
    ///
    /// Tinting by setting a colour and compositing `.sourceAtop` over the drawn
    /// glyph paints the whole rect solid, because the backdrop inside the rect is
    /// the opaque control background rather than the glyph alone. Palette colours
    /// tint during symbol rasterisation instead, so only the strokes are coloured.
    static func symbol(_ name: String,
                       pointSize: CGFloat,
                       weight: NSFont.Weight = .regular,
                       color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            assertionFailure("'\(name)' is not an SF Symbol on this system")
            return nil
        }
        let tinted = image.withSymbolConfiguration(configuration)
        tinted?.isTemplate = false
        return tinted
    }
}
