import AppKit

/// Notepad++-style tab strip. Dirty tabs are marked with a dot, and each tab
/// carries its own close button.
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    var onContextMenu: ((Int, NSPoint) -> Void)?

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
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

    func configure(
        titles: [String], dirtyFlags: [Bool], selected: Int,
        pinned: [Bool] = [], colours: [NSColor?] = []
    ) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let tab = TabItemView(
                title: title,
                isDirty: dirtyFlags.indices.contains(index) && dirtyFlags[index],
                isSelected: index == selected,
                isPinned: pinned.indices.contains(index) && pinned[index],
                colour: colours.indices.contains(index) ? colours[index] : nil
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

    init(title: String, isDirty: Bool, isSelected: Bool, isPinned: Bool = false, colour: NSColor? = nil) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (colour ?? (isSelected ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor)).cgColor

        let prefix = (isPinned ? "\u{1F4CC} " : "") + (isDirty ? "\u{25CF} " : "")
        let label = NSTextField(labelWithString: prefix + title)
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
