import AppKit

/// Where a panel docks. Notepad++ allows left/right/bottom docking plus
/// floating; these map onto split-view sides.
public enum DockPosition: String, CaseIterable, Sendable, Codable {
    case left, right, bottom
}

/// A dockable panel. Concrete panels supply a title and a content view; the
/// host handles docking, sizing, visibility and persistence.
@MainActor
public protocol DockablePanel: AnyObject {
    var panelIdentifier: String { get }
    var panelTitle: String { get }
    var preferredPosition: DockPosition { get }
    var contentView: NSView { get }
    /// Called when the active document changes so the panel can refresh.
    func panelDidBecomeVisible()
}

@MainActor
public extension DockablePanel {
    func panelDidBecomeVisible() {}
}

/// Hosts dockable panels around a central editor area.
///
/// Uses nested `NSSplitView`s: an outer vertical split (content over bottom
/// dock) containing a horizontal split (left dock, editor, right dock). Divider
/// positions and visibility persist across launches, which is what makes a
/// panel layout feel like it belongs to the user rather than the app.
@MainActor
public final class DockHostView: NSView {
    private let outerSplit = NSSplitView()
    private let innerSplit = NSSplitView()
    private let leftContainer = PanelStackView(position: .left)
    private let rightContainer = PanelStackView(position: .right)
    private let bottomContainer = PanelStackView(position: .bottom)
    private let centerContainer = NSView()

    private var panels: [String: DockablePanel] = [:]
    private var visibleIdentifiers: Set<String> = []
    private var floatingWindows: [String: NSPanel] = [:]
    private let defaultsKey = "NotepadXX.DockLayout"

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        // Docks are added to the split only when they hold a panel. Merely
        // hiding them leaves their divider in place, and the divider indices
        // then no longer line up with what is on screen.
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.addArrangedSubview(centerContainer)

        outerSplit.isVertical = false
        outerSplit.dividerStyle = .thin
        outerSplit.addArrangedSubview(innerSplit)

        outerSplit.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerSplit)
        NSLayoutConstraint.activate([
            outerSplit.topAnchor.constraint(equalTo: topAnchor),
            outerSplit.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerSplit.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateContainerVisibility()
    }

    /// The area the editor occupies, between the docks.
    public var editorContainer: NSView { centerContainer }

    public func register(_ panel: DockablePanel) {
        panels[panel.panelIdentifier] = panel
    }

    public func isVisible(_ identifier: String) -> Bool {
        visibleIdentifiers.contains(identifier)
    }

    public func toggle(_ identifier: String) {
        isVisible(identifier) ? hide(identifier) : show(identifier)
    }

    public func show(_ identifier: String) {
        guard let panel = panels[identifier], !visibleIdentifiers.contains(identifier) else { return }
        container(for: panel.preferredPosition).add(panel)
        visibleIdentifiers.insert(identifier)
        panel.panelDidBecomeVisible()
        updateContainerVisibility()
        saveLayout()
    }

    /// Tears a panel out of its dock into its own utility window.
    ///
    /// Notepad++ lets panels float. On macOS a floating utility panel is the
    /// natural equivalent; closing it re-docks rather than losing the panel.
    public func float(_ identifier: String) {
        guard let panel = panels[identifier], floatingWindows[identifier] == nil else { return }
        hide(identifier)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        window.title = panel.panelTitle
        window.isFloatingPanel = true
        window.contentView = panel.contentView
        window.center()
        window.makeKeyAndOrderFront(nil)

        floatingWindows[identifier] = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.floatingWindows[identifier] = nil
                self?.show(identifier)
            }
        }
        panel.panelDidBecomeVisible()
    }

    public func isFloating(_ identifier: String) -> Bool {
        floatingWindows[identifier] != nil
    }

    /// Returns a floating panel to its dock.
    public func dock(_ identifier: String) {
        guard let window = floatingWindows[identifier] else { return }
        window.close()
    }

    public func hide(_ identifier: String) {
        guard let panel = panels[identifier] else { return }
        container(for: panel.preferredPosition).remove(panel)
        visibleIdentifiers.remove(identifier)
        updateContainerVisibility()
        saveLayout()
    }

    /// Notifies visible panels that the active document changed.
    public func refreshVisiblePanels() {
        for identifier in visibleIdentifiers.union(floatingWindows.keys) {
            panels[identifier]?.panelDidBecomeVisible()
        }
    }

    private func container(for position: DockPosition) -> PanelStackView {
        switch position {
        case .left: return leftContainer
        case .right: return rightContainer
        case .bottom: return bottomContainer
        }
    }

    /// Default dock sizes. NSSplitView otherwise hands almost all the space to
    /// a newly added subview, squeezing the editor down to a sliver.
    private let sideDockWidth: CGFloat = 260
    private let bottomDockHeight: CGFloat = 180

    /// A dock with no panels is removed from the split entirely.
    private func updateContainerVisibility() {
        syncDock(leftContainer, in: innerSplit, atIndex: 0)
        syncDock(rightContainer, in: innerSplit, atIndex: innerSplit.arrangedSubviews.count)
        syncDock(bottomContainer, in: outerSplit, atIndex: outerSplit.arrangedSubviews.count)
        for split in [innerSplit, outerSplit] { split.adjustSubviews() }
        // Divider positions are only meaningful once the split has a size.
        DispatchQueue.main.async { [weak self] in self?.applyDockSizes() }
    }

    private func syncDock(_ container: PanelStackView, in split: NSSplitView, atIndex index: Int) {
        let attached = container.superview === split
        if !container.isEmpty && !attached {
            split.insertArrangedSubview(container, at: min(index, split.arrangedSubviews.count))
        } else if container.isEmpty && attached {
            split.removeArrangedSubview(container)
            container.removeFromSuperview()
        }
    }

    /// Pins each visible dock to its default size, leaving the rest to the editor.
    private func applyDockSizes() {
        let width = innerSplit.bounds.width
        let height = outerSplit.bounds.height
        guard width > 0, height > 0 else { return }

        if bottomContainer.superview === outerSplit {
            outerSplit.setPosition(height - bottomDockHeight, ofDividerAt: 0)
        }
        // Dividers are indexed left to right across the attached subviews.
        var divider = 0
        if leftContainer.superview === innerSplit {
            innerSplit.setPosition(sideDockWidth, ofDividerAt: divider)
            divider += 1
        }
        if rightContainer.superview === innerSplit {
            innerSplit.setPosition(width - sideDockWidth, ofDividerAt: divider)
        }
    }

    // MARK: - Persistence

    public func saveLayout() {
        UserDefaults.standard.set(Array(visibleIdentifiers), forKey: defaultsKey)
    }

    public func restoreLayout() {
        guard let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] else { return }
        for identifier in saved { show(identifier) }
    }
}

/// Stacks one or more panels docked on the same side, each with a title header.
@MainActor
final class PanelStackView: NSView {
    private let stack = NSStackView()
    private var hosted: [String: NSView] = [:]
    let position: DockPosition

    init(position: DockPosition) {
        self.position = position
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // Docks need a sensible default width/height or the split collapses them.
        switch position {
        case .left, .right:
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        case .bottom:
            heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEmpty: Bool { hosted.isEmpty }

    func add(_ panel: DockablePanel) {
        guard hosted[panel.panelIdentifier] == nil else { return }
        let wrapper = NSView()
        let header = NSTextField(labelWithString: panel.panelTitle.uppercased())
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let content = panel.contentView
        for subview in [header, content] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        hosted[panel.panelIdentifier] = wrapper
        stack.addArrangedSubview(wrapper)
    }

    func remove(_ panel: DockablePanel) {
        guard let wrapper = hosted.removeValue(forKey: panel.panelIdentifier) else { return }
        stack.removeArrangedSubview(wrapper)
        wrapper.removeFromSuperview()
    }
}
