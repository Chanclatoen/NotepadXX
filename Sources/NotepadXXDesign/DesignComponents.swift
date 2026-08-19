import AppKit

/// Reusable controls built to the design system's specification.
///
/// Each carries the five interaction states — normal, hover, pressed,
/// selected, disabled — and reports the right thing to VoiceOver. Controls are
/// deliberately container-less at rest: a glyph on the surface, with a well
/// fading in only on interaction.

/// A hairline divider that follows the appearance.
public final class DSSeparator: NSView {
    public enum Weight { case hairline, structural }
    private let weight: Weight

    public init(_ weight: Weight = .hairline, vertical: Bool = false) {
        self.weight = weight
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        if vertical {
            widthAnchor.constraint(equalToConstant: DS.Metric.hairline).isActive = true
        } else {
            heightAnchor.constraint(equalToConstant: DS.Metric.hairline).isActive = true
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func updateLayer() {
        layer?.backgroundColor = (weight == .hairline
            ? DS.Color.separator : DS.Color.separatorStructural).cgColor
    }

    public override var allowsVibrancy: Bool { false }
}

/// A toolbar glyph button.
///
/// No container, no bevel and no frame until you interact; a rounded well
/// fades in on hover and deepens on press. Sticky toggles take the NotepadXX
/// green tint and report their on/off state to VoiceOver.
public final class DSToolbarButton: NSButton {
    public enum Kind { case action, toggle }

    private let kind: Kind
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var trackingAreaRef: NSTrackingArea?

    public var isOn: Bool = false {
        didSet {
            needsDisplay = true
            updateAccessibilityValue()
        }
    }

    private let symbolName: String

    public init(symbol: String, label: String, kind: Kind = .action,
                target: AnyObject?, action: Selector?) {
        self.kind = kind
        self.symbolName = symbol
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        title = ""
        wantsLayer = true

        image = DS.symbol(symbol, pointSize: 15, color: DS.Color.glyph)
        setAccessibilityLabel(label)
        toolTip = label
        self.target = target
        self.action = action

        setAccessibilityLabel(label)
        setAccessibilityRole(kind == .toggle ? .checkBox : .button)
        updateAccessibilityValue()

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: DS.Metric.control),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateAccessibilityValue() {
        guard kind == .toggle else { return }
        // Announce on/off rather than leaving state to colour alone.
        setAccessibilityValue(isOn ? 1 : 0)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true }
    public override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    public override func mouseDown(with event: NSEvent) {
        pressing = true
        super.mouseDown(with: event)
        pressing = false
    }

    public override func draw(_ dirtyRect: NSRect) {
        let well = bounds.insetBy(dx: 1, dy: 0)
        let path = NSBezierPath(roundedRect: well, xRadius: DS.Radius.button, yRadius: DS.Radius.button)

        if !isEnabled {
            // No hover well when disabled; the glyph alone carries the state.
        } else if pressing {
            DS.Color.pressedWell.setFill(); path.fill()
        } else if isOn {
            DS.Color.brandTint.setFill(); path.fill()
        } else if hovering {
            DS.Color.hoverWell.setFill(); path.fill()
        }

        let tint: NSColor
        if !isEnabled { tint = DS.Color.textDisabled }
        else if isOn { tint = DS.Color.brand }
        else { tint = DS.Color.glyph }

        guard let glyph = DS.symbol(symbolName, pointSize: 15, color: tint) else { return }
        let size = glyph.size
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        glyph.draw(in: NSRect(origin: origin, size: size), from: .zero,
                   operation: .sourceOver, fraction: isEnabled ? 1.0 : 0.35,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    /// Draw a visible focus ring for Full Keyboard Access.
    public override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 0) }
    public override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0),
                     xRadius: DS.Radius.button, yRadius: DS.Radius.button).fill()
    }
    public override var canBecomeKeyView: Bool { true }
    public override var acceptsFirstResponder: Bool { isEnabled }
}

/// The header strip on a docked panel: 27 pt, sentence case, with its own
/// close and float affordances. Never uppercase — the design refuses it.
public final class DSPanelHeader: NSView {
    public var onClose: (() -> Void)?
    public var onFloat: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")

    public init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: DS.Metric.panelHeader).isActive = true

        titleLabel.font = DS.Font.smallEmphasis()
        titleLabel.textColor = DS.Color.textSecondary
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityRole(.staticText)

        let float = DSToolbarButton(symbol: "macwindow", label: "Float Panel",
                                    target: self, action: #selector(floatTapped))
        let close = DSToolbarButton(symbol: "xmark", label: "Close Panel",
                                    target: self, action: #selector(closeTapped))
        for button in [float, close] {
            button.widthAnchor.constraint(equalToConstant: 20).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        }

        let stack = NSStackView(views: [titleLabel, NSView(), float, close])
        stack.orientation = .horizontal
        stack.spacing = DS.Space.xs
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let rule = DSSeparator(.hairline)
        addSubview(rule)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.xs),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    public override func updateLayer() {
        layer?.backgroundColor = DS.Color.panel.cgColor
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func floatTapped() { onFloat?() }
}

/// A message shown where a panel or list has nothing to show. The design calls
/// for a glyph, a line of explanation and, where there is one, the action that
/// would fill it.
public final class DSEmptyState: NSView {
    public init(symbol: String, title: String, message: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
        let glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage())
        glyph.contentTintColor = DS.Color.textTertiary

        let titleField = NSTextField(labelWithString: title)
        titleField.font = DS.Font.bodyEmphasis()
        titleField.textColor = DS.Color.textSecondary
        titleField.alignment = .center

        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.font = DS.Font.small()
        messageField.textColor = DS.Color.textTertiary
        messageField.alignment = .center
        messageField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [glyph, titleField, messageField]
        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(actionTapped))
            button.bezelStyle = .rounded
            button.controlSize = .small
            views.append(button)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = DS.Space.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: DS.Space.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Space.xl),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(title). \(message)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private let action: (() -> Void)?
    @objc private func actionTapped() { action?() }
}

/// A status-bar segment: a label, optional value, and an optional chevron
/// marking it as a menu. Segments are divided by hairlines, never boxes.
public final class DSStatusSegment: NSView {
    public var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }

    public init(accessibilityLabel: String, showsMenu: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = DS.Font.small()
        label.textColor = DS.Color.textPrimary
        label.lineBreakMode = .byTruncatingTail

        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down",
                                accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular))
        chevron.contentTintColor = DS.Color.textTertiary
        chevron.isHidden = !showsMenu

        let stack = NSStackView(views: [label, chevron])
        stack.orientation = .horizontal
        stack.spacing = DS.Space.xs
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let rule = DSSeparator(.hairline, vertical: true)
        addSubview(rule)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Space.m),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.s),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.s),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(showsMenu ? .popUpButton : .staticText)
        setAccessibilityLabel(accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            setAccessibilityValue(newValue)
        }
    }

    public var textColor: NSColor {
        get { label.textColor ?? DS.Color.textPrimary }
        set { label.textColor = newValue }
    }

    public func setFont(_ font: NSFont) { label.font = font }

    public func hideTrailingSeparator() {
        subviews.compactMap { $0 as? DSSeparator }.forEach { $0.isHidden = true }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard onClick != nil else { return }
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func mouseEntered(with event: NSEvent) { hovering = onClick != nil }
    public override func mouseExited(with event: NSEvent) { hovering = false }
    public override func mouseDown(with event: NSEvent) { onClick?() }

    public override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        DS.Color.hoverWell.setFill()
        bounds.fill()
    }
}
