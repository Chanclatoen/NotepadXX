import XCTest
@testable import NotepadXXCore

/// Seventeen of fifty preferences were once stored, shown in the Preferences
/// window, and read by no code at all. Nothing in the type system stops that
/// happening again, so this checks the sources directly: every preference must
/// be read somewhere other than the model and the window that lists it.
final class PreferenceWiringTests: XCTestCase {
    /// The package root, found from this file's own path.
    private func sourcesDirectory() throws -> URL {
        // …/Tests/NotepadXXCoreTests/ThisFile.swift → the package root.
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let sources = directory.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "sources are not available in this run")
        return sources
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testEveryPreferenceIsReadSomewhere() throws {
        let sources = try sourcesDirectory()
        let modelURL = sources.appendingPathComponent("NotepadXXCore/Preferences.swift")
        let model = try String(contentsOf: modelURL, encoding: .utf8)

        // The declared property names, in declaration order.
        let names = model.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("public var ") else { return nil }
            return trimmed.dropFirst("public var ".count)
                .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                .description
        }
        XCTAssertGreaterThan(names.count, 30, "the model was not parsed")

        // Where a setting may only be declared or listed, never read.
        let ignored = ["Preferences.swift", "PreferencesWindow.swift"]
        let corpus = swiftFiles(in: sources)
            .filter { !ignored.contains($0.lastPathComponent) }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        let unread = names.filter { name in
            // Match the property as a whole word, so "wordWrap" is not found
            // inside "wordWrapSomethingElse".
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(corpus.startIndex..., in: corpus)
            return regex.firstMatch(in: corpus, range: range) == nil
        }

        XCTAssertTrue(unread.isEmpty, """
            These preferences are stored and shown but nothing reads them, so \
            changing them does nothing: \(unread.joined(separator: ", "))
            """)
    }
}
