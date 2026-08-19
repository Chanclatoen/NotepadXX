import Foundation

/// Application preferences, mirroring the pages of Notepad++'s Preferences
/// dialog. Codable so the whole set round-trips to disk as one document, which
/// makes "export settings" and "reset to defaults" trivial.
public struct Preferences: Codable, Equatable, Sendable {

    // MARK: - General
    public var showToolbar: Bool = true
    public var showStatusBar: Bool = true
    public var showTabBar: Bool = true
    /// Tab strip arrangement: "horizontal", "wrapped" or "vertical".
    /// A single value rather than two booleans that can disagree.
    public var tabLayoutRawValue: String = "horizontal"
    /// Which mode the one search panel was last left in.
    public var searchPanelModeRawValue: Int = 0
    public var tabCloseButtonOnEachTab: Bool = true
    public var confirmCloseUnsaved: Bool = false   // Notepad++ scratchpad behaviour

    // MARK: - Editing
    public var showLineNumbers: Bool = true
    public var showBookmarkMargin: Bool = true
    public var showChangeHistoryMargin: Bool = true
    public var highlightCurrentLine: Bool = true
    public var showIndentGuides: Bool = true
    public var showWhitespace: Bool = false
    public var showEndOfLine: Bool = false
    public var showWrapSymbol: Bool = false
    public var wordWrap: Bool = false
    public var smartHighlight: Bool = true
    public var braceMatching: Bool = true
    public var clickableURLs: Bool = true
    public var caretBlinks: Bool = true
    public var caretWidth: Int = 1
    public var edgeColumn: Int = 0          // 0 disables the vertical edge guide
    public var scrollBeyondLastLine: Bool = false
    /// Lines kept visible above and below the caret while scrolling.
    public var caretScrollMargin: Int = 0
    public var copyWholeLineWhenNothingSelected: Bool = true

    // MARK: - Indentation
    public var tabWidth: Int = 4
    public var replaceTabsBySpaces: Bool = false
    public var autoIndent: Bool = true
    public var trimTrailingWhitespaceOnPaste: Bool = false

    // MARK: - New document defaults
    public var defaultEncodingRawValue: UInt = String.Encoding.utf8.rawValue
    public var defaultEncodingHasBOM: Bool = false
    public var defaultLineEndingRawValue: String = "\n"
    public var defaultLanguageName: String?

    // MARK: - Backup and session
    public var rememberSession: Bool = true
    public var periodicBackup: Bool = true
    public var backupIntervalSeconds: Int = 5
    public var backupDirectory: String?

    // MARK: - File status
    public var detectFileChanges: Bool = true
    /// Files larger than this open view-only. 0 disables the limit.
    public var readOnlyAboveMegabytes: Int = 0
    public var reloadChangedFilesSilently: Bool = false

    // MARK: - Recent files
    public var recentFilesLimit: Int = 15
    public var recentFilesShowFullPath: Bool = false

    // MARK: - Auto-completion
    public var autoCompletionEnabled: Bool = true
    public var autoCompletionFromWords: Bool = true
    public var autoCompletionFromKeywords: Bool = true
    public var autoCompletionMinimumCharacters: Int = 3
    public var showCallTips: Bool = true
    public var pathCompletion: Bool = true
    public var closeBracketsAndQuotes: Bool = true
    public var closeTags: Bool = true

    // MARK: - Searching
    public var searchWrapAround: Bool = true
    public var searchDefaultModeRawValue: String = "normal"
    public var findDialogStaysOpen: Bool = true

    // MARK: - Appearance
    public var fontName: String = "SF Mono"
    public var fontSize: Double = 12
    /// "System" follows the appearance the Mac is in, so the editor and the
    /// window chrome are never light and dark at the same time.
    public var themeName: String = "System"

    public init() {}

    /// Clamps values that would break the editor if a hand-edited file supplied
    /// something nonsensical.
    public mutating func sanitize() {
        tabWidth = min(max(1, tabWidth), 16)
        fontSize = min(max(6, fontSize), 96)
        recentFilesLimit = min(max(0, recentFilesLimit), 50)
        backupIntervalSeconds = min(max(1, backupIntervalSeconds), 600)
        autoCompletionMinimumCharacters = min(max(1, autoCompletionMinimumCharacters), 10)
        caretWidth = min(max(1, caretWidth), 5)
        caretScrollMargin = min(max(0, caretScrollMargin), 40)
        readOnlyAboveMegabytes = min(max(0, readOnlyAboveMegabytes), 4096)
        edgeColumn = max(0, edgeColumn)
    }
}

/// Loads and saves `Preferences` as JSON.
///
/// Decoding is tolerant: a file written by an older build that lacks newer keys
/// still loads. Swift's synthesized `Decodable` does *not* fall back to property
/// defaults for absent keys -- it throws -- so incoming JSON is merged over the
/// encoded defaults before decoding. A corrupt file falls back to defaults
/// rather than refusing to launch.
public final class PreferencesStore {
    private let url: URL
    public private(set) var preferences: Preferences

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("preferences.json")
        self.preferences = Preferences()
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard var decoded = try? Self.decodeMergingDefaults(data) else {
            // Keep defaults rather than failing to start on a corrupt file.
            return
        }
        decoded.sanitize()
        preferences = decoded
    }

    /// Decodes `data` on top of the default values, so any key the file omits
    /// keeps its default instead of failing the whole decode.
    static func decodeMergingDefaults(_ data: Data) throws -> Preferences {
        let encodedDefaults = try JSONEncoder().encode(Preferences())
        guard let defaults = try JSONSerialization.jsonObject(with: encodedDefaults) as? [String: Any],
              let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "preferences must be a JSON object")
            )
        }
        let merged = defaults.merging(incoming) { _, new in new }
        return try JSONDecoder().decode(
            Preferences.self, from: try JSONSerialization.data(withJSONObject: merged)
        )
    }

    public func save() throws {
        var copy = preferences
        copy.sanitize()
        preferences = copy
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(copy).write(to: url, options: .atomic)
    }

    public func update(_ mutate: (inout Preferences) -> Void) throws {
        mutate(&preferences)
        try save()
    }

    public func resetToDefaults() throws {
        preferences = Preferences()
        try save()
    }

    /// Exports the current settings, for Notepad++-style config portability.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preferences)
    }

    public func importJSON(_ data: Data) throws {
        var decoded = try Self.decodeMergingDefaults(data)
        decoded.sanitize()
        preferences = decoded
        try save()
    }
}
