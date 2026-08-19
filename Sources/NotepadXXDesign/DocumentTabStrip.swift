import AppKit

/// One document's presentation in the tab strip.
public struct DSTabItem: Equatable {
    public var title: String
    public var isActive: Bool
    public var isDirty: Bool
    public var isPinned: Bool
    public var isReadOnly: Bool
    public var showsCloseButton: Bool
    /// Per-tab colour tag, drawn as a 2 pt leading bar — never a full tint.
    public var accent: NSColor?
    public var inSecondPane: Bool
    public var toolTip: String?

    public init(title: String, isActive: Bool = false, isDirty: Bool = false,
                isPinned: Bool = false, isReadOnly: Bool = false,
                showsCloseButton: Bool = true, accent: NSColor? = nil,
                inSecondPane: Bool = false, toolTip: String? = nil) {
        self.title = title
        self.isActive = isActive
        self.isDirty = isDirty
        self.isPinned = isPinned
        self.isReadOnly = isReadOnly
        self.showsCloseButton = showsCloseButton
        self.accent = accent
        self.inSecondPane = inSecondPane
        self.toolTip = toolTip
    }
}

/// The document tab strip in its three genuine layouts.
///
/// Horizontal scrolls, wrapped grows downward in real rows, and vertical is a
/// 190 pt side rail — not a tall top strip. All three share one data source, so
/// a document keeps its pin, colour, dirty flag and caret across a layout
/// change.
@MainActor
public final class DocumentTabStrip: NSView {
    public enum Layout: String, CaseIterable { case horizontal, wrapped, vertical }

    public var tabLayout: Layout = .horizontal {
        didSet {
            guard tabLayout != oldValue else { return }
            rebuild()
        }
    }

    public var onSelect: ((Int) -> Void)?
    public var onClose: ((Int) -> Void)?
    public var onReorder: ((Int, Int) -> Void)?
    public var onContextMenu: ((Int, NSPoint) -> Void)?
    /// Called when the strip's required extent changes, so the window can
    /// resize the editor around it.
    public var onExtentChanged: ((CGFloat) -> Void)?

    private(set) var items: [DSTabItem] = []
    private let scrollView = NSScrollView()
    private var scrollLeading: NSLayoutConstraint!
    private var scrollTrailing: NSLayoutConstraint!
    private let contentView = FlippedContainer()
    private var tabViews: [DSTabView] = []

    /// Scroll affordances, shown only when the strip actually overflows: a
    /// chevron at each edge and a button that lists every document. Without
    /// them a scrolling strip gives no clue that there is more to the side.
    private let scrollLeftButton = DSToolbarButton(symbol: "chevron.left", label: "Scroll tabs left",
                                                   target: nil, action: nil)
    private let scrollRightButton = DSToolbarButton(symbol: "chevron.right", label: "Scroll tabs right",
                                                    target: nil, action: nil)
    private let listButton = NSButton()

    /// Called when the list button is pressed, with the button to anchor a menu.
    public var onShowTabList: ((NSView) -> Void)?

    public static let rowHeight = DS.Metric.tabStrip
    public static let railWidth: CGFloat = 190
    public static let railRowHeight: CGFloat = 24
    /// Fixed sizes for the scroll affordances. Reading their frames while the
    /// strip is being laid out gives zero, which lets a tab slide underneath.
    static let chevronWidth: CGFloat = 22
    static let listButtonWidth: CGFloat = 52

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // A real scroller: horizontal overflow scrolls rather than clipping.
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = contentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        // The scroll view is inset from the edges when the affordances appear.
        // Content insets alone only shift the content; the tabs still draw
        // under the chevrons.
        scrollLeading = scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
        scrollTrailing = scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollLeading,
            scrollTrailing,
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        scrollLeftButton.target = self
        scrollLeftButton.action = #selector(scrollLeft)
        scrollRightButton.target = self
        scrollRightButton.action = #selector(scrollRight)

        listButton.bezelStyle = .inline
        listButton.font = DS.Font.small()
        listButton.target = self
        listButton.action = #selector(showList)
        listButton.setAccessibilityLabel("Show all documents")

        for control in [scrollLeftButton as NSView, listButton, scrollRightButton] {
            control.isHidden = true
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
        }
        NSLayoutConstraint.activate([
            listButton.widthAnchor.constraint(equalToConstant: Self.listButtonWidth),
            scrollLeftButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollLeftButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrollLeftButton.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
            scrollRightButton.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
            scrollRightButton.trailingAnchor.constraint(equalTo: listButton.leadingAnchor),
            scrollRightButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            listButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.xs),
            listButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Open documents")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func updateLayer() {
        layer?.backgroundColor = (tabLayout == .vertical ? DS.Color.panel : DS.Color.tabStrip).cgColor
    }

    public func configure(items: [DSTabItem]) {
        self.items = items
        rebuild()
    }

    /// The extent the strip needs: a height for horizontal and wrapped, a width
    /// for the vertical rail.
    public func requiredExtent(forWidth available: CGFloat) -> CGFloat {
        switch tabLayout {
        case .horizontal:
            return Self.rowHeight
        case .wrapped:
            return CGFloat(max(1, rowCount(forWidth: available))) * Self.rowHeight
        case .vertical:
            return Self.railWidth
        }
    }

    /// How many wrapped rows the current tabs need at this width.
    public func rowCount(forWidth available: CGFloat) -> Int {
        guard !items.isEmpty else { return 1 }
        var rows = 1
        var x: CGFloat = 0
        for item in items {
            let width = Self.width(for: item)
            if x > 0 && x + width > available {
                rows += 1
                x = 0
            }
            x += width
        }
        return rows
    }

    static func width(for item: DSTabItem) -> CGFloat {
        let titleWidth = (item.title as NSString)
            .size(withAttributes: [.font: DS.Font.dense()]).width
        var width = titleWidth + 24                      // padding
        if item.isPinned || item.isReadOnly { width += 16 }
        if item.isDirty { width += 12 }
        if item.showsCloseButton { width += 18 }
        return min(max(width, 84), 220)
    }

    private func rebuild() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = items.enumerated().map { index, item in
            let view = DSTabView(item: item, vertical: tabLayout == .vertical)
            view.onSelect = { [weak self] in self?.onSelect?(index) }
            view.onClose = { [weak self] in self?.onClose?(index) }
            view.onContextMenu = { [weak self] point in self?.onContextMenu?(index, point) }
            view.onDragTo = { [weak self] point in
                guard let self, let target = self.indexOfTab(at: point) , target != index else { return }
                self.onReorder?(index, target)
            }
            contentView.addSubview(view)
            return view
        }
        needsLayout = true
        needsDisplay = true
    }

    private func indexOfTab(at pointInWindow: NSPoint) -> Int? {
        let local = contentView.convert(pointInWindow, from: nil)
        return tabViews.firstIndex { $0.frame.contains(local) }
    }

    public override func layout() {
        super.layout()
        switch tabLayout {
        case .horizontal: layoutScrolling()
        case .wrapped: layoutRows()
        case .vertical: layoutRail()
        }
    }

    /// Horizontal: one row, overflowing to the right and genuinely scrollable.
    private func layoutScrolling() {
        scrollView.hasHorizontalScroller = false
        var x: CGFloat = 0
        for (view, item) in zip(tabViews, items) {
            let width = Self.width(for: item)
            view.frame = NSRect(x: x, y: 0, width: width, height: Self.rowHeight)
            x += width
        }
        contentView.frame = NSRect(x: 0, y: 0, width: max(x, bounds.width), height: Self.rowHeight)
        scrollView.contentView.scroll(to: NSPoint(x: min(scrollView.contentView.bounds.origin.x,
                                                        max(0, x - bounds.width)), y: 0))
        updateScrollAffordances(contentWidth: x)
        scrollToActive()
    }

    /// Shows the chevrons and the "n / total" button only when the tabs do not
    /// all fit, and insets the scroll view so they never cover a tab.
    private func updateScrollAffordances(contentWidth: CGFloat) {
        let overflows = tabLayout == .horizontal && contentWidth > bounds.width
        isScrolling = overflows
        listButton.title = "\(activeIndexInItems + 1) / \(items.count)"
        for control in [scrollLeftButton as NSView, listButton, scrollRightButton] {
            control.isHidden = !overflows
        }
        let leading = overflows ? Self.chevronWidth : 0
        let trailing = overflows ? Self.chevronWidth + Self.listButtonWidth : 0
        if scrollLeading.constant != leading || scrollTrailing.constant != -trailing {
            scrollLeading.constant = leading
            scrollTrailing.constant = -trailing
            needsLayout = true
        }
    }

    /// Whether the strip is currently in scroll mode.
    public private(set) var isScrolling = false

    private var activeIndexInItems: Int {
        items.firstIndex(where: { $0.isActive }) ?? 0
    }

    @objc private func scrollLeft() { scrollBy(-bounds.width / 2) }
    @objc private func scrollRight() { scrollBy(bounds.width / 2) }

    private func scrollBy(_ delta: CGFloat) {
        let maximum = max(0, contentView.frame.width - bounds.width)
        let target = min(max(0, scrollView.contentView.bounds.origin.x + delta), maximum)
        scrollView.contentView.scroll(to: NSPoint(x: target, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func showList() { onShowTabList?(listButton) }

    /// Wrapped: genuine rows. The strip grows downward and the editor shrinks;
    /// a tab never jumps rows on activation, only on reorder.
    private func layoutRows() {
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (view, item) in zip(tabViews, items) {
            let width = Self.width(for: item)
            if x > 0 && x + width > bounds.width {
                x = 0
                y += Self.rowHeight
            }
            view.frame = NSRect(x: x, y: y, width: width, height: Self.rowHeight)
            x += width
        }
        let height = y + Self.rowHeight
        contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        onExtentChanged?(height)
    }

    /// Vertical: a 190 pt side rail of full-width rows, grouped with pinned
    /// documents first.
    private func layoutRail() {
        var y: CGFloat = 0
        for (view, _) in zip(tabViews, items) {
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: Self.railRowHeight)
            y += Self.railRowHeight
        }
        contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(y, bounds.height))
        scrollView.hasVerticalScroller = y > bounds.height
    }

    /// Keeps the active tab on screen when the strip scrolls.
    private func scrollToActive() {
        guard tabLayout == .horizontal,
              let index = items.firstIndex(where: { $0.isActive }),
              tabViews.indices.contains(index) else { return }
        let frame = tabViews[index].frame
        let visible = scrollView.contentView.bounds
        if frame.minX < visible.minX {
            scrollView.contentView.scroll(to: NSPoint(x: frame.minX, y: 0))
        } else if frame.maxX > visible.maxX {
            scrollView.contentView.scroll(to: NSPoint(x: frame.maxX - visible.width, y: 0))
        }
    }
}

/// A flipped container so tabs lay out from the top-left in every mode.
final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// One tab. Active tabs carry a 2 pt brand-green top edge (a leading edge in
/// the rail); colour tags are a 2 pt bar, never a wash over the whole tab.
@MainActor
final class DSTabView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: ((NSPoint) -> Void)?
    var onDragTo: ((NSPoint) -> Void)?

    private let item: DSTabItem
    private let vertical: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingAreaRef: NSTrackingArea?
    private var closeButton: DSToolbarButton?

    init(item: DSTabItem, vertical: Bool) {
        self.item = item
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(item.title)
        // State is announced, never left to colour alone.
        var described: [String] = []
        if item.isDirty { described.append("unsaved changes") }
        if item.isPinned { described.append("pinned") }
        if item.isReadOnly { described.append("read only") }
        setAccessibilityHelp(described.joined(separator: ", "))
        setAccessibilityValue(item.isActive ? 1 : 0)
        toolTip = item.toolTip ?? item.title

        if item.showsCloseButton {
            let button = DSToolbarButton(symbol: "xmark", label: "Close \(item.title)",
                                         target: self, action: #selector(closeTapped))
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 16),
                button.heightAnchor.constraint(equalToConstant: 16),
            ])
            closeButton = button
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func mouseUp(with event: NSEvent) { onDragTo?(event.locationInWindow) }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event.locationInWindow) }
    /// Middle-click closes, as in Notepad++.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }
    @objc private func closeTapped() { onClose?() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Surface
        if item.isActive {
            DS.Color.content.setFill()
        } else if hovering {
            DS.Color.hoverWell.setFill()
        } else {
            NSColor.clear.setFill()
        }
        bounds.fill()

        // Active edge: top in a horizontal strip, leading edge in the rail.
        if item.isActive {
            DS.Color.brand.setFill()
            if vertical {
                NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
            } else {
                NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
            }
        }

        // Colour tag: a 2 pt bar, not a wash.
        if let accent = item.accent {
            accent.setFill()
            let inset: CGFloat = item.isActive && vertical ? 3 : 0
            NSRect(x: inset, y: bounds.midY - 6.5, width: 2, height: 13).fill()
        }

        var x: CGFloat = item.accent == nil ? 9 : 13
        let centreY = bounds.midY

        // Pinned and read-only are glyphs, never emoji.
        func drawGlyph(_ name: String, tint: NSColor) {
            guard let glyph = DS.symbol(name, pointSize: 10, color: tint) else { return }
            let rect = NSRect(x: x, y: centreY - glyph.size.height / 2,
                              width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: rect)
            x += glyph.size.width + 4
        }

        if item.isPinned { drawGlyph("pin.fill", tint: DS.Color.textSecondary) }
        if item.isReadOnly { drawGlyph("lock.fill", tint: DS.Color.textSecondary) }

        // Title
        let trailing: CGFloat = (item.showsCloseButton ? 22 : 8) + (item.isDirty ? 12 : 0)
        let available = max(0, bounds.width - x - trailing)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.Font.dense(),
            .foregroundColor: item.isActive ? DS.Color.textPrimary : DS.Color.textSecondary,
        ]
        let title = (item.title as NSString)
        let size = title.size(withAttributes: attributes)
        let text = size.width <= available ? title : truncate(title, to: available, attributes: attributes)
        text.draw(at: NSPoint(x: x, y: centreY - size.height / 2), withAttributes: attributes)

        // Dirty dot — paired with the accessibility description above.
        if item.isDirty {
            let dot = NSRect(x: bounds.width - (item.showsCloseButton ? 34 : 16),
                             y: centreY - 3.5, width: 7, height: 7)
            (item.isActive ? DS.Color.brand : DS.Color.textSecondary).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        // Trailing hairline between tabs.
        if !vertical {
            DS.Color.separator.setFill()
            NSRect(x: bounds.width - 1, y: 5, width: 1, height: bounds.height - 10).fill()
        }
    }

    private func truncate(_ text: NSString, to width: CGFloat,
                          attributes: [NSAttributedString.Key: Any]) -> NSString {
        var candidate = text as String
        while !candidate.isEmpty,
              (candidate + "…" as NSString).size(withAttributes: attributes).width > width {
            candidate.removeLast()
        }
        return (candidate.isEmpty ? "…" : candidate + "…") as NSString
    }
}
