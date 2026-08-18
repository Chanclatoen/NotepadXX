import XCTest
import CryptoKit
@testable import NotepadXXCore

@MainActor
final class PluginRepositoryTests: XCTestCase {
    private func workspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a real zipped plugin and a catalogue pointing at it, so install
    /// is exercised end to end without touching the network.
    private func makeLocalPlugin(
        in dir: URL, identifier: String, version: String, nested: Bool = false
    ) throws -> PluginListing {
        let staging = dir.appendingPathComponent("src-\(identifier)", isDirectory: true)
        let pluginDir = nested
            ? staging.appendingPathComponent("inner", isDirectory: true)
            : staging
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest = PluginManifest(
            name: identifier, identifier: identifier, version: version, main: "main.js",
            commands: [PluginManifest.Command(id: "run", title: "Run")]
        )
        try JSONEncoder().encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try Data("exports.run = function(){};".utf8).write(to: pluginDir.appendingPathComponent("main.js"))

        let archive = dir.appendingPathComponent("\(identifier).zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = staging
        zip.arguments = ["-q", "-r", archive.path, "."]
        zip.standardOutput = Pipe()
        try zip.run()
        zip.waitUntilExit()

        let data = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PluginListing(
            identifier: identifier, name: identifier, version: version,
            description: "test plugin", downloadURL: archive.absoluteString, sha256: digest
        )
    }

    private func writeCatalogue(_ listings: [PluginListing], in dir: URL, named: String = "cat") throws -> URL {
        let catalogue = PluginCatalogue(name: named, plugins: listings)
        let url = dir.appendingPathComponent("\(named).json")
        try JSONEncoder().encode(catalogue).write(to: url)
        return url
    }

    func testRefreshLoadsACatalogue() async throws {
        let dir = try workspace()
        let listing = try makeLocalPlugin(in: dir, identifier: "com.test.one", version: "1.0")
        let catalogue = try writeCatalogue([listing], in: dir)

        let repo = PluginRepository(directory: dir, sourceURLs: [catalogue])
        let failures = await repo.refresh()
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(repo.allListings.map(\.identifier), ["com.test.one"])
    }

    func testInstallVerifiesChecksumAndUnpacks() async throws {
        let dir = try workspace()
        let listing = try makeLocalPlugin(in: dir, identifier: "com.test.install", version: "1.0")
        let catalogue = try writeCatalogue([listing], in: dir)
        let repo = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repo.refresh()

        let plugins = dir.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let installed = try await repo.install(listing, into: plugins)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installed.appendingPathComponent("plugin.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installed.appendingPathComponent("main.js").path))
    }

    /// An unverified download is arbitrary code execution, so a mismatched
    /// checksum must abort before anything is unpacked.
    func testInstallRefusesAMismatchedChecksum() async throws {
        let dir = try workspace()
        var listing = try makeLocalPlugin(in: dir, identifier: "com.test.tampered", version: "1.0")
        listing.sha256 = String(repeating: "0", count: 64)

        let plugins = dir.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)

        do {
            _ = try await PluginRepository(directory: dir).install(listing, into: plugins)
            XCTFail("a tampered archive must not install")
        } catch let error as PluginRepository.RepositoryError {
            guard case .checksumMismatch = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: plugins.path).isEmpty,
                      "nothing was written")
    }

    func testArchiveWithThePluginOneLevelDownStillInstalls() async throws {
        let dir = try workspace()
        let listing = try makeLocalPlugin(in: dir, identifier: "com.test.nested", version: "1.0", nested: true)
        let plugins = dir.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)

        let installed = try await PluginRepository(directory: dir).install(listing, into: plugins)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installed.appendingPathComponent("plugin.json").path))
    }

    func testUnreachableSourceIsReportedWithoutLosingTheCache() async throws {
        let dir = try workspace()
        let listing = try makeLocalPlugin(in: dir, identifier: "com.test.cached", version: "1.0")
        let catalogue = try writeCatalogue([listing], in: dir)

        let repo = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repo.refresh()
        XCTAssertEqual(repo.allListings.count, 1)

        // Point at something that does not exist and refresh again.
        repo.removeSource(catalogue)
        repo.addSource(dir.appendingPathComponent("missing.json"))
        let failures = await repo.refresh()

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(repo.allListings.count, 1, "a flaky source must not empty the list")
    }

    func testMalformedCatalogueIsReportedDistinctly() async throws {
        let dir = try workspace()
        let bad = dir.appendingPathComponent("bad.json")
        try Data("{ not a catalogue".utf8).write(to: bad)

        let failures = await PluginRepository(directory: dir, sourceURLs: [bad]).refresh()
        guard case .malformedCatalogue? = failures.first else {
            return XCTFail("expected a malformed-catalogue error, got \(String(describing: failures.first))")
        }
    }

    func testVersionComparisonIsNumericNotLexical() {
        let repo = PluginRepository(directory: FileManager.default.temporaryDirectory)
        XCTAssertEqual(repo.compareVersions("1.10.0", "1.9.0"), .orderedDescending,
                       "1.10 is newer than 1.9, which string comparison gets wrong")
        XCTAssertEqual(repo.compareVersions("2.0", "2.0.0"), .orderedSame)
        XCTAssertEqual(repo.compareVersions("1.0", "1.0.1"), .orderedAscending)
    }

    func testUpdatesAreOfferedOnlyForNewerVersions() async throws {
        let dir = try workspace()
        let listing = try makeLocalPlugin(in: dir, identifier: "com.test.upd", version: "2.0")
        let catalogue = try writeCatalogue([listing], in: dir)
        let repo = PluginRepository(directory: dir, sourceURLs: [catalogue])
        await repo.refresh()

        let older = InstalledPlugin(
            manifest: PluginManifest(name: "u", identifier: "com.test.upd", version: "1.0", main: "main.js"),
            directory: dir, isEnabled: true
        )
        XCTAssertEqual(repo.availableUpdates(installed: [older]).map(\.version), ["2.0"])

        let current = InstalledPlugin(
            manifest: PluginManifest(name: "u", identifier: "com.test.upd", version: "2.0", main: "main.js"),
            directory: dir, isEnabled: true
        )
        XCTAssertTrue(repo.availableUpdates(installed: [current]).isEmpty)
    }

    /// A second catalogue must not shadow a newer entry from the first.
    func testHigherVersionWinsAcrossCatalogues() async throws {
        let dir = try workspace()
        let newer = try makeLocalPlugin(in: dir, identifier: "com.test.dup", version: "3.0")
        var older = newer
        older.version = "1.0"

        let first = try writeCatalogue([newer], in: dir, named: "first")
        let second = try writeCatalogue([older], in: dir, named: "second")
        let repo = PluginRepository(directory: dir, sourceURLs: [first, second])
        await repo.refresh()

        XCTAssertEqual(repo.allListings.count, 1)
        XCTAssertEqual(repo.allListings.first?.version, "3.0")
    }
}
