import AppKit
import NotepadXXCore

/// Prompts that belong to one document, presented as sheets under the title
/// bar of the window they concern.
///
/// The design's rule: anything that acts on one document is a sheet; anything
/// that stands alone is its own window. A document prompt shown as a free
/// floating alert steals the whole app for something that concerns one tab.
extension MainWindowController {

    /// Runs an alert as a sheet on this window. Falls back to a modal run when
    /// there is no window to attach to, which is the case in tests.
    func presentSheet(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window, window.isVisible else {
            completion(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    // MARK: - A file changed underneath us

    /// Asks about each externally-changed document in turn.
    ///
    /// The prompts are sequenced rather than raised together: several sheets on
    /// one window would stack invisibly, and the user would answer for a
    /// document they cannot see.
    func promptForExternalChanges(_ pending: [TextDocument]) {
        var remaining = pending
        guard !remaining.isEmpty else {
            refreshUI()
            return
        }
        let document = remaining.removeFirst()
        guard let url = document.fileURL else {
            promptForExternalChanges(remaining)
            return
        }

        let alert = NSAlert()
        alert.messageText = "“\(url.lastPathComponent)” was changed by another application"
        alert.informativeText = document.isDirty
            ? """
              You have unsaved edits in this document. Reloading discards them; keeping yours \
              leaves the file on disk untouched until you save.
              """
            : "Reloading takes the version on disk."
        alert.accessoryView = ChangeComparisonView(document: document, url: url)

        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep Mine")
        // Comparing is only meaningful when the two actually differ from what
        // the user has in front of them.
        if document.isDirty { alert.addButton(withTitle: "Compare…") }

        presentSheet(alert) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                if let reloaded = try? TextDocument.load(contentsOf: url) {
                    document.adoptContents(of: reloaded)
                    if let editor = self.editors[document.id] { editor.load(text: document.text) }
                }
            case .alertThirdButtonReturn:
                self.openOnDiskCopyForComparison(of: document, at: url)
            default:
                // Stop asking about this revision.
                document.acceptOnDiskRevision()
            }
            self.promptForExternalChanges(remaining)
        }
    }

    /// Opens the version on disk beside the edited one, read-only, so the two
    /// can be read side by side.
    private func openOnDiskCopyForComparison(of document: TextDocument, at url: URL) {
        guard let onDisk = try? TextDocument.load(contentsOf: url) else { return }
        onDisk.untitledName = "\(url.lastPathComponent) — on disk"
        // Read-only, so the comparison copy can never be saved back over the
        // file it was opened to compare against.
        onDisk.isReadOnly = true
        openBeside(onDisk)
        document.acceptOnDiskRevision()
        refreshUI()
    }

    // MARK: - Closing an edited document

    /// Asks before losing edits, then closes if the answer allows it.
    func confirmDiscard(of document: TextDocument, then close: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save the changes to “\(document.displayName)”?"
        alert.informativeText = """
            Your changes will be lost if you don't save them. A snapshot is kept until this \
            document closes.
            """
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let discard = alert.addButton(withTitle: "Don't Save")
        discard.hasDestructiveAction = true

        presentSheet(alert) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                self?.saveDocumentAction(nil)
                close(!document.isDirty)
            case .alertThirdButtonReturn:
                close(true)
            default:
                close(false)
            }
        }
    }

    // MARK: - A save that failed

    /// Reports a failed save with what actually went wrong, and offers the two
    /// ways out: somewhere else, or with more rights.
    func presentSaveFailure(_ error: Error, url: URL?) {
        let alert = NSAlert()
        alert.messageText = "The document could not be saved"
        let code = (error as NSError).code
        alert.informativeText = code == NSFileWriteNoPermissionError
            ? "You do not have permission to write to this location."
            : error.localizedDescription
        if let url {
            let detail = NSTextField(labelWithString: "\(url.path) · \((error as NSError).domain) \(code)")
            detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            detail.textColor = .secondaryLabelColor
            alert.accessoryView = detail
        }
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")

        presentSheet(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.saveDocumentAsAction(nil)
        }
    }
}

/// The two sides of an external change: what is on disk against what is open,
/// so the choice is made on facts rather than on a guess.
final class ChangeComparisonView: NSView {
    init(document: TextDocument, url: URL) {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 40))
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? Int).map(Self.formatted) ?? "—"

        let onDisk = Self.line(
            title: "On disk",
            detail: "\(Self.formatted(modified)) · \(size)")
        let yours = Self.line(
            title: "Yours",
            detail: document.isDirty ? "unsaved edits" : "no unsaved edits")

        let stack = NSStackView(views: [onDisk, yours])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func line(title: String, detail: String) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 11, weight: .semibold)
        name.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let value = NSTextField(labelWithString: detail)
        value.font = .systemFont(ofSize: 11)
        value.textColor = .secondaryLabelColor
        let row = NSStackView(views: [name, value])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private static func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
