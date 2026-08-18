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
    private let defaultsKey = "NotepadXX.DockLayout"

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.addArrangedSubview(leftContainer)
        innerSplit.addArrangedSubview(centerContainer)
        innerSplit.addArrangedSubview(rightContainer)

        outerSplit.isVertical = false
        outerSplit.dividerStyle = .thin
        outerSplit.addArrangedSubview(innerSplit)
        outerSplit.addArrangedSubview(bottomContainer)

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

    public func hide(_ identifier: String) {
        guard let panel = panels[identifier] else { return }
        container(for: panel.preferredPosition).remove(panel)
        visibleIdentifiers.remove(identifier)
        updateContainerVisibility()
        saveLayout()
    }

    /// Notifies visible panels that the active document changed.
    public func refreshVisiblePanels() {
        for identifier in visibleIdentifiers {
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

    /// A dock with no panels takes no space.
    private func updateContainerVisibility() {
        for container in [leftContainer, rightContainer, bottomContainer] {
            container.isHidden = container.isEmpty
        }
        for split in [innerSplit, outerSplit] { split.adjustSubviews() }
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
