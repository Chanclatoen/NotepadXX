import Foundation

/// Per-document state restored on relaunch.
public struct SessionEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var filePath: String?
    public var untitledName: String
    /// Path of the snapshot holding unsaved content, relative to the backup dir.
    public var backupFileName: String?
    public var selectionLocation: Int
    public var selectionLength: Int
    public var scrollOffset: Double
    public var encodingRawValue: UInt
    public var encodingHasBOM: Bool
    public var lineEndingRawValue: String
    public var isDirty: Bool
    public var isReadOnly: Bool

    public init(
        id: UUID, filePath: String?, untitledName: String, backupFileName: String?,
        selectionLocation: Int = 0, selectionLength: Int = 0, scrollOffset: Double = 0,
        encodingRawValue: UInt, encodingHasBOM: Bool, lineEndingRawValue: String,
        isDirty: Bool, isReadOnly: Bool
    ) {
        self.id = id
        self.filePath = filePath
        self.untitledName = untitledName
        self.backupFileName = backupFileName
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
        self.encodingRawValue = encodingRawValue
        self.encodingHasBOM = encodingHasBOM
        self.lineEndingRawValue = lineEndingRawValue
        self.isDirty = isDirty
        self.isReadOnly = isReadOnly
    }
}

public struct Session: Codable, Equatable, Sendable {
    public var entries: [SessionEntry]
    public var activeIndex: Int
    public init(entries: [SessionEntry] = [], activeIndex: Int = 0) {
        self.entries = entries
        self.activeIndex = activeIndex
    }
}

/// Persists open documents so that quitting — or crashing — never loses work.
///
/// This is the behaviour people cite most often as the reason they trust
/// Notepad++ as a scratchpad: untitled buffers with unsaved text come back
/// exactly as they were, with no "save changes?" prompt. Every dirty buffer,
/// titled or not, gets a full content snapshot written alongside the index.
public final class SessionStore {
    public let directory: URL
    private let indexURL: URL
    private let backupsDirectory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent("session.json")
        self.backupsDirectory = directory.appendingPathComponent("backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    /// Default location: ~/Library/Application Support/NotepadXX
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("NotepadXX", isDirectory: true)
    }

    /// Snapshots documents and writes the index atomically.
    ///
    /// The index is written *after* every snapshot lands, so a crash midway
    /// leaves the previous index intact and pointing at complete snapshots
    /// rather than a half-written one.
    public func save(documents: [TextDocument], activeIndex: Int) throws {
        var entries: [SessionEntry] = []
        var liveBackups: Set<String> = []

        for document in documents {
            var backupName: String?
            // Snapshot anything whose content is not safely on disk already.
            if document.isDirty || document.isUntitled {
                let name = "\(document.id.uuidString).txt"
                let url = backupsDirectory.appendingPathComponent(name)
                try document.text.write(to: url, atomically: true, encoding: .utf8)
                backupName = name
                liveBackups.insert(name)
            }
            entries.append(SessionEntry(
                id: document.id,
                filePath: document.fileURL?.path,
                untitledName: document.untitledName,
                backupFileName: backupName,
                encodingRawValue: document.encoding.encoding.rawValue,
                encodingHasBOM: document.encoding.hasBOM,
                lineEndingRawValue: document.lineEnding.rawValue,
                isDirty: document.isDirty,
                isReadOnly: document.isReadOnly
            ))
        }

        let session = Session(entries: entries, activeIndex: activeIndex)
        let data = try JSONEncoder().encode(session)
        try data.write(to: indexURL, options: .atomic)

        // Drop snapshots for documents that are no longer open or got saved.
        let existing = (try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        for name in existing where !liveBackups.contains(name) {
            try? fileManager.removeItem(at: backupsDirectory.appendingPathComponent(name))
        }
    }

    public func loadSession() -> Session? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    /// Rebuilds documents from the last session.
    ///
    /// A snapshot always wins over the file on disk: it represents unsaved work.
    /// A file that has since been deleted still restores from its snapshot, and a
    /// file whose snapshot is gone restores from disk as a clean document.
    public func restoreDocuments() -> (documents: [TextDocument], activeIndex: Int) {
        guard let session = loadSession() else { return ([], 0) }
        var documents: [TextDocument] = []

        for entry in session.entries {
            let encoding = FileEncoding(
                String.Encoding(rawValue: entry.encodingRawValue),
                hasBOM: entry.encodingHasBOM
            )
            let lineEnding = LineEnding(rawValue: entry.lineEndingRawValue) ?? .platformDefault
            let fileURL = entry.filePath.map { URL(fileURLWithPath: $0) }

            var text: String?
            if let name = entry.backupFileName {
                let url = backupsDirectory.appendingPathComponent(name)
                text = try? String(contentsOf: url, encoding: .utf8)
            }
            if text == nil, let url = fileURL {
                text = (try? TextDocument.load(contentsOf: url))?.text
            }
            guard let restored = text else { continue }

            let document = TextDocument(
                id: entry.id,
                fileURL: fileURL,
                text: restored,
                encoding: encoding,
                lineEnding: lineEnding,
                isDirty: entry.isDirty,
                isReadOnly: entry.isReadOnly
            )
            document.untitledName = entry.untitledName
            documents.append(document)
        }

        let active = min(max(0, session.activeIndex), max(0, documents.count - 1))
        return (documents, active)
    }
}
