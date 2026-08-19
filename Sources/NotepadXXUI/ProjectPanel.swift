import AppKit
import NotepadXXDesign
import NotepadXXCore

/// A docked tree of the active project's files.
///
/// Distinct from Folder as Workspace: this shows a curated list, so files can
/// be added and removed, and a missing file is shown struck through rather than
/// silently omitted.
@MainActor
public final class ProjectPanel: NSObject, DockablePanel {
    public let panelIdentifier = "projectPanel"
    public let panelTitle = "Project"
    public let preferredPosition = DockPosition.left

    public var projectProvider: (() -> Project?)?
    public var onOpenFile: ((URL) -> Void)?
    public var onRemoveFile: ((String) -> Void)?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var project: Project?

    /// A node in the displayed tree: either a folder or a file path.
    private enum Node: Hashable {
        case folder(Project.Folder)
        case file(String)
    }

    public override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = 220
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rowActivated)
        outlineView.menu = makeContextMenu()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        installContainer()
    }

    private let container = NSView()
    private var placeholder: DSEmptyState?

    /// Called when the placeholder's button is pressed.
    public var onCreateProject: (() -> Void)?

    public var contentView: NSView { container }

    /// Builds the container the placeholder needs. Called from init.
    private func installContainer() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        placeholder = PanelPlaceholder.install(
            in: container, over: scrollView,
            symbol: "folder.badge.gearshape",
            title: "No project open",
            message: "Create a project to group files, sessions and run commands.",
            actionTitle: "New Project…") { [weak self] in self?.onCreateProject?() }
    }

    public func panelDidBecomeVisible() { reload() }

    public func reload() {
        project = projectProvider?()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        PanelPlaceholder.show(placeholder, whenEmpty: project == nil, hiding: scrollView)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let remove = menu.addItem(withTitle: "Remove from Project",
                                  action: #selector(removeTapped), keyEquivalent: "")
        remove.target = self
        return menu
    }

    @objc private func rowActivated() {
        guard case .file(let path)? = outlineView.item(atRow: outlineView.clickedRow) as? Node else {
            let row = outlineView.clickedRow
            if row >= 0, let item = outlineView.item(atRow: row) {
                outlineView.isItemExpanded(item)
                    ? outlineView.collapseItem(item) : outlineView.expandItem(item)
            }
            return
        }
        onOpenFile?(URL(fileURLWithPath: path))
    }

    @objc private func removeTapped() {
        guard case .file(let path)? = outlineView.item(atRow: outlineView.clickedRow) as? Node else { return }
        onRemoveFile?(path)
        reload()
    }
}

extension ProjectPanel: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func children(of node: Node?) -> [Node] {
        switch node {
        case .none:
            guard let project else { return [] }
            return [.folder(project.root)]
        case .folder(let folder):
            return folder.folders.map(Node.folder) + folder.filePaths.map(Node.file)
        case .file:
            return []
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item as? Node).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item as? Node)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if case .folder = item as? Node { return true }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        switch node {
        case .folder(let folder):
            let field = NSTextField(labelWithString: folder.name)
            field.font = .systemFont(ofSize: 11, weight: .semibold)
            return field
        case .file(let path):
            let name = (path as NSString).lastPathComponent
            let exists = FileManager.default.fileExists(atPath: path)
            let field = NSTextField(labelWithString: name)
            field.font = .systemFont(ofSize: 11)
            field.lineBreakMode = .byTruncatingMiddle
            if !exists {
                // A missing file is shown, struck through, rather than hidden.
                field.attributedStringValue = NSAttributedString(
                    string: name,
                    attributes: [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.systemRed,
                        .font: NSFont.systemFont(ofSize: 11),
                    ]
                )
                field.toolTip = "Missing: \(path)"
            } else {
                field.toolTip = path
            }
            return field
        }
    }
}
