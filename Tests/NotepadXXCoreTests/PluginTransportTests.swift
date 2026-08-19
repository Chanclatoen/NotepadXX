import XCTest
@testable import NotepadXXCore

/// A plug-in archive is arbitrary code, and its checksum comes from the same
/// catalogue as the archive. Over plain HTTP an attacker rewrites both, so the
/// verification proves nothing unless the transport is authenticated.
final class PluginTransportTests: XCTestCase {
    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-transport-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A local catalogue the user pointed at deliberately is fine.
    func testAFileURLIsAccepted() {
        XCTAssertNoThrow(try PluginRepository.requireSafeTransport(
            URL(fileURLWithPath: "/tmp/catalogue.json")))
    }

    func testHTTPSIsAccepted() {
        XCTAssertNoThrow(try PluginRepository.requireSafeTransport(URL(string: "https://example.com/c.json")!))
    }

    func testPlainHTTPIsRefused() {
        XCTAssertThrowsError(try PluginRepository.requireSafeTransport(URL(string: "http://example.com/c.json")!)) {
            XCTAssertEqual($0 as? PluginRepository.RepositoryError,
                           .insecureTransport("http://example.com/c.json"))
        }
    }

    /// Anything else crossing a network is refused too, not just http.
    func testOtherSchemesAreRefused() {
        for source in ["ftp://example.com/c.json", "http://127.0.0.1:8080/c.json"] {
            XCTAssertThrowsError(try PluginRepository.requireSafeTransport(URL(string: source)!),
                                 "\(source) should be refused")
        }
    }

    /// An install over plain HTTP fails before anything is downloaded, rather
    /// than downloading and trusting a checksum that came with it.
    @MainActor
    func testInstallRefusesAPlainHTTPDownload() async throws {
        let repository = try PluginRepository(directory: try directory())
        let listing = PluginListing(
            identifier: "test.plugin", name: "Test", version: "1.0.0",
            description: "", downloadURL: "http://example.com/plugin.zip",
            sha256: String(repeating: "0", count: 64))

        do {
            _ = try await repository.install(listing, into: try directory())
            XCTFail("a plain-HTTP download was allowed")
        } catch let error as PluginRepository.RepositoryError {
            XCTAssertEqual(error, .insecureTransport("http://example.com/plugin.zip"))
        }
    }
}
