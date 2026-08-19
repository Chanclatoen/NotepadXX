import AppKit
import NotepadXXDesign

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

    /// Where each panel is docked now, which may differ from its preference
    /// once the user has moved it.
    private var dockPositions: [String: DockPosition] = [:]
    /// Divider sizes, updated as the user drags and restored on launch.
    private var currentLeftWidth: CGFloat = 260
    private var currentRightWidth: CGFloat = 260
    private var currentBottomHeight: CGFloat = 180
    /// Suppresses saving while a restore is in flight, so a partly-applied
    /// layout is never written back over the saved one.
    private var isRestoring = false
    /// Nothing is saved until the host has either restored a layout or been
    /// told to change one. Laying out an empty host emits split-view resize
    /// notifications, and saving those would overwrite the user's saved layout
    /// with an empty one before it had a chance to load.
    private var acceptsSaves = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        for container in [leftContainer, rightContainer, bottomContainer] {
            container.onClosePanel = { [weak self] identifier in self?.hide(identifier) }
            container.onFloatPanel = { [weak self] identifier in self?.float(identifier) }
        }
        // Docks are added to the split only when they hold a panel. Merely
        // hiding them leaves their divider in place, and the divider indices
        // then no longer line up with what is on screen.
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.addArrangedSubview(centerContainer)

        outerSplit.isVertical = false
        outerSplit.dividerStyle = .thin
        innerSplit.delegate = self
        outerSplit.delegate = self
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
        acceptsSaves = true
        guard let panel = panels[identifier], !visibleIdentifiers.contains(identifier) else { return }
        container(for: position(of: panel)).add(panel)
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
        acceptsSaves = true
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
        // Floating is part of the layout: hide() saved it as merely closed.
        saveLayout()
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
        acceptsSaves = true
        guard let panel = panels[identifier] else { return }
        container(for: position(of: panel)).remove(panel)
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

    /// Where this panel sits: what the user last chose, or its preference.
    public func position(of panel: DockablePanel) -> DockPosition {
        dockPositions[panel.panelIdentifier] ?? panel.preferredPosition
    }

    /// Moves a panel to another dock, keeping it visible.
    public func move(_ identifier: String, to position: DockPosition) {
        acceptsSaves = true
        guard let panel = panels[identifier] else { return }
        let wasVisible = visibleIdentifiers.contains(identifier)
        if wasVisible { hide(identifier) }
        dockPositions[identifier] = position
        if wasVisible { show(identifier) }
        saveLayout()
    }

    private func container(for position: DockPosition) -> PanelStackView {
        switch position {
        case .left: return leftContainer
        case .right: return rightContainer
        case .bottom: return bottomContainer
        }
    }

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

    /// Restores each visible dock to the size the user left it at.
    private func applyDockSizes() {
        let width = innerSplit.bounds.width
        let height = outerSplit.bounds.height
        guard width > 0, height > 0 else { return }

        if bottomContainer.superview === outerSplit {
            outerSplit.setPosition(height - currentBottomHeight, ofDividerAt: 0)
        }
        // Dividers are indexed left to right across the attached subviews.
        var divider = 0
        if leftContainer.superview === innerSplit {
            innerSplit.setPosition(currentLeftWidth, ofDividerAt: divider)
            divider += 1
        }
        if rightContainer.superview === innerSplit {
            innerSplit.setPosition(width - currentRightWidth, ofDividerAt: divider)
        }
    }

    /// Records the sizes after the user drags a divider, so they survive a
    /// relaunch rather than snapping back to the defaults.
    fileprivate func recordDockSizes() {
        guard !isRestoring else { return }
        if leftContainer.superview === innerSplit, leftContainer.bounds.width > 0 {
            currentLeftWidth = leftContainer.bounds.width
        }
        if rightContainer.superview === innerSplit, rightContainer.bounds.width > 0 {
            currentRightWidth = rightContainer.bounds.width
        }
        if bottomContainer.superview === outerSplit, bottomContainer.bounds.height > 0 {
            currentBottomHeight = bottomContainer.bounds.height
        }
        saveLayout()
    }

    // MARK: - Persistence

    /// Everything about the panel layout that belongs to the user: which
    /// panels are open, where each one is docked, which are floating, and how
    /// big the docks are. Saving only visibility loses the arrangement, which
    /// is the part people notice.
    struct Layout: Codable {
        var visible: [String] = []
        var floating: [String] = []
        var positions: [String: DockPosition] = [:]
        var leftWidth: CGFloat = 260
        var rightWidth: CGFloat = 260
        var bottomHeight: CGFloat = 180
        var floatingFrames: [String: String] = [:]
    }

    public func saveLayout() {
        guard !isRestoring, acceptsSaves else { return }
        var layout = Layout()
        layout.visible = Array(visibleIdentifiers).sorted()
        layout.floating = Array(floatingWindows.keys).sorted()
        layout.positions = dockPositions
        layout.leftWidth = currentLeftWidth
        layout.rightWidth = currentRightWidth
        layout.bottomHeight = currentBottomHeight
        for (identifier, window) in floatingWindows {
            layout.floatingFrames[identifier] = NSStringFromRect(window.frame)
        }
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    public func restoreLayout() {
        acceptsSaves = true
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let layout = try? JSONDecoder().decode(Layout.self, from: data) else {
            restoreLegacyLayout()
            return
        }
        isRestoring = true
        dockPositions = layout.positions
        currentLeftWidth = layout.leftWidth
        currentRightWidth = layout.rightWidth
        currentBottomHeight = layout.bottomHeight
        for identifier in layout.visible where !layout.floating.contains(identifier) {
            show(identifier)
        }
        for identifier in layout.floating {
            float(identifier)
            if let string = layout.floatingFrames[identifier] {
                floatingWindows[identifier]?.setFrame(NSRectFromString(string), display: true)
            }
        }
        isRestoring = false
        applyDockSizes()
    }

    /// Layouts written before positions and sizes were saved were a plain
    /// array of identifiers.
    private func restoreLegacyLayout() {
        guard let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] else { return }
        for identifier in saved { show(identifier) }
    }

}

extension DockHostView: NSSplitViewDelegate {
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        recordDockSizes()
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

    /// Called when a panel's header asks to close or float it.
    var onClosePanel: ((String) -> Void)?
    var onFloatPanel: ((String) -> Void)?

    func add(_ panel: DockablePanel) {
        guard hosted[panel.panelIdentifier] == nil else { return }
        let wrapper = NSView()
        // Sentence case, not upper: the design refuses shouted panel headers.
        let header = DSPanelHeader(title: panel.panelTitle)
        let identifier = panel.panelIdentifier
        header.onClose = { [weak self] in self?.onClosePanel?(identifier) }
        header.onFloat = { [weak self] in self?.onFloatPanel?(identifier) }

        let content = panel.contentView
        for subview in [header, content] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: wrapper.topAnchor),
            header.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
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
