import XCTest
import AppKit
@testable import NotepadXXUI
import NotepadXXDesign

/// Screenshots are how the design work gets verified, so a capture that shifts
/// colour is not a cosmetic problem — it makes every visual check unreliable.
@MainActor
final class CaptureFidelityTests: XCTestCase {
    private final class SolidView: NSView {
        var fill: NSColor = .black
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            fill.setFill()
            bounds.fill()
        }
    }

    /// A fixed sRGB colour isolates the capture pipeline from token resolution.
    func testCaptureDoesNotShiftAFixedColour() throws {
        let fixed = NSColor(srgbRed: 15 / 255, green: 138 / 255, blue: 99 / 255, alpha: 1)
        let captured = try capture(fill: fixed, appearance: .aqua)
        XCTAssertLessThanOrEqual(delta(captured, fixed), 3,
                                 "capture shifted the colour: drew \(hex(fixed)), captured \(hex(captured))")
    }

    /// Tokens must resolve against the view being drawn, not an ambient appearance.
    func testTokensResolveAgainstTheDrawingAppearance() throws {
        let light = try capture(fill: DS.Color.brand, appearance: .aqua)
        XCTAssertEqual(hex(light), "#0F8A63", "light brand")
        let dark = try capture(fill: DS.Color.brand, appearance: .darkAqua)
        XCTAssertEqual(hex(dark), "#3FD097", "dark brand")
    }

    private func capture(fill: NSColor, appearance name: NSAppearance.Name) throws -> NSColor {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: name)
        let view = SolidView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        view.wantsLayer = true
        view.fill = fill
        window.contentView = view

        let path = NSTemporaryDirectory() + "npxx-capture-fidelity.png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(WindowCapture.writePNG(of: window, to: path))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        // Compare the stored components directly: the capture writes an sRGB
        // file, but `colorAt` returns them tagged generically, so converting
        // "to sRGB" would transform values that need no transform.
        return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    }

    private func delta(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let y = b.usingColorSpace(.sRGB) else { return 255 }
        return max(abs(a.redComponent - y.redComponent),
                   abs(a.greenComponent - y.greenComponent),
                   abs(a.blueComponent - y.blueComponent)) * 255
    }

    private func hex(_ colour: NSColor) -> String {
        String(format: "#%02X%02X%02X",
               Int((colour.redComponent * 255).rounded()),
               Int((colour.greenComponent * 255).rounded()),
               Int((colour.blueComponent * 255).rounded()))
    }
}
