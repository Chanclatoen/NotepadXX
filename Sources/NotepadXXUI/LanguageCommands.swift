import AppKit
import NotepadXXCore

/// Language menu: explicit selection plus automatic detection.
extension MainWindowController {

    /// Builds the Language menu from the registry so user-defined languages
    /// appear alongside the built-ins without any extra wiring.
    public static func buildLanguageMenu(registry: LanguageRegistry = .shared) -> NSMenu {
        let menu = NSMenu(title: "Language")
        let none = menu.addItem(withTitle: "Normal Text",
                                action: #selector(MainWindowController.selectLanguageAction(_:)),
                                keyEquivalent: "")
        none.representedObject = ""
        menu.addItem(.separator())
        for language in registry.all {
            let item = menu.addItem(withTitle: language.name,
                                    action: #selector(MainWindowController.selectLanguageAction(_:)),
                                    keyEquivalent: "")
            item.representedObject = language.name
        }
        return menu
    }

    @objc public func selectLanguageAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let name = item.representedObject as? String else { return }
        applyLanguage(named: name.isEmpty ? nil : name)
    }

    public func applyLanguage(named name: String?) {
        guard documents.indices.contains(activeIndex) else { return }
        let language = name.flatMap { LanguageRegistry.shared.language(named: $0) }
        documents[activeIndex].languageName = language?.name
        currentEditor?.setLanguage(language)
        refreshUI()
    }

    /// Chooses a language from the file name, falling back to a shebang.
    public func autoDetectLanguage(for document: TextDocument) {
        let firstLine = document.text.split(separator: "\n", maxSplits: 1,
                                            omittingEmptySubsequences: false).first.map(String.init)
        let detected = LanguageRegistry.shared.detect(
            fileName: document.fileURL?.lastPathComponent, firstLine: firstLine
        )
        document.languageName = detected?.name
    }
}

/// User Defined Language import/export, using the real Notepad++ XML format so
/// the existing community UDL collection loads without conversion.
extension MainWindowController {
    @objc public func importUDLAction(_ sender: Any?) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.xml]
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }

        var imported = 0
        var failures: [String] = []
        for url in picker.urls {
            do {
                for language in try UDLSerialization.importLanguages(from: url) {
                    LanguageRegistry.shared.register(language)
                    imported += 1
                }
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        rebuildLanguageMenu()

        let alert = NSAlert()
        alert.messageText = imported > 0
            ? "Imported \(imported) language\(imported == 1 ? "" : "s")"
            : "Nothing imported"
        if !failures.isEmpty {
            alert.informativeText = "Could not read: " + failures.joined(separator: ", ")
        }
        alert.runModal()
    }

    @objc public func exportUDLAction(_ sender: Any?) {
        guard documents.indices.contains(activeIndex),
              let name = documents[activeIndex].languageName,
              let language = LanguageRegistry.shared.language(named: name) else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(language.name).xml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? UDLSerialization.exportXML(for: [language]).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Rebuilds the Language menu in place after the registry changes.
    func rebuildLanguageMenu() {
        guard let languageItem = NSApp.mainMenu?.items.first(where: { $0.title == "Language" }) else { return }
        languageItem.submenu = MainWindowController.buildLanguageMenu()
    }
}
