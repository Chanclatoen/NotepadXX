import XCTest
@testable import NotepadXXCore

final class CommandLineOptionsTests: XCTestCase {
    private func parse(_ arguments: String...) -> CommandLineOptions {
        CommandLineOptions.parse(["NotepadXX"] + arguments)
    }

    func testPlainFileArguments() {
        let options = parse("a.txt", "b.swift")
        XCTAssertEqual(options.files.map(\.path), ["a.txt", "b.swift"])
        XCTAssertNil(options.files[0].line)
    }

    func testNotepadPlusPlusLineAndColumnSwitches() {
        let options = parse("-n25", "-c4", "file.txt")
        XCTAssertEqual(options.files.first?.line, 25)
        XCTAssertEqual(options.files.first?.column, 4)
    }

    func testColonLocationSyntax() {
        let options = parse("file.txt:25:4")
        XCTAssertEqual(options.files.first?.path, "file.txt")
        XCTAssertEqual(options.files.first?.line, 25)
        XCTAssertEqual(options.files.first?.column, 4)
    }

    func testColonSyntaxWithLineOnly() {
        let options = parse("file.txt:25")
        XCTAssertEqual(options.files.first?.path, "file.txt")
        XCTAssertEqual(options.files.first?.line, 25)
        XCTAssertNil(options.files.first?.column)
    }

    /// A file genuinely containing a colon must not be mangled.
    func testNonNumericColonsAreLeftInThePath() {
        let options = parse("weird:name.txt")
        XCTAssertEqual(options.files.first?.path, "weird:name.txt")
        XCTAssertNil(options.files.first?.line)
    }

    func testAbsolutePathWithLocationKeepsLeadingSlash() {
        let options = parse("/tmp/a/b.txt:10")
        XCTAssertEqual(options.files.first?.path, "/tmp/a/b.txt")
        XCTAssertEqual(options.files.first?.line, 10)
    }

    func testSwitches() {
        let options = parse("-ro", "-nosession", "-multiInst", "x.txt")
        XCTAssertTrue(options.readOnly)
        XCTAssertTrue(options.noSession)
        XCTAssertTrue(options.newInstance)
        XCTAssertEqual(options.files.count, 1)
    }

    func testScreenshotFlagConsumesItsPath() {
        let options = parse("--screenshot", "/tmp/out.png", "file.txt")
        XCTAssertEqual(options.screenshotPath, "/tmp/out.png")
        XCTAssertEqual(options.files.map(\.path), ["file.txt"],
                       "the screenshot path must not be treated as a file to open")
    }

    /// An unrecognised switch must not be opened as a file named "-x".
    func testUnknownSwitchesAreIgnoredNotTreatedAsFiles() {
        let options = parse("--nonsense", "real.txt")
        XCTAssertEqual(options.files.map(\.path), ["real.txt"])
    }

    func testLinePrefixAppliesOnlyToTheNextFile() {
        let options = parse("-n5", "first.txt", "second.txt")
        XCTAssertEqual(options.files[0].line, 5)
        XCTAssertNil(options.files[1].line, "the switch is consumed by the first file")
    }

    func testNoArgumentsYieldsNoFiles() {
        XCTAssertTrue(CommandLineOptions.parse(["NotepadXX"]).files.isEmpty)
    }
}
