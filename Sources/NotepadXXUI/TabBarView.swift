import AppKit

/// Notepad++-style tab strip. Dirty tabs are marked with a dot, and each tab
/// carries its own close button.
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    var onContextMenu: ((Int, NSPoint) -> Void)?

    /// Tab bar layouts Notepad++ offers.
    enum Layout { case horizontal, multiLine, vertical }
    var layout: Layout = .horizontal

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Applies the chosen layout. Vertical and multi-line both stack tabs
    /// downwards; multi-line wraps, vertical is a single column.
    private func applyLayout() {
        switch layout {
        case .horizontal:
            stack.orientation = .horizontal
            stack.alignment = .centerY
        case .multiLine, .vertical:
            stack.orientation = .vertical
            stack.alignment = .leading
        }
    }

    /// Height the bar needs for the current layout and tab count.
    func requiredExtent(tabCount: Int, availableWidth: CGFloat) -> CGFloat {
        switch layout {
        case .horizontal:
            return 28
        case .vertical:
            return CGFloat(max(1, tabCount)) * 26 + 4
        case .multiLine:
            // Roughly 150pt per tab; wrap into rows that fit the width.
            let perRow = max(1, Int(availableWidth / 150))
            let rows = Int(ceil(Double(max(1, tabCount)) / Double(perRow)))
            return CGFloat(rows) * 26 + 4
        }
    }

    private var lastConfiguration: (titles: [String], dirty: [Bool], selected: Int,
                                    pinned: [Bool], colours: [NSColor?])?
    private var chromeBackground: NSColor = .windowBackgroundColor
    private var chromeSelected: NSColor = .controlBackgroundColor
    private var chromeText: NSColor = .labelColor

    func applyChrome(background: NSColor, selected: NSColor, text: NSColor) {
        chromeBackground = background
        chromeSelected = selected
        chromeText = text
        layer?.backgroundColor = background.cgColor
        // Rebuild so existing tabs pick up the new colours.
        if let last = lastConfiguration {
            configure(titles: last.titles, dirtyFlags: last.dirty, selected: last.selected,
                      pinned: last.pinned, colours: last.colours)
        }
        needsDisplay = true
    }

    func configure(
        titles: [String], dirtyFlags: [Bool], selected: Int,
        pinned: [Bool] = [], colours: [NSColor?] = []
    ) {
        lastConfiguration = (titles, dirtyFlags, selected, pinned, colours)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        applyLayout()
        for (index, title) in titles.enumerated() {
            let tab = TabItemView(
                title: title,
                isDirty: dirtyFlags.indices.contains(index) && dirtyFlags[index],
                isSelected: index == selected,
                isPinned: pinned.indices.contains(index) && pinned[index],
                colour: colours.indices.contains(index) ? colours[index] : nil,
                background: chromeBackground,
                selectedBackground: chromeSelected,
                textColour: chromeText
            )
            tab.onSelect = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            tab.onContextMenu = { [weak self] point in self?.onContextMenu?(index, point) }
            tab.onDragTo = { [weak self] point in
                guard let self else { return }
                // Destination is whichever tab sits under the drop point.
                let local = self.convert(point, from: nil)
                var destination = index
                for (candidate, view) in self.stack.arrangedSubviews.enumerated()
                where view.frame.contains(self.stack.convert(local, from: self)) {
                    destination = candidate
                }
                if destination != index { self.onReorder?(index, destination) }
            }
            stack.addArrangedSubview(tab)
        }
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: ((NSPoint) -> Void)?
    var onDragTo: ((NSPoint) -> Void)?
    private let isSelected: Bool

    init(title: String, isDirty: Bool, isSelected: Bool, isPinned: Bool = false, colour: NSColor? = nil,
         background: NSColor = .windowBackgroundColor,
         selectedBackground: NSColor = .controlBackgroundColor,
         textColour: NSColor = .labelColor) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (colour ?? (isSelected ? selectedBackground : background)).cgColor
        // The active tab is joined to the editor below it, as Notepad++'s is.
        layer?.cornerRadius = 3
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let prefix = (isPinned ? "\u{1F4CC} " : "") + (isDirty ? "\u{25CF} " : "")
        let label = NSTextField(labelWithString: prefix + title)
        label.textColor = textColour
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail

        let close = NSButton(title: "\u{2715}", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.font = .systemFont(ofSize: 9)

        for subview in [label, close] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func mouseUp(with event: NSEvent) { onDragTo?(event.locationInWindow) }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event.locationInWindow) }
    /// Middle-click closes a tab, as in Notepad++.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }
    @objc private func closeClicked() { onClose?() }
}
