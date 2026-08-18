import AppKit

/// Notepad++-style tab strip. Dirty tabs are marked with a dot, and each tab
/// carries its own close button.
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

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

    func configure(titles: [String], dirtyFlags: [Bool], selected: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let isDirty = dirtyFlags.indices.contains(index) && dirtyFlags[index]
            let tab = TabItemView(
                title: title,
                isDirty: isDirty,
                isSelected: index == selected
            )
            tab.onSelect = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            stack.addArrangedSubview(tab)
        }
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private let isSelected: Bool

    init(title: String, isDirty: Bool, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (isSelected ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor).cgColor

        let label = NSTextField(labelWithString: (isDirty ? "\u{25CF} " : "") + title)
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
    @objc private func closeClicked() { onClose?() }
}
