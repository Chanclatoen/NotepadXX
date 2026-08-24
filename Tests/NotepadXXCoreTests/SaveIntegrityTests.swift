import XCTest
@testable import NotepadXXCore

/// Losing someone's text is the worst thing an editor can do. These check the
/// paths where it could happen quietly.
final class SaveIntegrityTests: XCTestCase {
    private func temporaryFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-save-\(ProcessInfo.processInfo.globallyUniqueString).txt")
    }

    /// Text that the chosen encoding cannot represent must fail loudly, not
    /// write a file with the characters silently replaced or dropped.
    func testSavingUnrepresentableTextFailsRatherThanLosingIt() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = TextDocument(fileURL: url, text: "plain", encoding: FileEncoding(.ascii))
        document.text = "emoji 😀 and accents café"
        XCTAssertThrowsError(try document.save()) { error in
            guard case TextDocument.SaveError.unencodable = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "a partial file was written for text that cannot be encoded")
        XCTAssertTrue(document.isDirty, "the document must stay dirty when the save failed")
    }

    /// A failed save must not mark the document clean — the user would close it
    /// believing the work was written.
    func testAFailedSaveLeavesTheDocumentDirty() {
        let unwritable = URL(fileURLWithPath: "/System/nope/npxx.txt")
        let document = TextDocument(fileURL: unwritable, text: "work")
        document.text = "edited work"
        XCTAssertTrue(document.isDirty)

        XCTAssertThrowsError(try document.save())
        XCTAssertTrue(document.isDirty, "marked clean despite the write failing")
    }

    /// Text survives a save/load cycle byte for byte, in every shipped encoding
    /// that can represent it.
    func testRoundTripPreservesTextAcrossEncodings() throws {
        let samples: [(FileEncoding, String)] = [
            (FileEncoding(.utf8), "emoji 😀 café 🇳🇱 line\nsecond"),
            (FileEncoding(.utf8, hasBOM: true), "with a BOM 😀\nsecond"),
            (FileEncoding(.utf16LittleEndian, hasBOM: true), "utf16 café 😀"),
            (FileEncoding(.isoLatin1), "latin1 café only"),   // sniffed back as ANSI; see below
        ]

        for (encoding, text) in samples {
            let url = temporaryFile()
            defer { try? FileManager.default.removeItem(at: url) }

            let document = TextDocument(fileURL: url, text: text, encoding: encoding)
            try document.save()

            let reloaded = try TextDocument.load(contentsOf: url)
            XCTAssertEqual(reloaded.text, text,
                           "\(encoding.displayName) did not round-trip")
            // Detection is only asserted where the bytes actually say what the
            // encoding is. ISO Latin 1 and Windows-1252 encode this text to
            // identical bytes with no BOM, so no detector can separate them;
            // Notepad++ falls back to ANSI here too. What must hold either way
            // is that the text came back unchanged, which is asserted above.
            if encoding.encoding != .isoLatin1 {
                XCTAssertEqual(reloaded.encoding.encoding, encoding.encoding,
                               "\(encoding.displayName) was detected as something else")
            }
        }
    }

    /// Line endings are normalised on save and detected on load.
    func testLineEndingsRoundTrip() throws {
        for ending in [LineEnding.lf, .crlf, .cr] {
            let url = temporaryFile()
            defer { try? FileManager.default.removeItem(at: url) }

            let document = TextDocument(fileURL: url, text: "one\ntwo\nthree", lineEnding: ending)
            try document.save()

            let written = try Data(contentsOf: url)
            let text = String(data: written, encoding: .utf8) ?? ""
            XCTAssertTrue(text.contains(ending.rawValue), "\(ending) was not written")

            let reloaded = try TextDocument.load(contentsOf: url)
            XCTAssertEqual(reloaded.lineEnding, ending, "\(ending) was not detected on load")
            XCTAssertEqual(reloaded.text, "one\ntwo\nthree",
                           "text is normalised to LF in memory whatever the file uses")
        }
    }
}
