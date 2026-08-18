import AppKit
import NotepadXXCore

/// Dual-view support: Notepad++'s "Move to Other View" and "Clone to Other View".
///
/// A tab is a (document, pane) pair, so cloning adds a second tab referencing
/// the *same* `TextDocument` instance. That is what makes an edit in one pane
/// appear in the other; copying the document would let the two silently diverge
/// and the second save would clobber the first.
extension MainWindowController {

    public var isSplit: Bool { tabs.contains { $0.pane == 1 } }

    public func tabs(inPane pane: Int) -> [EditorTab] {
        tabs.filter { $0.pane == pane }
    }

    @objc public func moveToOtherViewAction(_ sender: Any?) {
        guard tabs.indices.contains(activeIndex) else { return }
        setPane(tabs[activeIndex].pane == 0 ? 1 : 0, forTabAt: activeIndex)
        refreshUI()
    }

    @objc public func cloneToOtherViewAction(_ sender: Any?) {
        guard tabs.indices.contains(activeIndex) else { return }
        let tab = tabs[activeIndex]
        let target = tab.pane == 0 ? 1 : 0

        // Already cloned into that pane: nothing to do.
        guard !tabs.contains(where: { $0.document === tab.document && $0.pane == target }) else { return }
        appendClone(of: tab.document, inPane: target)
        refreshUI()
    }

    /// Collapses the split, returning every secondary tab to the primary pane
    /// and dropping clones that would otherwise become duplicates.
    @objc public func closeSplitAction(_ sender: Any?) {
        var seen: [ObjectIdentifier] = []
        var kept: [EditorTab] = []
        for tab in tabs {
            let identity = ObjectIdentifier(tab.document)
            if seen.contains(identity) { continue }
            seen.append(identity)
            var moved = tab
            moved.pane = 0
            moved.document.paneIndex = 0
            kept.append(moved)
        }
        replaceTabs(kept)
        refreshUI()
    }

    @objc public func toggleSplitViewAction(_ sender: Any?) {
        if isSplit {
            closeSplitAction(sender)
        } else if tabs.count > 1 {
            moveToOtherViewAction(sender)
        } else {
            cloneToOtherViewAction(sender)
        }
    }
}
