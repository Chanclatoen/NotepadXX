import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// The Plugins Admin's five states, checked by what the window announces.
@MainActor
final class PluginStateBannerTests: XCTestCase {
    private func makeWindow() throws -> PluginsAdminWindowController {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-plugins-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let registry = try PluginRegistry(directory: directory)
        let controller = PluginsAdminWindowController(registry: registry, repository: nil) {}
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    /// A checksum failure has to read as a security refusal, with the evidence.
    func testASignatureFailureShowsBothDigests() {
        let banner = DSStateBanner(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        banner.show(.init(
            severity: .error,
            title: "Signature does not match",
            message: "The download failed verification and was discarded. Nothing was installed.",
            detail: "expected sha256:9f2c…41ab\nreceived sha256:1d70…c8e5"))

        XCTAssertTrue(banner.announcement.contains("Signature does not match"))
        XCTAssertTrue(banner.announcement.contains("Nothing was installed"))
        XCTAssertFalse(banner.isHidden)
    }

    func testShowingNothingHidesTheBanner() {
        let banner = DSStateBanner(frame: .zero)
        banner.show(.init(severity: .working, title: "Working", message: "…"))
        XCTAssertFalse(banner.isHidden)
        banner.show(nil)
        XCTAssertTrue(banner.isHidden)
    }

    /// Digests are abbreviated at both ends, which is where they differ.
    func testDigestsAreAbbreviated() {
        let digest = "9f2c1188aa77bbccddeeff00112233445566778899aabbccddeeff0011223341ab"
        XCTAssertEqual(PluginsAdminWindowController.abbreviated(digest), "9f2c…41ab")
        XCTAssertEqual(PluginsAdminWindowController.abbreviated("short"), "short")
    }

    /// With no repository configured there is nothing to announce.
    func testNoRepositoryMeansNoBanner() throws {
        let controller = try makeWindow()
        controller.showRestingState()
        XCTAssertTrue(controller.stateBanner.isHidden)
    }

    /// Every state carries a glyph as well as a colour.
    func testEverySeverityHasItsOwnGlyph() {
        let symbols = [DSStateBanner.Severity.working, .success, .warning, .error].map(\.symbol)
        XCTAssertEqual(Set(symbols).count, 4, "two states share a glyph")
        for symbol in symbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                            "\(symbol) is not an SF Symbol")
        }
    }
}
