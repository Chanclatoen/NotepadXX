import XCTest
import AppKit
@testable import NotepadXXDesign

/// The design system is the source of these values. A token that drifts from
/// the design is a token that stops meaning anything, so each is pinned to the
/// value the design specifies, in both appearances.
@MainActor
final class DesignTokenTests: XCTestCase {
    private func hex(_ colour: NSColor, appearance name: NSAppearance.Name) -> String {
        var result = ""
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            let resolved = colour.usingColorSpace(.sRGB) ?? colour
            result = String(format: "#%02X%02X%02X",
                            Int((resolved.redComponent * 255).rounded()),
                            Int((resolved.greenComponent * 255).rounded()),
                            Int((resolved.blueComponent * 255).rounded()))
        }
        return result
    }

    private func check(_ colour: NSColor, light: String, dark: String,
                       _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(hex(colour, appearance: .aqua), light, "\(name) in light", file: file, line: line)
        XCTAssertEqual(hex(colour, appearance: .darkAqua), dark, "\(name) in dark", file: file, line: line)
    }

    func testSurfaceTokensMatchTheDesign() {
        check(DS.Color.windowBackground, light: "#EFEFF1", dark: "#2E2F31", "window")
        check(DS.Color.titleBar, light: "#F6F6F7", dark: "#2A2B2D", "title bar")
        check(DS.Color.toolbar, light: "#F6F6F7", dark: "#2A2B2D", "toolbar")
        check(DS.Color.content, light: "#FFFFFF", dark: "#1D1E20", "content")
        check(DS.Color.panel, light: "#F2F2F3", dark: "#252628", "panel")
        check(DS.Color.tabStrip, light: "#EDEDEE", dark: "#232527", "tab strip")
    }

    func testTextTokensMatchTheDesign() {
        check(DS.Color.textPrimary, light: "#1C1C1E", dark: "#F2F2F4", "primary text")
        check(DS.Color.textSecondary, light: "#6E6E76", dark: "#A8A8AE", "secondary text")
        check(DS.Color.textTertiary, light: "#7D7D83", dark: "#8E8E95", "tertiary text")
        check(DS.Color.textDisabled, light: "#B0B0B6", dark: "#5F6065", "disabled text")
    }

    func testAccentAndSignalTokensMatchTheDesign() {
        check(DS.Color.brand, light: "#0F8A63", dark: "#3FD097", "brand")
        check(DS.Color.caret, light: "#0A6CFF", dark: "#3B8BFF", "caret")
        check(DS.Color.searchMatch, light: "#FFE9A6", dark: "#5E5326", "search match")
        check(DS.Color.currentMatch, light: "#9EE8C4", dark: "#1F5B45", "current match")
        check(DS.Color.selection, light: "#B4D5FE", dark: "#2C4A73", "selection")
        check(DS.Color.changeModified, light: "#E0932C", dark: "#C88A2A", "unsaved change bar")
        check(DS.Color.changeSaved, light: "#0F8A63", dark: "#2A8A5E", "saved change bar")
    }

    func testEditorTokensMatchTheDesign() {
        check(DS.Color.gutterBackground, light: "#FBFBFC", dark: "#202123", "gutter")
        check(DS.Color.gutterText, light: "#B2B2B8", dark: "#6C6D72", "gutter text")
        check(DS.Color.gutterTextCurrent, light: "#1C1C1E", dark: "#F2F2F4", "current gutter text")
        check(DS.Color.currentLine, light: "#F5F7FC", dark: "#25272B", "current line")
        check(DS.Color.invisibleCharacter, light: "#C6C6CB", dark: "#4A4B4F", "invisible characters")
    }

    func testSyntaxPaletteMatchesTheDesign() {
        check(DS.SyntaxPalette.xcodePlain, light: "#1F2024", dark: "#E3E3E6", "plain")
        check(DS.SyntaxPalette.xcodeKeyword, light: "#9B2393", dark: "#FC5FA3", "keyword")
        check(DS.SyntaxPalette.xcodeString, light: "#C41A16", dark: "#FF8170", "string")
        check(DS.SyntaxPalette.xcodeComment, light: "#5D6C79", dark: "#7F8C98", "comment")
        check(DS.SyntaxPalette.xcodeNumber, light: "#1C00CF", dark: "#D0BF69", "number")
        check(DS.SyntaxPalette.xcodeType, light: "#0F68A0", dark: "#6BDFFF", "type")
        check(DS.SyntaxPalette.xcodeFunction, light: "#326D74", dark: "#67B7A4", "function")
        check(DS.SyntaxPalette.xcodeAttribute, light: "#836C28", dark: "#D9C97C", "attribute")
    }

    /// Every surface must differ between the two appearances; a token that
    /// resolves to the same colour in both is one that was never made dynamic.
    func testEverySurfaceTokenActuallyChangesWithAppearance() {
        let tokens: [(String, NSColor)] = [
            ("window", DS.Color.windowBackground), ("toolbar", DS.Color.toolbar),
            ("content", DS.Color.content), ("panel", DS.Color.panel),
            ("tab strip", DS.Color.tabStrip), ("gutter", DS.Color.gutterBackground),
            ("primary text", DS.Color.textPrimary), ("brand", DS.Color.brand),
        ]
        for (name, colour) in tokens {
            XCTAssertNotEqual(hex(colour, appearance: .aqua), hex(colour, appearance: .darkAqua),
                              "\(name) is the same in both appearances")
        }
    }

    /// The metrics the design states outright.
    func testMetricsMatchTheDesign() {
        XCTAssertEqual(DS.Metric.toolbar, 42)
        XCTAssertEqual(DS.Metric.tabStrip, 30)
        XCTAssertEqual(DS.Metric.statusBar, 26)
        XCTAssertEqual(DS.Metric.panelHeader, 27)
        XCTAssertEqual(DS.Metric.control, 24)
        XCTAssertEqual(DS.Metric.gutterBookmark, 15)
        XCTAssertEqual(DS.Metric.gutterNumber, 36)
        XCTAssertEqual(DS.Metric.gutterChangeBar, 4)
        XCTAssertEqual(DS.Metric.gutterFolding, 14)
        XCTAssertEqual(DS.Metric.windowDefault, NSSize(width: 1100, height: 720))
        XCTAssertEqual(DS.Metric.windowMinimum, NSSize(width: 900, height: 600))
    }
}
