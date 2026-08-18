import Foundation

/// One open buffer. May be backed by a file on disk, or be an untitled scratch
/// buffer that has never been saved — Notepad++ treats both as first-class and
/// persists them across quit, which is why `text` is always retained in full.
public final class TextDocument: Identifiable, @unchecked Sendable {
    public let id: UUID
    public private(set) var fileURL: URL?
    public var text: String { didSet { if text != oldValue { isDirty = true } } }
    public var encoding: FileEncoding
    public var lineEnding: LineEnding
    public private(set) var isDirty: Bool
    /// Notepad++ lets a tab be marked read-only independently of file permissions.
    public var isReadOnly: Bool
    /// Selected syntax language, or nil for plain text. Persisted in the session.
    public var languageName: String?
    /// Modification date observed at load/save, used for on-disk change detection.
    public private(set) var lastKnownModification: Date?

    public init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        text: String = "",
        encoding: FileEncoding = .utf8,
        lineEnding: LineEnding = .platformDefault,
        isDirty: Bool = false,
        isReadOnly: Bool = false,
        lastKnownModification: Date? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.text = text
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.isDirty = isDirty
        self.isReadOnly = isReadOnly
        self.lastKnownModification = lastKnownModification
    }

    /// Tab title. Untitled buffers get Notepad++'s "new N" naming.
    public var displayName: String {
        fileURL?.lastPathComponent ?? untitledName
    }
    public var untitledName: String = "new 1"
    public var isUntitled: Bool { fileURL == nil }

    // MARK: - Loading and saving

    public enum LoadError: Error, Equatable {
        case unreadable(String)
        case undecodable(String)
    }

    /// Reads a file, detecting encoding and line ending. The in-memory text is
    /// always normalised to LF; the original terminator is remembered in
    /// `lineEnding` and re-applied on save. This keeps every offset-based
    /// operation (search, selection, column mode) free of CRLF special-casing.
    public static func load(contentsOf url: URL) throws -> TextDocument {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LoadError.unreadable(error.localizedDescription) }

        let encoding = EncodingDetector.detect(data: data)
        guard let raw = EncodingDetector.decode(data: data, as: encoding) else {
            throw LoadError.undecodable(url.lastPathComponent)
        }
        let ending = LineEnding.detect(in: raw) ?? .platformDefault
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)

        return TextDocument(
            fileURL: url,
            text: LineEnding.normalize(raw, to: .lf),
            encoding: encoding,
            lineEnding: ending,
            isDirty: false,
            lastKnownModification: attributes?[.modificationDate] as? Date
        )
    }

    public enum SaveError: Error, Equatable {
        case noDestination
        case unencodable(String)
        case unwritable(String)
    }

    /// Writes to `url` (or the document's own URL), re-applying `lineEnding`.
    public func save(to url: URL? = nil) throws {
        guard let destination = url ?? fileURL else { throw SaveError.noDestination }
        let output = LineEnding.normalize(text, to: lineEnding)
        guard let data = EncodingDetector.encode(string: output, as: encoding) else {
            throw SaveError.unencodable(encoding.displayName)
        }
        do { try data.write(to: destination, options: .atomic) }
        catch { throw SaveError.unwritable(error.localizedDescription) }

        fileURL = destination
        isDirty = false
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        lastKnownModification = attributes?[.modificationDate] as? Date
    }

    /// True when the file changed on disk since we last read or wrote it —
    /// drives Notepad++'s file-status auto-detection (reload/prompt).
    public func hasChangedOnDisk() -> Bool {
        guard let url = fileURL, let known = lastKnownModification else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let current = attributes[.modificationDate] as? Date else { return false }
        return current > known
    }

    // MARK: - Encoding commands

    /// Notepad++ "Convert to <encoding>": keep the characters, change the bytes
    /// written on save. Marks the document dirty because the file will differ.
    public func convert(to newEncoding: FileEncoding) {
        guard newEncoding != encoding else { return }
        encoding = newEncoding
        isDirty = true
    }

    /// Notepad++ "Encode in <encoding>": reinterpret the *existing bytes* under a
    /// different encoding, which changes the visible characters. Only meaningful
    /// for a file-backed document, since it re-reads from disk.
    public func reinterpret(as newEncoding: FileEncoding) throws {
        guard let url = fileURL else { throw LoadError.unreadable("untitled document") }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw LoadError.unreadable(error.localizedDescription) }
        guard let raw = EncodingDetector.decode(data: data, as: newEncoding) else {
            throw LoadError.undecodable(newEncoding.displayName)
        }
        encoding = newEncoding
        text = LineEnding.normalize(raw, to: .lf)
        isDirty = false
    }

    public func markClean() { isDirty = false }

    /// Marks the document as needing a save without altering `text` — used by
    /// commands that change how bytes are written (encoding, line endings).
    public func markDirty() { isDirty = true }
}
