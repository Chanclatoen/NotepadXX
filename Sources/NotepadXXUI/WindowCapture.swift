import AppKit

/// Renders a window's contents to a PNG.
///
/// The app captures itself through the view hierarchy rather than the display,
/// so this needs no Screen Recording permission — which makes it usable from a
/// headless CI run or an SSH session, where `screencapture` cannot work.
@MainActor
public enum WindowCapture {
    /// Captures a specific window, used to verify auxiliary windows such as
    /// Preferences that never appear in a main-window capture.
    @discardableResult
    public static func writePNG(ofWindowTitled title: String, to path: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.title == title }) else { return false }
        return writePNG(of: window, to: path)
    }

    @discardableResult
    public static func writePNG(of window: NSWindow, to path: String) -> Bool {
        guard let view = window.contentView else { return false }
        // Capture in sRGB end to end. The window's backing store is Display P3
        // here, and the layer keeps raw sRGB fills in a P3-tagged buffer, so a
        // capture converts a colour that was never converted going in. Pinning
        // the window's space removes the mismatch instead of compensating for it.
        let originalColorSpace = window.colorSpace
        window.colorSpace = .sRGB
        defer { window.colorSpace = originalColorSpace }

        // Auto Layout may not have run yet, leaving every subview at zero size
        // and producing a blank image of an otherwise correct hierarchy.
        view.layoutSubtreeIfNeeded()
        view.setNeedsDisplay(view.bounds)
        window.display()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return false }

        // Render into an explicitly sRGB context. `bitmapImageRepForCachingDisplay`
        // builds its bitmap in the display's space (Display P3 here), and the
        // layer's sRGB contents get copied in without conversion — which leaves
        // saturated colours visibly washed out in the PNG while the screen is
        // correct. Naming the space makes captured pixels comparable to tokens.
        let scale = window.backingScaleFactor
        let pixelsWide = Int((bounds.width * scale).rounded())
        let pixelsHigh = Int((bounds.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(
                data: nil, width: pixelsWide, height: pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        cgContext.scaleBy(x: scale, y: scale)

        // Layers render bottom-up; AppKit's view geometry is bottom-up too, so
        // no extra flip is needed here.
        let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if let layer = view.layer {
            // Modern AppKit controls (NSButton and friends) are SwiftUI-hosted,
            // and cacheDisplay draws them as blank space, producing an image
            // that wrongly looks like a layout bug.
            layer.render(in: cgContext)
        } else {
            view.displayIgnoringOpacity(bounds, in: context)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let image = cgContext.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = bounds.size

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
