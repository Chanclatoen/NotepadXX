import AppKit
import NotepadXXCore

/// Tab management: reorder, pin, colour, sort, and the tab context menu.
extension MainWindowController {

    func attributes(for document: TextDocument) -> TabAttributes {
        tabAttributes[document.id] ?? TabAttributes()
    }

    func setAttributes(_ attributes: TabAttributes, for document: TextDocument) {
        tabAttributes[document.id] = attributes
        applyPinnedOrdering()
        refreshUI()
    }

    /// Pinned tabs sit at the left, as in Notepad++.
    func applyPinnedOrdering() {
        let active = tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
        let order = TabSorting.ordering(count: tabs.count) {
            attributes(for: tabs[$0].document).isPinned
        }
        guard order != Array(0..<tabs.count) else { return }
        reorderTabs(order, keeping: active)
    }

    func reorderTabs(_ order: [Int], keeping active: EditorTab?) {
        let reordered = order.compactMap { tabs.indices.contains($0) ? tabs[$0] : nil }
        guard reordered.count == tabs.count else { return }
        setTabs(reordered)
        if let active, let index = tabs.firstIndex(where: {
            $0.document === active.document && $0.pane == active.pane
        }) {
            selectTab(at: index)
        }
    }

    @objc public func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source) else { return }
        let clamped = TabSorting.clampedDestination(
            moving: source, to: destination,
            isPinned: { self.attributes(for: self.tabs[$0].document).isPinned },
            count: tabs.count
        )
        guard clamped != source else { return }
        var order = Array(0..<tabs.count)
        order.remove(at: source)
        order.insert(source, at: clamped)
        reorderTabs(order, keeping: tabs[activeIndex])
    }

    @objc public func togglePinTabAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        var current = attributes(for: document)
        current.isPinned.toggle()
        setAttributes(current, for: document)
    }

    @objc public func setTabColourAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? Int,
              let colour = TabAttributes.Colour(rawValue: raw),
              let document = activeDocument else { return }
        var current = attributes(for: document)
        current.colour = colour
        setAttributes(current, for: document)
    }

    @objc public func sortTabsByNameAction(_ sender: Any?) { sortTabs(.name) }
    @objc public func sortTabsByPathAction(_ sender: Any?) { sortTabs(.path) }
    @objc public func sortTabsByTypeAction(_ sender: Any?) { sortTabs(.extensionThenName) }

    private func sortTabs(_ order: TabSorting.Order) {
        let active = tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
        let sorted = TabSorting.sorted(
            indices: Array(0..<tabs.count), order: order,
            name: { self.tabs[$0].document.displayName },
            path: { self.tabs[$0].document.fileURL?.path }
        )
        // Pinned tabs stay left even after a sort.
        let pinnedFirst = sorted.filter { attributes(for: tabs[$0].document).isPinned }
            + sorted.filter { !attributes(for: tabs[$0].document).isPinned }
        reorderTabs(pinnedFirst, keeping: active)
    }

    // MARK: - Close variants

    @objc public func closeAllTabsAction(_ sender: Any?) {
        setTabs([])
        newDocument()
    }

    @objc public func closeOtherTabsAction(_ sender: Any?) {
        guard tabs.indices.contains(activeIndex) else { return }
        setTabs([tabs[activeIndex]])
        selectTab(at: 0)
    }

    @objc public func closeTabsToTheLeftAction(_ sender: Any?) {
        guard tabs.indices.contains(activeIndex) else { return }
        setTabs(Array(tabs[activeIndex...]))
        selectTab(at: 0)
    }

    @objc public func closeTabsToTheRightAction(_ sender: Any?) {
        guard tabs.indices.contains(activeIndex) else { return }
        setTabs(Array(tabs[...activeIndex]))
        selectTab(at: tabs.count - 1)
    }

    @objc public func toggleReadOnlyAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        document.isReadOnly.toggle()
        currentEditor?.isEditable = !document.isReadOnly
        refreshUI()
    }

    // MARK: - Context menu

    func showTabContextMenu(forTabAt index: Int, at point: NSPoint) {
        guard tabs.indices.contains(index) else { return }
        selectTab(at: index)
        let document = tabs[index].document
        let current = attributes(for: document)

        let menu = NSMenu()
        func item(_ title: String, _ selector: Selector, state: NSControl.StateValue = .off) {
            let entry = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.state = state
        }

        item("Close", #selector(closeTabAction(_:)))
        item("Close All but This", #selector(closeOtherTabsAction(_:)))
        item("Close All to the Left", #selector(closeTabsToTheLeftAction(_:)))
        item("Close All to the Right", #selector(closeTabsToTheRightAction(_:)))
        menu.addItem(.separator())
        item(current.isPinned ? "Unpin Tab" : "Pin Tab", #selector(togglePinTabAction(_:)))
        item("Read-Only", #selector(toggleReadOnlyAction(_:)),
             state: document.isReadOnly ? .on : .off)
        menu.addItem(.separator())

        let colours = NSMenuItem(title: "Apply Colour to Tab", action: nil, keyEquivalent: "")
        let colourMenu = NSMenu()
        for colour in TabAttributes.Colour.allCases {
            let entry = colourMenu.addItem(
                withTitle: colour.displayName,
                action: #selector(setTabColourAction(_:)), keyEquivalent: ""
            )
            entry.representedObject = colour.rawValue
            entry.target = self
            entry.state = colour == current.colour ? .on : .off
        }
        colours.submenu = colourMenu
        menu.addItem(colours)
        menu.addItem(.separator())

        item("Rename…", #selector(renameFileAction(_:)))
        item("Move to Trash", #selector(moveToTrashAction(_:)))
        item("Reveal in Finder", #selector(revealInFinderAction(_:)))
        item("Copy Full Path to Clipboard", #selector(copyFullPathAction(_:)))
        menu.addItem(.separator())
        item("Move to Other View", #selector(moveToOtherViewAction(_:)))
        item("Clone to Other View", #selector(cloneToOtherViewAction(_:)))

        menu.popUp(positioning: nil, at: tabBar.convert(point, from: nil), in: tabBar)
    }

    /// AppKit colour for a tab tag.
    func colour(for attributes: TabAttributes) -> NSColor? {
        switch attributes.colour {
        case .none: return nil
        case .yellow: return NSColor.systemYellow.withAlphaComponent(0.35)
        case .green: return NSColor.systemGreen.withAlphaComponent(0.35)
        case .blue: return NSColor.systemBlue.withAlphaComponent(0.35)
        case .orange: return NSColor.systemOrange.withAlphaComponent(0.35)
        case .purple: return NSColor.systemPurple.withAlphaComponent(0.35)
        }
    }
}
