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
