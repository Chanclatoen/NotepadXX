import AppKit

/// The Notepad++ toolbar.
///
/// Same command set and grouping as Notepad++, drawn with SF Symbols so it
/// reads as a Mac app rather than a Windows port. Groups are separated by
/// dividers in the same order Notepad++ uses, because the muscle memory of
/// where a button sits is most of a toolbar's value.
public final class ToolbarView: NSView {
    public struct Item {
        public let symbol: String
        public let tooltip: String
        public let selector: Selector
        /// Toolbar buttons that show pressed state, e.g. word wrap.
        public var isToggle: Bool = false
    }

    public var target: AnyObject?
    /// Identifiers whose toggle is currently on.
    public var activeToggles: Set<String> = [] { didSet { refreshToggleStates() } }

    private let stack = NSStackView()
    private var buttons: [String: NSButton] = [:]
    private var toggleTooltips: Set<String> = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // A hairline under the toolbar, as Notepad++ has.
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The default button set, in Notepad++'s order and grouping.
    public static func defaultGroups() -> [[Item]] {
        [
            [
                Item(symbol: "doc.badge.plus", tooltip: "New",
                     selector: #selector(MainWindowController.newDocumentAction(_:))),
                Item(symbol: "folder", tooltip: "Open",
                     selector: #selector(MainWindowController.openDocumentAction(_:))),
                Item(symbol: "square.and.arrow.down", tooltip: "Save",
                     selector: #selector(MainWindowController.saveDocumentAction(_:))),
                Item(symbol: "square.and.arrow.down.on.square", tooltip: "Save All",
                     selector: #selector(MainWindowController.saveAllAction(_:))),
                Item(symbol: "xmark.square", tooltip: "Close",
                     selector: #selector(MainWindowController.closeTabAction(_:))),
                Item(symbol: "xmark.square.fill", tooltip: "Close All",
                     selector: #selector(MainWindowController.closeAllTabsAction(_:))),
                Item(symbol: "printer", tooltip: "Print",
                     selector: #selector(MainWindowController.printDocumentAction(_:))),
            ],
            [
                Item(symbol: "scissors", tooltip: "Cut", selector: #selector(NSText.cut(_:))),
                Item(symbol: "doc.on.doc", tooltip: "Copy", selector: #selector(NSText.copy(_:))),
                Item(symbol: "doc.on.clipboard", tooltip: "Paste", selector: #selector(NSText.paste(_:))),
            ],
            [
                Item(symbol: "arrow.uturn.backward", tooltip: "Undo", selector: Selector(("undo:"))),
                Item(symbol: "arrow.uturn.forward", tooltip: "Redo", selector: Selector(("redo:"))),
            ],
            [
                Item(symbol: "magnifyingglass", tooltip: "Find",
                     selector: #selector(MainWindowController.showFindPanelAction(_:))),
                Item(symbol: "arrow.2.squarepath", tooltip: "Replace",
                     selector: #selector(MainWindowController.showReplacePanelAction(_:))),
                Item(symbol: "doc.text.magnifyingglass", tooltip: "Find in Files",
                     selector: #selector(MainWindowController.showFindInFilesAction(_:))),
            ],
            [
                Item(symbol: "plus.magnifyingglass", tooltip: "Zoom In",
                     selector: #selector(MainWindowController.zoomInAction(_:))),
                Item(symbol: "minus.magnifyingglass", tooltip: "Zoom Out",
                     selector: #selector(MainWindowController.zoomOutAction(_:))),
            ],
            [
                Item(symbol: "arrow.turn.down.left", tooltip: "Word Wrap",
                     selector: #selector(MainWindowController.toggleWordWrapAction(_:)), isToggle: true),
                Item(symbol: "paragraphsign", tooltip: "Show All Characters",
                     selector: #selector(MainWindowController.toggleShowAllCharactersAction(_:)), isToggle: true),
                Item(symbol: "text.alignleft", tooltip: "Indent Guide",
                     selector: #selector(MainWindowController.toggleIndentGuideAction(_:)), isToggle: true),
            ],
            [
                Item(symbol: "map", tooltip: "Document Map",
                     selector: #selector(MainWindowController.toggleDocumentMapAction(_:)), isToggle: true),
                Item(symbol: "list.bullet.indent", tooltip: "Function List",
                     selector: #selector(MainWindowController.toggleFunctionListAction(_:)), isToggle: true),
                Item(symbol: "folder.badge.gearshape", tooltip: "Folder as Workspace",
                     selector: #selector(MainWindowController.openFolderAsWorkspaceAction(_:))),
            ],
            [
                Item(symbol: "record.circle", tooltip: "Start/Stop Recording",
                     selector: #selector(MainWindowController.toggleMacroRecordingAction(_:)), isToggle: true),
                Item(symbol: "play.circle", tooltip: "Playback",
                     selector: #selector(MainWindowController.playbackMacroAction(_:))),
                Item(symbol: "repeat.circle", tooltip: "Run a Macro Multiple Times",
                     selector: #selector(MainWindowController.runMacroMultipleTimesAction(_:))),
                Item(symbol: "terminal", tooltip: "Run",
                     selector: #selector(MainWindowController.runCommandAction(_:))),
            ],
        ]
    }

    func applyChrome(background: NSColor) {
        layer?.backgroundColor = background.cgColor
    }

    public func configure(groups: [[Item]]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        toggleTooltips = Set(groups.flatMap { $0 }.filter(\.isToggle).map(\.tooltip))

        for (index, group) in groups.enumerated() {
            if index > 0 { stack.addArrangedSubview(makeDivider()) }
            for item in group {
                let button = makeButton(item)
                buttons[item.tooltip] = button
                stack.addArrangedSubview(button)
            }
        }
        refreshToggleStates()
    }

    private func makeButton(_ item: Item) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.tooltip)
        assert(image != nil, "unknown SF Symbol \(item.symbol) — it would render as truncated text")
        button.image = image
        // Never fall back to the title: a missing glyph should show as an empty
        // button, not as clipped words in the middle of the toolbar.
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = item.tooltip
        button.target = target
        button.action = item.selector
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        // Toggles get a visible pressed state, as Notepad++'s do.
        if item.isToggle {
            button.setButtonType(.pushOnPushOff)
            button.wantsLayer = true
        }
        return button
    }

    private func makeDivider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let container = NSView()
        container.addSubview(box)
        NSLayoutConstraint.activate([
            box.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            box.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(equalToConstant: 9),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    private func refreshToggleStates() {
        for (tooltip, button) in buttons where toggleTooltips.contains(tooltip) {
            let on = activeToggles.contains(tooltip)
            button.state = on ? .on : .off
            button.layer?.backgroundColor = on
                ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
            button.layer?.cornerRadius = 4
        }
    }
}
