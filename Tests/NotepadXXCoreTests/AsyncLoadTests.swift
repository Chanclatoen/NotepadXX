import XCTest
@testable import NotepadXXCore

/// The chunked, cancellable read behind opening a large file, and the byte-wise
/// line-ending code it relies on.
final class AsyncLoadTests: XCTestCase {
    private func tempURL(_ name: String = "f.txt") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name)
    }

    // MARK: - Support directory isolation

    func testTestRunsNeverUseTheRealSupportDirectory() throws {
        let real = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ).appendingPathComponent("NotepadXX", isDirectory: true).standardizedFileURL
        let used = try SessionStore.defaultDirectory().standardizedFileURL
        XCTAssertNotEqual(used.path, real.path)
        XCTAssertTrue(used.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path)
                      || used.path.contains("/tmp") || used.path.contains("/var/"),
                      "scratch directory, got \(used.path)")
    }

    func testEnvironmentVariableRedirectsTheSupportDirectory() throws {
        let target = try tempURL("support").deletingLastPathComponent().appendingPathComponent("chosen")
        setenv("NOTEPADXX_SUPPORT_DIR", target.path, 1)
        defer { unsetenv("NOTEPADXX_SUPPORT_DIR") }
        XCTAssertEqual(try SessionStore.defaultDirectory().standardizedFileURL.path,
                       target.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "created on demand")
    }

    // MARK: - Chunked load

    func testLoadsAFileLargerThanOneChunkIntact() throws {
        let url = try tempURL()
        let line = "naïve café ☕ line with ünïcode and ascii 0123456789\n"
        let text = String(repeating: line, count: (TextDocument.readChunkLength * 2 + 1000) / line.utf8.count)
        try Data(text.utf8).write(to: url)

        var fractions: [Double] = []
        let document = try TextDocument.load(contentsOf: url, progress: { fractions.append($0) }, isCancelled: nil)
        XCTAssertEqual(document.text, text)
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertEqual(document.lineEnding, .lf)
        XCTAssertFalse(document.isDirty)
        XCTAssertGreaterThanOrEqual(fractions.count, 3, "reports during the read")
        XCTAssertEqual(fractions, fractions.sorted(), "progress never goes backwards")
        XCTAssertEqual(fractions.last, 1)
    }

    func testCancelStopsTheReadBetweenChunks() throws {
        let url = try tempURL()
        try Data(count: TextDocument.readChunkLength * 3).write(to: url)
        var checks = 0
        XCTAssertThrowsError(try TextDocument.load(contentsOf: url, progress: nil, isCancelled: {
            checks += 1
            return checks > 2
        })) { error in
            XCTAssertEqual(error as? TextDocument.LoadError, .cancelled)
        }
        XCTAssertGreaterThan(checks, 1, "asked more than once, so it is checked while reading")
    }

    func testCancelledBeforeStartThrowsCancelled() throws {
        let url = try tempURL()
        try Data("hi".utf8).write(to: url)
        XCTAssertThrowsError(try TextDocument.load(contentsOf: url, progress: nil, isCancelled: { true })) {
            XCTAssertEqual($0 as? TextDocument.LoadError, .cancelled)
        }
    }

    func testMissingFileIsAnUnreadableError() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("npxx-missing-\(UUID().uuidString)")
        XCTAssertThrowsError(try TextDocument.load(contentsOf: url, progress: nil, isCancelled: nil)) { error in
            guard case TextDocument.LoadError.unreadable = error else { return XCTFail("got \(error)") }
        }
    }

    func testEncodingDetectionIsUnchangedByTheChunkedRead() throws {
        let cases: [(String, Data, FileEncoding, String)] = [
            ("utf8", Data("héllo\n".utf8), .utf8, "héllo\n"),
            ("bom", Data([0xEF, 0xBB, 0xBF]) + Data("héllo\n".utf8), .utf8BOM, "héllo\n"),
            ("utf16le", Data([0xFF, 0xFE]) + "héllo\n".data(using: .utf16LittleEndian)!, .utf16LE, "héllo\n"),
            ("utf16be", Data([0xFE, 0xFF]) + "héllo\n".data(using: .utf16BigEndian)!, .utf16BE, "héllo\n"),
            ("ansi", Data([0x68, 0xE9, 0x6C, 0x6C, 0x6F, 0x0A]), .ansi, "héllo\n"),
        ]
        for (name, bytes, encoding, expected) in cases {
            let url = try tempURL("\(name).txt")
            try bytes.write(to: url)
            let chunked = try TextDocument.load(contentsOf: url, progress: { _ in }, isCancelled: { false })
            let plain = try TextDocument.load(contentsOf: url)
            XCTAssertEqual(chunked.encoding, encoding, name)
            XCTAssertEqual(chunked.text, expected, name)
            XCTAssertEqual(chunked.encoding, plain.encoding, name)
            XCTAssertEqual(chunked.text, plain.text, name)
        }
    }

    func testCRLFFileIsNormalisedAndRemembered() throws {
        let url = try tempURL()
        try Data("one\r\ntwo\r\nthree".utf8).write(to: url)
        let document = try TextDocument.load(contentsOf: url, progress: nil, isCancelled: nil)
        XCTAssertEqual(document.text, "one\ntwo\nthree")
        XCTAssertEqual(document.lineEnding, .crlf)
    }

    func testSaveRoundTripKeepsBytes() throws {
        let url = try tempURL()
        let original = Data("a\r\nb\r\n\u{FEFF}ünï\r\n".utf8)
        try original.write(to: url)
        let document = try TextDocument.load(contentsOf: url, progress: nil, isCancelled: nil)
        try document.save()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    // MARK: - Byte-wise line endings agree with the scalar definition

    private func referenceNormalize(_ string: String, to target: LineEnding) -> String {
        var out = String()
        var iterator = string.unicodeScalars.makeIterator()
        var pending = iterator.next()
        while let scalar = pending {
            if scalar == "\r" {
                let next = iterator.next()
                out += target.rawValue
                pending = (next == "\n") ? iterator.next() : next
            } else if scalar == "\n" {
                out += target.rawValue
                pending = iterator.next()
            } else {
                out.unicodeScalars.append(scalar)
                pending = iterator.next()
            }
        }
        return out
    }

    private func referenceCounts(_ string: String) -> (Int, Int, Int) {
        var lf = 0, crlf = 0, cr = 0
        var iterator = string.unicodeScalars.makeIterator()
        var pending = iterator.next()
        while let scalar = pending {
            if scalar == "\r" {
                let next = iterator.next()
                if next == "\n" { crlf += 1; pending = iterator.next() } else { cr += 1; pending = next }
            } else {
                if scalar == "\n" { lf += 1 }
                pending = iterator.next()
            }
        }
        return (lf, crlf, cr)
    }

    func testByteWiseLineEndingsMatchTheScalarReference() {
        var generator = SystemRandomNumberGenerator()
        let alphabet: [String] = ["a", "é", "☕", "😀", "\r", "\n", "\r\n", "\n\r", "x", " "]
        for _ in 0..<500 {
            let length = Int.random(in: 0...40, using: &generator)
            let text = (0..<length).map { _ in alphabet.randomElement(using: &generator)! }.joined()
            let counts = LineEnding.counts(in: text)
            let expected = referenceCounts(text)
            XCTAssertEqual([counts.lf, counts.crlf, counts.cr], [expected.0, expected.1, expected.2], text.debugDescription)
            for target in LineEnding.allCases {
                XCTAssertEqual(LineEnding.normalize(text, to: target), referenceNormalize(text, to: target),
                               "\(target) \(text.debugDescription)")
            }
        }
    }

    func testNormaliseOfBridgedStringStillWorks() {
        let bridged = NSMutableString(string: "a\r\nb\rc\nd") as String
        XCTAssertEqual(LineEnding.normalize(bridged, to: .lf), "a\nb\nc\nd")
        XCTAssertEqual(LineEnding.normalize(bridged, to: .crlf), "a\r\nb\r\nc\r\nd")
    }
}
