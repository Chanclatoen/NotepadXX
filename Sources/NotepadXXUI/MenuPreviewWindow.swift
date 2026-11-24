import AppKit

/// A window listing one top-level menu with its submenus open, for
/// `--screenshot` runs: a window capture cannot see a real open menu.
@MainActor
enum MenuPreviewWindow {
    static func show(menu title: String) {
        guard let menu = MainMenu.build().items.first(where: { $0.title == title })?.submenu else { return }
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 3
        rows.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        func add(_ menu: NSMenu, depth: Int) {
            for item in menu.items {
                if item.isSeparatorItem {
                    let line = NSBox()
                    line.boxType = .separator
                    line.widthAnchor.constraint(equalToConstant: 420).isActive = true
                    rows.addArrangedSubview(line)
                    continue
                }
                let row = NSTextField(labelWithString: shortcut(of: item).isEmpty
                    ? item.title : "\(item.title)    \(shortcut(of: item))")
                row.font = .systemFont(ofSize: 13, weight: item.submenu == nil ? .regular : .semibold)
                row.textColor = item.action == nil && item.submenu == nil ? .secondaryLabelColor : .labelColor
                let wrapper = NSStackView(views: [NSView(), row])
                wrapper.views[0].widthAnchor.constraint(equalToConstant: CGFloat(depth) * 18).isActive = true
                rows.addArrangedSubview(wrapper)
                if let sub = item.submenu { add(sub, depth: depth + 1) }
            }
        }
        add(menu, depth: 0)

        let size = rows.fittingSize
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(460, size.width), height: size.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Menu: \(title)"
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: max(460, size.width), height: size.height)))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rows.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: container.topAnchor),
            rows.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        ])
        window.contentView = container
        window.center()
        window.orderFrontRegardless()
        // The window is retained by the application's window list while it is shown.
        window.isReleasedWhenClosed = false
    }

    private static func shortcut(of item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let flags = item.keyEquivalentModifierMask
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + item.keyEquivalent.uppercased()
    }
}
