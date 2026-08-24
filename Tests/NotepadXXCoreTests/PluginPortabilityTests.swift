import XCTest
import CryptoKit
@testable import NotepadXXCore

/// The bundled catalogue has to work on the machine that *runs* the app, not
/// the one that built it. Plugins failed to install on any other Mac because
/// each entry named an absolute path from the build machine.
@MainActor
final class PluginPortabilityTests: XCTestCase {
    private func makeBundleLikeTree(at root: URL) throws -> URL {
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("plugins"),
                                                withIntermediateDirectories: true)
        // A stand-in archive; this test is about locating it, not unpacking it.
        let archive = resources.appendingPathComponent("plugins/test.plugin.zip")
        try Data("archive".utf8).write(to: archive)

        let catalogue = """
            {"name":"Bundled","plugins":[{"identifier":"test.plugin","name":"Test",
             "version":"1.0.0","description":"","downloadURL":"plugins/test.plugin.zip",
             "sha256":"0000000000000000000000000000000000000000000000000000000000000000",
             "author":"NotepadXX"}]}
            """
        let catalogueURL = resources.appendingPathComponent("plugin-catalogue.json")
        try catalogue.write(to: catalogueURL, atomically: true, encoding: .utf8)
        return catalogueURL
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-portability-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The bug, reproduced: a catalogue read from one location must point at
    /// archives in *that* location.
    func testTheBundledCatalogueResolvesWhereverTheAppIs() async throws {
        let installed = try temporaryDirectory().appendingPathComponent("NotepadXX.app")
        let catalogueURL = try makeBundleLikeTree(at: installed)
        defer { try? FileManager.default.removeItem(at: installed.deletingLastPathComponent()) }

        let repository = PluginRepository(directory: try temporaryDirectory(),
                                          sourceURLs: [catalogueURL])
        let failures = await repository.refresh()
        XCTAssertTrue(failures.isEmpty, "catalogue failed to load: \(failures)")

        let listing = try XCTUnwrap(repository.catalogues.first?.plugins.first)
        let resolved = try XCTUnwrap(URL(string: listing.downloadURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path),
                      "the archive is not where the catalogue says: \(listing.downloadURL)")
    }

    /// Moving the app — which is what installing it does — must not break it.
    func testMovingTheAppKeepsThePluginsInstallable() async throws {
        let first = try temporaryDirectory().appendingPathComponent("NotepadXX.app")
        _ = try makeBundleLikeTree(at: first)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        // Copy it somewhere else, as dragging to /Applications would.
        let secondParent = try temporaryDirectory()
        let second = secondParent.appendingPathComponent("NotepadXX.app")
        try FileManager.default.copyItem(at: first, to: second)
        defer { try? FileManager.default.removeItem(at: secondParent) }

        let movedCatalogue = second.appendingPathComponent("Contents/Resources/plugin-catalogue.json")
        let repository = PluginRepository(directory: try temporaryDirectory(),
                                          sourceURLs: [movedCatalogue])
        _ = await repository.refresh()

        let listing = try XCTUnwrap(repository.catalogues.first?.plugins.first)
        let resolved = try XCTUnwrap(URL(string: listing.downloadURL))
        XCTAssertTrue(resolved.path.hasPrefix(second.path),
                      "resolved against the old location: \(resolved.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
    }

    /// A remote catalogue's absolute URLs must not be rewritten.
    func testAbsoluteEntriesAreLeftAlone() {
        let listing = PluginListing(
            identifier: "x", name: "X", version: "1", description: "",
            downloadURL: "https://example.com/x.zip", sha256: String(repeating: "0", count: 64))
        let resolved = listing.resolved(
            against: URL(string: "https://example.com/catalogue.json")!)
        XCTAssertEqual(resolved.downloadURL, "https://example.com/x.zip")
    }

    /// The catalogue this build actually ships must not name any absolute path.
    func testTheShippedCatalogueHasNoBuildMachinePaths() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let catalogue = root.appendingPathComponent("dist/NotepadXX.app/Contents/Resources/plugin-catalogue.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: catalogue.path),
                          "no built app to inspect")

        let text = try String(contentsOf: catalogue, encoding: .utf8)
        XCTAssertFalse(text.contains("file://"), "the catalogue ships absolute file URLs")
        XCTAssertFalse(text.contains("/Users/"), "the catalogue ships a build-machine path")
    }
}

/// A plug-in archive is arbitrary content from a catalogue. What it may contain
/// has to be bounded, not merely hoped about.
@MainActor
final class PluginArchiveSafetyTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npxx-archive-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a zip whose entries are written by `build`, and returns it with
    /// its checksum so install() gets past verification and reaches unpacking.
    private func makeArchive(in directory: URL,
                             build: (URL) throws -> Void) throws -> (url: URL, sha256: String) {
        let staging = directory.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try build(staging)

        let archive = directory.appendingPathComponent("plugin.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", "-y", archive.path, "."]   // -y keeps links as links
        zip.currentDirectoryURL = staging
        try zip.run()
        zip.waitUntilExit()

        let data = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (archive, digest)
    }

    /// unzip will not write *through* an escaping link, but it does create the
    /// link. A plug-in folder containing a link out is a foothold, so the
    /// install is refused outright.
    func testAnArchiveContainingALinkIsRefused() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }

        let archive = try makeArchive(in: workspace) { staging in
            try #"{"id":"x","name":"X","version":"1.0.0","entry":"main.js"}"#
                .write(to: staging.appendingPathComponent("plugin.json"),
                       atomically: true, encoding: .utf8)
            try "".write(to: staging.appendingPathComponent("main.js"),
                         atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: staging.appendingPathComponent("escape"), withDestinationURL: outside)
        }

        let repository = PluginRepository(directory: try temporaryDirectory())
        let listing = PluginListing(
            identifier: "x", name: "X", version: "1.0.0", description: "",
            downloadURL: archive.url.absoluteString, sha256: archive.sha256)

        do {
            _ = try await repository.install(listing, into: try temporaryDirectory())
            XCTFail("an archive containing a link was installed")
        } catch let error as PluginRepository.RepositoryError {
            guard case .unsafeArchiveEntry = error else {
                return XCTFail("wrong refusal: \(error)")
            }
        }
    }

    /// An ordinary plug-in still installs — the check must not refuse everything.
    func testAnOrdinaryArchiveStillInstalls() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let archive = try makeArchive(in: workspace) { staging in
            try #"{"id":"ordinary","name":"Ordinary","version":"1.0.0","entry":"main.js"}"#
                .write(to: staging.appendingPathComponent("plugin.json"),
                       atomically: true, encoding: .utf8)
            try "function run() {}".write(to: staging.appendingPathComponent("main.js"),
                                          atomically: true, encoding: .utf8)
        }

        let repository = PluginRepository(directory: try temporaryDirectory())
        let listing = PluginListing(
            identifier: "ordinary", name: "Ordinary", version: "1.0.0", description: "",
            downloadURL: archive.url.absoluteString, sha256: archive.sha256)

        let installed = try await repository.install(listing, into: try temporaryDirectory())
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installed.appendingPathComponent("plugin.json").path))
    }
}
