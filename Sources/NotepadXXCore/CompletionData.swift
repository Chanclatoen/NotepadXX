import Foundation

/// Per-language completion entries: API names with their signatures, matching
/// Notepad++'s XML autoCompletion files.
///
/// The shipped set is deliberately small — it exists so call tips have real
/// signatures to show, and so a user can extend a language by dropping in a
/// file rather than waiting for us to ship one.
public struct CompletionEntry: Codable, Equatable, Sendable {
    public var name: String
    /// Shown as the call tip, e.g. "printf(format, ...)".
    public var signature: String?
    public var detail: String?

    public init(name: String, signature: String? = nil, detail: String? = nil) {
        self.name = name
        self.signature = signature
        self.detail = detail
    }
}

public struct LanguageCompletionData: Codable, Equatable, Sendable {
    public var languageName: String
    public var entries: [CompletionEntry]

    public init(languageName: String, entries: [CompletionEntry]) {
        self.languageName = languageName
        self.entries = entries
    }
}

/// Loads completion data: the shipped defaults, plus anything the user has
/// dropped into the autoCompletion folder.
public final class CompletionDataStore {
    private let directory: URL
    private var userData: [String: LanguageCompletionData] = [:]

    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("autoCompletion", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    public func reload() {
        userData.removeAll()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(LanguageCompletionData.self, from: data)
            else { continue }
            userData[decoded.languageName.lowercased()] = decoded
        }
    }

    /// User data replaces the shipped set for that language, so a user can
    /// correct a bad built-in rather than being stuck with it.
    public func entries(forLanguage name: String?) -> [CompletionEntry] {
        guard let name else { return [] }
        if let user = userData[name.lowercased()] { return user.entries }
        return BuiltInCompletionData.entries(forLanguage: name)
    }

    public func save(_ data: LanguageCompletionData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let safe = data.languageName.replacingOccurrences(of: "/", with: "-")
        try encoder.encode(data).write(
            to: directory.appendingPathComponent("\(safe).json"), options: .atomic
        )
        reload()
    }
}

public enum BuiltInCompletionData {
    public static func entries(forLanguage name: String) -> [CompletionEntry] {
        switch name.lowercased() {
        case "c":
            return [
                CompletionEntry(name: "printf", signature: "int printf(const char *format, ...)"),
                CompletionEntry(name: "scanf", signature: "int scanf(const char *format, ...)"),
                CompletionEntry(name: "malloc", signature: "void *malloc(size_t size)"),
                CompletionEntry(name: "free", signature: "void free(void *ptr)"),
                CompletionEntry(name: "memcpy", signature: "void *memcpy(void *dest, const void *src, size_t n)"),
                CompletionEntry(name: "strlen", signature: "size_t strlen(const char *s)"),
                CompletionEntry(name: "strcmp", signature: "int strcmp(const char *a, const char *b)"),
                CompletionEntry(name: "fopen", signature: "FILE *fopen(const char *path, const char *mode)"),
                CompletionEntry(name: "fclose", signature: "int fclose(FILE *stream)"),
            ]
        case "python":
            return [
                CompletionEntry(name: "print", signature: "print(*values, sep=' ', end='\\n')"),
                CompletionEntry(name: "len", signature: "len(obj) -> int"),
                CompletionEntry(name: "range", signature: "range(start, stop[, step])"),
                CompletionEntry(name: "open", signature: "open(file, mode='r', encoding=None)"),
                CompletionEntry(name: "enumerate", signature: "enumerate(iterable, start=0)"),
                CompletionEntry(name: "zip", signature: "zip(*iterables)"),
                CompletionEntry(name: "sorted", signature: "sorted(iterable, key=None, reverse=False)"),
                CompletionEntry(name: "isinstance", signature: "isinstance(obj, class_or_tuple) -> bool"),
            ]
        case "javascript", "typescript":
            return [
                CompletionEntry(name: "parseInt", signature: "parseInt(string, radix?) -> number"),
                CompletionEntry(name: "parseFloat", signature: "parseFloat(string) -> number"),
                CompletionEntry(name: "setTimeout", signature: "setTimeout(callback, delayMs, ...args)"),
                CompletionEntry(name: "setInterval", signature: "setInterval(callback, delayMs, ...args)"),
                CompletionEntry(name: "JSON.stringify", signature: "JSON.stringify(value, replacer?, space?)"),
                CompletionEntry(name: "JSON.parse", signature: "JSON.parse(text, reviver?)"),
                CompletionEntry(name: "Array.isArray", signature: "Array.isArray(value) -> boolean"),
                CompletionEntry(name: "Object.keys", signature: "Object.keys(obj) -> string[]"),
            ]
        case "swift":
            return [
                CompletionEntry(name: "print", signature: "print(_ items: Any..., separator: String, terminator: String)"),
                CompletionEntry(name: "map", signature: "map(_ transform: (Element) -> T) -> [T]"),
                CompletionEntry(name: "filter", signature: "filter(_ isIncluded: (Element) -> Bool) -> [Element]"),
                CompletionEntry(name: "reduce", signature: "reduce(_ initial: T, _ next: (T, Element) -> T) -> T"),
                CompletionEntry(name: "compactMap", signature: "compactMap(_ transform: (Element) -> T?) -> [T]"),
                CompletionEntry(name: "sorted", signature: "sorted(by: (Element, Element) -> Bool) -> [Element]"),
            ]
        case "shell":
            return [
                CompletionEntry(name: "echo", signature: "echo [-neE] [arg ...]"),
                CompletionEntry(name: "grep", signature: "grep [options] pattern [file ...]"),
                CompletionEntry(name: "sed", signature: "sed [-n] script [file ...]"),
                CompletionEntry(name: "awk", signature: "awk [-F sep] 'program' [file ...]"),
                CompletionEntry(name: "find", signature: "find [path ...] [expression]"),
                CompletionEntry(name: "curl", signature: "curl [options] <url>"),
            ]
        case "sql":
            return [
                CompletionEntry(name: "SELECT", signature: "SELECT columns FROM table [WHERE ...]"),
                CompletionEntry(name: "INSERT", signature: "INSERT INTO table (columns) VALUES (...)"),
                CompletionEntry(name: "UPDATE", signature: "UPDATE table SET column = value [WHERE ...]"),
                CompletionEntry(name: "DELETE", signature: "DELETE FROM table [WHERE ...]"),
                CompletionEntry(name: "JOIN", signature: "JOIN table ON condition"),
            ]
        default:
            return []
        }
    }

    public static var supportedLanguages: [String] {
        ["C", "Python", "JavaScript", "TypeScript", "Swift", "Shell", "SQL"]
    }
}
