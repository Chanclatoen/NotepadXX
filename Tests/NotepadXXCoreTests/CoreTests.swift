import XCTest
@testable import NotepadXXCore

final class LineEndingTests: XCTestCase {
    func testCountsDoNotDoubleCountCRLF() {
        let c = LineEnding.counts(in: "a\r\nb\r\nc")
        XCTAssertEqual(c.crlf, 2)
        XCTAssertEqual(c.lf, 0, "LF inside CRLF must not be counted separately")
        XCTAssertEqual(c.cr, 0, "CR inside CRLF must not be counted separately")
    }

    func testDetectsDominantEnding() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc\nd"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\nb\nc\r\nd"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\rb\rc"), .cr)
        XCTAssertNil(LineEnding.detect(in: "no terminators"))
    }

    func testMixedDetection() {
        XCTAssertTrue(LineEnding.isMixed(in: "a\r\nb\nc"))
        XCTAssertFalse(LineEnding.isMixed(in: "a\nb\nc"))
    }

    func testNormalizeCollapsesMixedInput() {
        XCTAssertEqual(LineEnding.normalize("a\r\nb\nc\rd", to: .lf), "a\nb\nc\nd")
        XCTAssertEqual(LineEnding.normalize("a\nb", to: .crlf), "a\r\nb")
        XCTAssertEqual(LineEnding.normalize("a\r\nb", to: .cr), "a\rb")
    }

    func testNormalizeIsIdempotent() {
        let once = LineEnding.normalize("a\r\nb\rc\nd", to: .crlf)
        XCTAssertEqual(LineEnding.normalize(once, to: .crlf), once)
    }

    func testTrailingCarriageReturnAtEndOfString() {
        XCTAssertEqual(LineEnding.counts(in: "a\r").cr, 1)
        XCTAssertEqual(LineEnding.normalize("a\r", to: .lf), "a\n")
    }
}

final class FileEncodingTests: XCTestCase {
    func testDetectsBOMs() {
        XCTAssertEqual(EncodingDetector.detect(data: Data([0xEF, 0xBB, 0xBF, 0x41])), .utf8BOM)
        XCTAssertEqual(EncodingDetector.detect(data: Data([0xFF, 0xFE, 0x41, 0x00])), .utf16LE)
        XCTAssertEqual(EncodingDetector.detect(data: Data([0xFE, 0xFF, 0x00, 0x41])), .utf16BE)
    }

    func testDetectsPlainUTF8AndFallsBackToANSI() {
        XCTAssertEqual(EncodingDetector.detect(data: Data("héllo".utf8)), .utf8)
        // 0x93 is a valid Windows-1252 byte but not valid standalone UTF-8.
        XCTAssertEqual(EncodingDetector.detect(data: Data([0x41, 0x93, 0x42])), .ansi)
    }

    func testBOMRoundTripStripsAndRestores() {
        let encoded = EncodingDetector.encode(string: "hi", as: .utf8BOM)!
        XCTAssertEqual(Array(encoded.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(EncodingDetector.decode(data: encoded, as: .utf8BOM), "hi")
    }
}

final class TextDocumentTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLoadNormalizesToLFButRemembersOriginalEnding() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("crlf.txt")
        try Data("alpha\r\nbeta\r\n".utf8).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        XCTAssertEqual(document.text, "alpha\nbeta\n", "in-memory text is always LF")
        XCTAssertEqual(document.lineEnding, .crlf, "original terminator is remembered")
        XCTAssertFalse(document.isDirty)
    }

    func testSaveRestoresOriginalLineEndingBytes() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("crlf.txt")
        try Data("alpha\r\nbeta\r\n".utf8).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        document.text = "alpha\nbeta\ngamma\n"
        try document.save()

        let written = try Data(contentsOf: url)
        XCTAssertEqual(String(data: written, encoding: .utf8), "alpha\r\nbeta\r\ngamma\r\n")
        XCTAssertFalse(document.isDirty, "saving clears the dirty flag")
    }

    func testEOLConversionChangesBytesOnDisk() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("f.txt")
        try Data("a\r\nb\r\n".utf8).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        document.lineEnding = .lf
        try document.save()
        XCTAssertEqual(String(data: try Data(contentsOf: url), encoding: .utf8), "a\nb\n")
    }

    func testEditingMarksDirtyAndSameValueDoesNot() throws {
        let document = TextDocument(text: "hello")
        XCTAssertFalse(document.isDirty)
        document.text = "hello"
        XCTAssertFalse(document.isDirty, "assigning an identical value is not an edit")
        document.text = "hello world"
        XCTAssertTrue(document.isDirty)
    }

    func testConvertToEncodingMarksDirtyWithoutChangingText() {
        let document = TextDocument(text: "hi", encoding: .utf8)
        document.convert(to: .utf8BOM)
        XCTAssertEqual(document.encoding, .utf8BOM)
        XCTAssertEqual(document.text, "hi", "convert changes bytes, not characters")
        XCTAssertTrue(document.isDirty)
    }

    func testReinterpretChangesCharactersFromSameBytes() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("mojibake.txt")
        // 0xC3 0xA9 is "é" in UTF-8 and "Ã©" in Windows-1252 — decodable as
        // both, which is exactly what "Encode in <x>" is for.
        try Data([0xC3, 0xA9]).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertEqual(document.text, "é")

        try document.reinterpret(as: .ansi)
        XCTAssertEqual(document.encoding, .ansi)
        XCTAssertEqual(document.text, "Ã©", "same bytes, different characters")
        XCTAssertFalse(document.isDirty, "reinterpreting does not modify the file")
    }

    func testReinterpretRejectsBytesInvalidForTargetEncoding() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("invalid.txt")
        // 0x93 is a lone Windows-1252 byte that is not valid UTF-8.
        try Data([0x41, 0x93, 0x42]).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        XCTAssertThrowsError(try document.reinterpret(as: .utf8)) { error in
            XCTAssertEqual(error as? TextDocument.LoadError, .undecodable("UTF-8"))
        }
        XCTAssertEqual(document.encoding, .ansi, "a failed reinterpret leaves the document untouched")
    }

    func testDetectsOnDiskModification() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("watch.txt")
        try Data("one".utf8).write(to: url)

        let document = try TextDocument.load(contentsOf: url)
        XCTAssertFalse(document.hasChangedOnDisk())

        // Filesystem timestamps are coarse; push it clearly into the future.
        try Data("two".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path
        )
        XCTAssertTrue(document.hasChangedOnDisk())
    }
}

final class JoinLinesTests: XCTestCase {
    /// Scintilla's SCI_LINESJOIN, which Notepad++ uses, inserts a space where
    /// one is not already present. Plain concatenation runs words together.
    func testJoinInsertsASpaceBetweenWords() {
        XCTAssertEqual(LineOperations.joinLines("a\nb\nc\n", range: 0...2), "a b c\n")
    }

    func testJoinDoesNotDoubleAnExistingSpace() {
        XCTAssertEqual(LineOperations.joinLines("a \nb\n", range: 0...1), "a b\n")
        XCTAssertEqual(LineOperations.joinLines("a\n b\n", range: 0...1), "a b\n")
    }

    /// An empty line contributes no text, but the surviving boundary between
    /// the words either side still needs its separating space.
    func testJoinAcrossAnEmptyLineStillSeparatesTheWords() {
        XCTAssertEqual(LineOperations.joinLines("a\n\nb\n", range: 0...2), "a b\n")
    }

    func testJoiningASingleLineIsANoOp() {
        XCTAssertEqual(LineOperations.joinLines("a\nb\n", range: 0...0), "a\nb\n")
    }
}
