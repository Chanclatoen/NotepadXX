import Foundation
import CryptoKit

/// One plugin as advertised by a repository catalogue.
public struct PluginListing: Codable, Equatable, Sendable, Identifiable {
    public var identifier: String
    public var name: String
    public var version: String
    public var description: String
    public var author: String?
    public var homepage: String?
    /// Where the plugin archive lives. A `file:` URL works, which is what makes
    /// a local or bundled catalogue possible.
    public var downloadURL: String
    /// Lowercase hex SHA-256 of the archive. Required: an unverified download
    /// is arbitrary code execution.
    public var sha256: String
    public var minimumAppVersion: String?

    public var id: String { identifier }

    public init(
        identifier: String, name: String, version: String, description: String,
        downloadURL: String, sha256: String,
        author: String? = nil, homepage: String? = nil, minimumAppVersion: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.description = description
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.author = author
        self.homepage = homepage
        self.minimumAppVersion = minimumAppVersion
    }
}

public struct PluginCatalogue: Codable, Equatable, Sendable {
    public var name: String
    public var plugins: [PluginListing]
    public init(name: String, plugins: [PluginListing]) {
        self.name = name
        self.plugins = plugins
    }
}

/// Fetches plugin catalogues and installs from them — the Plugins Admin
/// "Available" list.
///
/// Repository URLs are user-configurable. Nothing is fetched until the user
/// opens Plugins Admin, and nothing is installed without an explicit click.
@MainActor
public final class PluginRepository {
    public private(set) var catalogues: [PluginCatalogue] = []
    public private(set) var sourceURLs: [URL]
    private let cacheURL: URL
    private let session: URLSession

    public init(directory: URL, sourceURLs: [URL] = [], session: URLSession = .shared) {
        self.sourceURLs = sourceURLs
        self.cacheURL = directory.appendingPathComponent("plugin-catalogue-cache.json")
        self.session = session
        loadCache()
    }

    public enum RepositoryError: Error, Equatable {
        case unreachable(String)
        case malformedCatalogue(String)
        case checksumMismatch(expected: String, actual: String)
        /// A source or download that is not HTTPS.
        case insecureTransport(String)
        case notAnArchive(String)
        case noPluginInArchive
    }

    /// All listings across catalogues, newest-first per identifier.
    public var allListings: [PluginListing] {
        var seen: [String: PluginListing] = [:]
        for listing in catalogues.flatMap(\.plugins) {
            // A later catalogue does not silently shadow an earlier one unless
            // it offers a higher version.
            if let existing = seen[listing.identifier],
               compareVersions(listing.version, existing.version) != .orderedDescending {
                continue
            }
            seen[listing.identifier] = listing
        }
        return seen.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public func addSource(_ url: URL) {
        guard !sourceURLs.contains(url) else { return }
        sourceURLs.append(url)
    }

    public func removeSource(_ url: URL) {
        sourceURLs.removeAll { $0 == url }
    }

    /// Refreshes every catalogue. A source that fails is reported but does not
    /// prevent the others from loading.
    @discardableResult
    public func refresh() async -> [RepositoryError] {
        var loaded: [PluginCatalogue] = []
        var failures: [RepositoryError] = []

        for url in sourceURLs {
            do {
                try Self.requireSafeTransport(url)
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    (data, _) = try await session.data(from: url)
                }
                loaded.append(try JSONDecoder().decode(PluginCatalogue.self, from: data))
            } catch is DecodingError {
                failures.append(.malformedCatalogue(url.absoluteString))
            } catch let error as RepositoryError {
                failures.append(error)
            } catch {
                failures.append(.unreachable(url.absoluteString))
            }
        }

        // Keep the cached copy when every source failed, so the list is not
        // emptied by a flaky network.
        if !loaded.isEmpty || failures.isEmpty {
            catalogues = loaded
            saveCache()
        }
        return failures
    }

    /// Refuses any source that is not safe to fetch from.
    ///
    /// A file URL is a local catalogue the user pointed at deliberately and is
    /// allowed. Everything crossing a network must be HTTPS, or the checksums
    /// it carries mean nothing: an attacker who can rewrite the catalogue
    /// supplies both the archive and the hash it is checked against.
    nonisolated static func requireSafeTransport(_ url: URL) throws {
        guard url.isFileURL || url.scheme?.lowercased() == "https" else {
            throw RepositoryError.insecureTransport(url.absoluteString)
        }
    }

    /// Downloads, verifies and unpacks a plugin into `destination`.
    public func install(_ listing: PluginListing, into destination: URL) async throws -> URL {
        guard let url = URL(string: listing.downloadURL) else {
            throw RepositoryError.unreachable(listing.downloadURL)
        }

        // Checked before anything is fetched: the checksum below is only as
        // trustworthy as the transport the archive and its hash arrived over.
        try Self.requireSafeTransport(url)

        let data: Data
        do {
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                (data, _) = try await session.data(from: url)
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.unreachable(listing.downloadURL)
        }

        // Verify before unpacking. An unverified archive is arbitrary code.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(listing.sha256) == .orderedSame else {
            throw RepositoryError.checksumMismatch(expected: listing.sha256, actual: digest)
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("plugin.zip")
        try data.write(to: archive)
        try unzip(archive, into: staging)

        // The archive may hold the plugin at its root or one level down.
        guard let root = try locatePluginRoot(in: staging) else {
            throw RepositoryError.noPluginInArchive
        }
        let target = destination.appendingPathComponent(
            PluginRegistry.safeFolderName(for: listing.identifier), isDirectory: true
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: root, to: target)
        return target
    }

    /// Listings that are newer than what is installed.
    public func availableUpdates(installed: [InstalledPlugin]) -> [PluginListing] {
        allListings.filter { listing in
            guard let current = installed.first(where: { $0.id == listing.identifier }) else { return false }
            return compareVersions(listing.version, current.manifest.version) == .orderedDescending
        }
    }

    // MARK: - Helpers

    private func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archive.path, "-d", directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RepositoryError.notAnArchive(archive.lastPathComponent)
        }
    }

    /// The directory containing plugin.json, at the archive root or one down.
    private func locatePluginRoot(in directory: URL) throws -> URL? {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.appendingPathComponent("plugin.json").path) {
            return directory
        }
        for entry in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            if manager.fileExists(atPath: entry.appendingPathComponent("plugin.json").path) {
                return entry
            }
        }
        return nil
    }

    /// Numeric-aware version comparison: 1.10 is newer than 1.9.
    public func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = left.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let rightParts = right.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let a = index < leftParts.count ? leftParts[index] : 0
            let b = index < rightParts.count ? rightParts[index] : 0
            if a != b { return a > b ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    private func saveCache() {
        try? JSONEncoder().encode(catalogues).write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([PluginCatalogue].self, from: data) else { return }
        catalogues = decoded
    }
}
