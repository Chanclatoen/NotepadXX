import AppKit

/// Renders a window's contents to a PNG.
///
/// The app captures itself through the view hierarchy rather than the display,
/// so this needs no Screen Recording permission — which makes it usable from a
/// headless CI run or an SSH session, where `screencapture` cannot work.
@MainActor
public enum WindowCapture {
    @discardableResult
    public static func writePNG(of window: NSWindow, to path: String) -> Bool {
        guard let view = window.contentView else { return false }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }

        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
