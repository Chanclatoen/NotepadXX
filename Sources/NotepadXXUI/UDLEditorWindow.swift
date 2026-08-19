import AppKit
import NotepadXXCore
import NotepadXXDesign

/// "Define your language…" — the GUI for authoring a User Defined Language.
///
/// This is the piece nothing else on macOS offers: other editors make you
/// hand-write a grammar file. Everything here edits a `LanguageDefinition`,
/// the same type the built-in languages use, so a user-defined language is a
/// first-class citizen rather than a lesser tier.
@MainActor
public final class UDLEditorWindowController: NSWindowController {
    private var definition: LanguageDefinition
    private let registry: LanguageRegistry
    private let onSave: (LanguageDefinition) -> Void

    private let nameField = NSTextField(string: "")
    private let extensionsField = NSTextField(string: "")
    private let caseSensitiveBox = NSButton(checkboxWithTitle: "Case sensitive", target: nil, action: nil)
    private let lineCommentField = NSTextField(string: "")
    private let blockOpenField = NSTextField(string: "")
    private let blockCloseField = NSTextField(string: "")
    private let nestBox = NSButton(checkboxWithTitle: "Block comments nest", target: nil, action: nil)
    private let delimitersField = NSTextField(string: "")
    private let escapeField = NSTextField(string: "")
    private let operatorsField = NSTextField(string: "")
    private let foldOpenField = NSTextField(string: "")
    private let foldCloseField = NSTextField(string: "")
    private let keywordViews: [NSTextView] = (0..<4).map { _ in NSTextView() }
    private let previewLabel = NSTextField(labelWithString: "")
    /// Always visible, and repainted as the rules are typed.
    private let livePreview = UDLPreviewView()

    public init(
        editing definition: LanguageDefinition? = nil,
        registry: LanguageRegistry = .shared,
        onSave: @escaping (LanguageDefinition) -> Void
    ) {
        self.definition = definition ?? LanguageDefinition(name: "New Language")
        self.registry = registry
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "User Defined Language"
        super.init(window: window)
        buildLayout()
        populate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }

        func labelled(_ title: String, _ control: NSView, width: CGFloat = 220) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 150).isActive = true
            control.widthAnchor.constraint(equalToConstant: width).isActive = true
            let row = NSStackView(views: [label, control])
            row.orientation = .horizontal
            row.spacing = 8
            return row
        }

        let general = NSStackView(views: [
            labelled("Name", nameField),
            labelled("Extensions (space separated)", extensionsField, width: 320),
            labelled("", caseSensitiveBox),
        ])
        general.orientation = .vertical
        general.alignment = .leading
        general.spacing = 8

        let comments = NSStackView(views: [
            labelled("Line comment tokens", lineCommentField),
            labelled("Block comment open", blockOpenField),
            labelled("Block comment close", blockCloseField),
            labelled("", nestBox),
        ])
        comments.orientation = .vertical
        comments.alignment = .leading
        comments.spacing = 8

        let delimiters = NSStackView(views: [
            labelled("String delimiters", delimitersField),
            labelled("Escape character", escapeField, width: 60),
            labelled("Operator characters", operatorsField, width: 320),
            labelled("Fold open", foldOpenField),
            labelled("Fold close", foldCloseField),
        ])
        delimiters.orientation = .vertical
        delimiters.alignment = .leading
        delimiters.spacing = 8

        // Four keyword groups, matching Notepad++'s Keywords1..4.
        let keywordStack = NSStackView()
        keywordStack.orientation = .horizontal
        keywordStack.distribution = .fillEqually
        keywordStack.spacing = 8
        for (index, textView) in keywordViews.enumerated() {
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            let scroll = NSScrollView()
            scroll.documentView = textView
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder

            let caption = NSTextField(labelWithString: "Keywords \(index + 1)")
            caption.font = .systemFont(ofSize: 10, weight: .semibold)
            let column = NSStackView(views: [caption, scroll])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 4
            scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
            keywordStack.addArrangedSubview(column)
        }

        previewLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingTail

        let preview = NSButton(title: "Test on Current Document", target: self,
                               action: #selector(previewTapped))
        let previewHeading = NSTextField(labelWithString: "Live preview")
        previewHeading.font = DS.Font.bodyEmphasis()
        previewHeading.textColor = DS.Color.textPrimary
        livePreview.translatesAutoresizingMaskIntoConstraints = false
        livePreview.heightAnchor.constraint(equalToConstant: 120).isActive = true
        let importButton = NSButton(title: "Import…", target: self, action: #selector(importTapped))
        let exportButton = NSButton(title: "Export…", target: self, action: #selector(exportTapped))
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        for button in [preview, importButton, exportButton, save, cancel] { button.bezelStyle = .rounded }

        let buttons = NSStackView(views: [importButton, exportButton, preview, cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [general, separator(), comments, separator(),
                                       delimiters, separator(), keywordStack,
                                       previewHeading, livePreview,
                                       previewLabel, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = FlippedView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            keywordStack.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
        window.contentView = content
        observeFields()
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func populate() {
        nameField.stringValue = definition.name
        extensionsField.stringValue = definition.fileExtensions.joined(separator: " ")
        caseSensitiveBox.state = definition.isCaseSensitive ? .on : .off
        lineCommentField.stringValue = definition.lineCommentTokens.joined(separator: " ")
        blockOpenField.stringValue = definition.blockCommentOpen ?? ""
        blockCloseField.stringValue = definition.blockCommentClose ?? ""
        nestBox.state = definition.blockCommentsNest ? .on : .off
        delimitersField.stringValue = definition.stringDelimiters.joined(separator: " ")
        escapeField.stringValue = definition.escapeCharacterString ?? ""
        operatorsField.stringValue = definition.operatorCharacterString
        foldOpenField.stringValue = definition.foldOpen.joined(separator: " ")
        foldCloseField.stringValue = definition.foldClose.joined(separator: " ")

        let groups = [definition.keywords1, definition.keywords2,
                      definition.keywords3, definition.keywords4]
        for (view, group) in zip(keywordViews, groups) {
            view.string = group.sorted().joined(separator: " ")
        }
    }

    /// Reads the form back into a definition.
    /// Watches every field, so the preview follows the rules as they are typed
    /// rather than waiting for a button.
    private func observeFields() {
        let fields: [NSTextField] = [nameField, extensionsField, lineCommentField,
                                     blockOpenField, blockCloseField, delimitersField,
                                     escapeField, operatorsField, foldOpenField, foldCloseField]
        for field in fields { field.delegate = self }
        for view in keywordViews { view.delegate = self }
        refreshPreview()
    }

    /// Repaints the preview from the rules as they stand.
    func refreshPreview() {
        livePreview.update(with: currentDefinition())
    }

    public func currentDefinition() -> LanguageDefinition {
        func tokens(_ field: NSTextField) -> [String] {
            field.stringValue.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        }
        func keywords(_ index: Int) -> Set<String> {
            Set(keywordViews[index].string
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .map(String.init))
        }

        var built = LanguageDefinition(
            name: nameField.stringValue.trimmingCharacters(in: .whitespaces),
            fileExtensions: tokens(extensionsField).map { $0.lowercased() },
            lineCommentTokens: tokens(lineCommentField),
            blockCommentOpen: blockOpenField.stringValue.isEmpty ? nil : blockOpenField.stringValue,
            blockCommentClose: blockCloseField.stringValue.isEmpty ? nil : blockCloseField.stringValue,
            blockCommentsNest: nestBox.state == .on,
            stringDelimiters: tokens(delimitersField),
            escapeCharacter: escapeField.stringValue.first,
            isCaseSensitive: caseSensitiveBox.state == .on,
            keywords1: keywords(0), keywords2: keywords(1),
            keywords3: keywords(2), keywords4: keywords(3),
            foldOpen: tokens(foldOpenField), foldClose: tokens(foldCloseField)
        )
        if !operatorsField.stringValue.isEmpty {
            built.operatorCharacterString = operatorsField.stringValue
        }
        return built
    }

    /// Lexes a sample with the in-progress definition so the author can see the
    /// effect before saving — the whole point of a GUI over a grammar file.
    @objc private func previewTapped() {
        let sample = previewSample ?? "keyword identifier 42 \"string\" // comment"
        let language = currentDefinition()
        let tokens = Lexer(language: language).tokenize(sample).tokens
        let content = sample as NSString
        let summary = tokens.prefix(12)
            .map { "\($0.type.rawValue):\(content.substring(with: $0.range))" }
            .joined(separator: "  ")
        previewLabel.stringValue = tokens.isEmpty ? "No tokens matched" : summary
    }

    /// Text to lex when previewing; the window controller supplies the active
    /// document so the author tests against real content.
    public var previewSample: String?

    @objc private func importTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let imported = try UDLSerialization.importLanguages(from: url).first else { return }
            definition = imported
            populate()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not import that file"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    @objc private func exportTapped() {
        let language = currentDefinition()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(language.name).xml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? UDLSerialization.exportXML(for: [language])
            .write(to: url, atomically: true, encoding: .utf8)
    }

    /// Why the current definition cannot be saved, or nil if it can.
    ///
    /// Kept separate from the alert so it is testable: a test that drives the
    /// Save button directly would otherwise block on a modal.
    public func validationError() -> String? {
        let language = currentDefinition()
        if language.name.isEmpty { return "The language needs a name." }
        // Shadowing a shipped language would leave no way back to it.
        if BuiltInLanguages.all.contains(where: {
            $0.name.caseInsensitiveCompare(language.name) == .orderedSame
        }) {
            return "“\(language.name)” is a built-in language. Choose a different name so the built-in one stays available."
        }
        return nil
    }

    /// Saves if valid. Returns false when validation failed.
    @discardableResult
    public func save() -> Bool {
        guard validationError() == nil else { return false }
        onSave(currentDefinition())
        return true
    }

    @objc private func saveTapped() {
        if let problem = validationError() {
            let alert = NSAlert()
            alert.messageText = "Cannot save this language"
            alert.informativeText = problem
            alert.runModal()
            return
        }
        save()
        window?.close()
    }

    @objc private func closeTapped() { window?.close() }
}

extension UDLEditorWindowController: NSTextFieldDelegate, NSTextViewDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        refreshPreview()
    }

    public func textDidChange(_ notification: Notification) {
        refreshPreview()
    }
}
