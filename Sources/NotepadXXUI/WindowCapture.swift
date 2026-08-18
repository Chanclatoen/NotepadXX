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
        // Auto Layout may not have run yet, leaving every subview at zero size
        // and producing a blank image of an otherwise correct hierarchy.
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return false }

        // Render the backing layer rather than using cacheDisplay: modern
        // AppKit controls (NSButton and friends) are SwiftUI-hosted, and
        // cacheDisplay draws them as blank space, producing an image that
        // wrongly looks like a layout bug.
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        if let layer = view.layer, let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            layer.render(in: context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            view.cacheDisplay(in: bounds, to: rep)
        }

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
