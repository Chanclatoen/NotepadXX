import AppKit

/// The 42 pt toolbar.
///
/// Commands sit in logical groups separated by hairlines, in the order the
/// design specifies. When the window narrows, whole groups move into an
/// overflow menu from the right rather than the strip clipping or scrolling.
@MainActor
public final class DSToolbar: NSView {
    public struct Item {
        public let symbol: String
        public let label: String
        public let selector: Selector
        public let isToggle: Bool
        public let shortcut: String?

        public init(symbol: String, label: String, selector: Selector,
                    isToggle: Bool = false, shortcut: String? = nil) {
            self.symbol = symbol
            self.label = label
            self.selector = selector
            self.isToggle = isToggle
            self.shortcut = shortcut
        }
    }

    public var commandTarget: AnyObject?
    /// Labels of toggles currently on.
    public var activeToggles: Set<String> = [] { didSet { refreshToggleState() } }
    /// Labels of commands currently unavailable.
    public var disabledCommands: Set<String> = [] { didSet { refreshEnabledState() } }

    private var groups: [[Item]] = []
    private var buttons: [String: DSToolbarButton] = [:]
    private var groupViews: [NSStackView] = []
    private var separators: [DSSeparator] = []
    private let overflowButton = NSButton()
    private var visibleGroupCount = 0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: DS.Metric.toolbar).isActive = true

        overflowButton.isBordered = false
        overflowButton.imagePosition = .imageOnly
        overflowButton.image = NSImage(systemSymbolName: "chevron.right.2",
                                       accessibilityDescription: "More toolbar commands")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        overflowButton.target = self
        overflowButton.action = #selector(showOverflow)
        overflowButton.toolTip = "More commands"
        overflowButton.setAccessibilityLabel("More toolbar commands")
        overflowButton.isHidden = true
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overflowButton)

        let rule = DSSeparator(.structural)
        addSubview(rule)
        NSLayoutConstraint.activate([
            overflowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
            overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            overflowButton.widthAnchor.constraint(equalToConstant: 24),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Toolbar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func updateLayer() {
        layer?.backgroundColor = DS.Color.toolbar.cgColor
    }

    public func configure(groups: [[Item]]) {
        self.groups = groups
        groupViews.forEach { $0.removeFromSuperview() }
        separators.forEach { $0.removeFromSuperview() }
        groupViews = []
        separators = []
        buttons = [:]

        for (index, group) in groups.enumerated() {
            if index > 0 {
                let rule = DSSeparator(.hairline, vertical: true)
                addSubview(rule)
                separators.append(rule)
            }
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = DS.Space.xxs
            stack.translatesAutoresizingMaskIntoConstraints = false
            for item in group {
                let button = DSToolbarButton(symbol: item.symbol, label: item.label,
                                             kind: item.isToggle ? .toggle : .action,
                                             target: commandTarget, action: item.selector)
                buttons[item.label] = button
                stack.addArrangedSubview(button)
            }
            addSubview(stack)
            groupViews.append(stack)
        }
        needsLayout = true
    }

    /// Rebinds every button to the command target, used once the window
    /// controller exists.
    public func bind(to target: AnyObject) {
        commandTarget = target
        for group in groups {
            for item in group { buttons[item.label]?.target = target }
        }
    }

    private func refreshToggleState() {
        for group in groups {
            for item in group where item.isToggle {
                buttons[item.label]?.isOn = activeToggles.contains(item.label)
            }
        }
    }

    private func refreshEnabledState() {
        for (label, button) in buttons {
            button.isEnabled = !disabledCommands.contains(label)
        }
    }

    /// Lays groups left to right, hiding whole groups that do not fit and
    /// moving them into the overflow menu.
    public override func layout() {
        super.layout()
        let leading = DS.Space.s
        let overflowReserve: CGFloat = 34
        var x = leading
        var shown = 0

        for (index, stack) in groupViews.enumerated() {
            let width = stack.fittingSize.width
            let separatorWidth: CGFloat = index > 0 ? 9 : 0
            let needed = x + separatorWidth + width + overflowReserve

            if needed > bounds.width && index > 0 {
                break
            }
            if index > 0, separators.indices.contains(index - 1) {
                let rule = separators[index - 1]
                rule.isHidden = false
                rule.frame = NSRect(x: x + 4, y: 11, width: 1, height: DS.Metric.toolbar - 22)
                x += separatorWidth
            }
            stack.isHidden = false
            stack.frame = NSRect(x: x, y: (DS.Metric.toolbar - DS.Metric.control) / 2 - 1,
                                 width: width, height: DS.Metric.control)
            x += width
            shown = index + 1
        }

        for index in shown..<groupViews.count {
            groupViews[index].isHidden = true
            if index > 0, separators.indices.contains(index - 1) {
                separators[index - 1].isHidden = true
            }
        }
        visibleGroupCount = shown
        overflowButton.isHidden = shown >= groups.count
    }

    /// The commands currently hidden, exposed for tests and the menu.
    public var overflowedItems: [Item] {
        guard visibleGroupCount < groups.count else { return [] }
        return groups[visibleGroupCount...].flatMap { $0 }
    }

    @objc private func showOverflow() {
        let menu = NSMenu()
        for item in overflowedItems {
            let entry = menu.addItem(withTitle: item.label, action: item.selector, keyEquivalent: "")
            entry.target = commandTarget
            entry.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            if item.isToggle { entry.state = activeToggles.contains(item.label) ? .on : .off }
            entry.isEnabled = !disabledCommands.contains(item.label)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: overflowButton.frame.minX, y: overflowButton.frame.maxY),
                   in: self)
    }
}
