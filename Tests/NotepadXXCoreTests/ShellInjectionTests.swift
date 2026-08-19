import XCTest
@testable import NotepadXXCore

/// The Run menu hands its command to a shell, so every substituted value is
/// potential code. File names containing shell metacharacters are legal on
/// macOS and arrive with cloned repositories and unzipped archives.
final class ShellInjectionTests: XCTestCase {
    private func expand(_ command: String, path: String) -> String {
        let context = RunContext.forDocument(path: path, line: 1, column: 1)
        return RunCommandExpander.expand(command, with: context)
    }

    /// The case that made this a bug, proved the only way worth trusting: run
    /// the expanded command through a real shell and check the injected part
    /// did not execute.
    func testAHostileFileNameCannotRunASecondCommand() throws {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-injection-\(ProcessInfo.processInfo.globallyUniqueString)")
        try? FileManager.default.removeItem(at: marker)

        // A legal macOS file name that used to end the command and start another.
        let hostile = "/tmp/notes; touch \(marker.path) #.txt"
        let expanded = expand("echo scanning $(FULL_CURRENT_PATH)", path: hostile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", expanded]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path),
                       "the injected command ran: \(expanded)")
        try? FileManager.default.removeItem(at: marker)
    }

    func testCommandSubstitutionInAFileNameIsInert() {
        for hostile in ["/tmp/$(whoami).txt", "/tmp/`whoami`.txt", "/tmp/a|b.txt",
                        "/tmp/a&&b.txt", "/tmp/a>out.txt", "/tmp/a\nb.txt"] {
            let expanded = expand("wc -l $(FULL_CURRENT_PATH)", path: hostile)
            XCTAssertTrue(expanded.hasPrefix("wc -l '"), "unquoted: \(expanded)")
            XCTAssertTrue(expanded.hasSuffix("'"), "unterminated quote: \(expanded)")
        }
    }

    /// A quote in the name must not close the quoting and escape the value.
    func testASingleQuoteInAFileNameCannotBreakOut() {
        let expanded = expand("cat $(FULL_CURRENT_PATH)", path: "/tmp/it's; rm -rf ~.txt")
        // The dangerous reading is a bare `; rm` sitting outside any quotes.
        XCTAssertFalse(expanded.contains("' ; rm"), "got: \(expanded)")
        XCTAssertTrue(expanded.contains("'\\''"), "the quote is escaped, got: \(expanded)")
    }

    /// Quoting must not break the ordinary case.
    func testAnOrdinaryPathStillExpandsUsefully() {
        let expanded = expand("python3 $(FULL_CURRENT_PATH)", path: "/tmp/script.py")
        XCTAssertEqual(expanded, "python3 '/tmp/script.py'")
    }

    /// Substituting inside a word still produces one word, because adjacent
    /// quoted and unquoted text joins in a shell.
    func testSubstitutionInsideAWordStillJoins() {
        let expanded = expand("echo prefix-$(FILE_NAME)", path: "/tmp/notes.txt")
        XCTAssertEqual(expanded, "echo prefix-'notes.txt'")
    }

    /// The quoting helper itself, on the cases that matter.
    func testQuotingRules() {
        XCTAssertEqual(ShellQuoting.quoted("plain"), "'plain'")
        XCTAssertEqual(ShellQuoting.quoted("with space"), "'with space'")
        XCTAssertEqual(ShellQuoting.quoted("it's"), "'it'\\''s'")
        XCTAssertEqual(ShellQuoting.quoted(""), "''")
    }
}
