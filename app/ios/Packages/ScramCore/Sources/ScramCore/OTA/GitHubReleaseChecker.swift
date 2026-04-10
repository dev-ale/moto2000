import Foundation

/// Describes a firmware update available for download.
public struct FirmwareUpdate: Sendable, Equatable {
    public let version: FirmwareVersion
    public let downloadURL: URL
    public let releaseNotes: String?

    public init(version: FirmwareVersion, downloadURL: URL, releaseNotes: String?) {
        self.version = version
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
    }
}

/// Checks a remote source for available firmware updates.
public protocol ReleaseChecker: Sendable {
    func checkForUpdate(currentVersion: FirmwareVersion) async throws -> FirmwareUpdate?
}

// MARK: - GitHub Release Checker

/// Checks the GitHub Releases API for firmware updates matching the `fw-v*` tag pattern.
///
/// Results are cached in ``UserDefaults`` for 24 hours to avoid excessive API calls.
public struct GitHubReleaseChecker: ReleaseChecker {

    // MARK: - Types

    enum CheckerError: Error, Equatable {
        case noMatchingRelease
        case invalidTagFormat(String)
        case noBinaryAsset
        case networkError(String)
    }

    // MARK: - Dependencies

    private let session: URLSessionProtocol
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// Tag prefix for firmware releases.
    static let tagPrefix = "fw-v"

    /// Cache validity in seconds (24 h).
    static let cacheTTL: TimeInterval = 86_400

    // UserDefaults keys
    static let cacheVersionKey = "scramscreen.ota.cachedVersion"
    static let cacheURLKey = "scramscreen.ota.cachedURL"
    static let cacheNotesKey = "scramscreen.ota.cachedNotes"
    static let cacheTimestampKey = "scramscreen.ota.cacheTimestamp"

    // MARK: - Init

    public init(
        session: URLSessionProtocol = URLSession.shared,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.defaults = defaults
        self.now = now
    }

    // MARK: - ReleaseChecker

    public func checkForUpdate(currentVersion: FirmwareVersion) async throws -> FirmwareUpdate? {
        // Check cache first
        if let cached = cachedUpdate() {
            return cached.version.isNewer(than: currentVersion) ? cached : nil
        }

        // Try latest release first
        let latestURL = URL(string: "https://api.github.com/repos/dev-ale/moto2000/releases/latest")!
        if let update = try await fetchRelease(from: latestURL) {
            storeCache(update)
            return update.version.isNewer(than: currentVersion) ? update : nil
        }

        // Fall back to listing releases and finding the first `fw-v*` tag
        let listURL = URL(string: "https://api.github.com/repos/dev-ale/moto2000/releases?per_page=20")!
        let (data, _) = try await session.dataForRequest(URLRequest(url: listURL))

        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CheckerError.noMatchingRelease
        }

        for release in releases {
            guard let tagName = release["tag_name"] as? String,
                  tagName.hasPrefix(Self.tagPrefix) else { continue }

            if let update = try parseRelease(release) {
                storeCache(update)
                return update.version.isNewer(than: currentVersion) ? update : nil
            }
        }

        throw CheckerError.noMatchingRelease
    }

    // MARK: - Private

    private func fetchRelease(from url: URL) async throws -> FirmwareUpdate? {
        let (data, _) = try await session.dataForRequest(URLRequest(url: url))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let tagName = json["tag_name"] as? String,
              tagName.hasPrefix(Self.tagPrefix) else {
            return nil
        }
        return try parseRelease(json)
    }

    private func parseRelease(_ json: [String: Any]) throws -> FirmwareUpdate? {
        guard let tagName = json["tag_name"] as? String else { return nil }

        let versionString = String(tagName.dropFirst(Self.tagPrefix.count))
        guard let version = FirmwareVersion(string: versionString) else {
            throw CheckerError.invalidTagFormat(tagName)
        }

        guard let assets = json["assets"] as? [[String: Any]],
              let binAsset = assets.first(where: {
                  ($0["name"] as? String)?.hasSuffix(".bin") == true
              }),
              let urlString = binAsset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw CheckerError.noBinaryAsset
        }

        let notes = json["body"] as? String
        return FirmwareUpdate(version: version, downloadURL: downloadURL, releaseNotes: notes)
    }

    // MARK: - Cache

    private func cachedUpdate() -> FirmwareUpdate? {
        guard let timestamp = defaults.object(forKey: Self.cacheTimestampKey) as? Date else {
            return nil
        }
        guard now().timeIntervalSince(timestamp) < Self.cacheTTL else {
            return nil
        }
        guard let versionString = defaults.string(forKey: Self.cacheVersionKey),
              let version = FirmwareVersion(string: versionString),
              let urlString = defaults.string(forKey: Self.cacheURLKey),
              let url = URL(string: urlString) else {
            return nil
        }
        let notes = defaults.string(forKey: Self.cacheNotesKey)
        return FirmwareUpdate(version: version, downloadURL: url, releaseNotes: notes)
    }

    private func storeCache(_ update: FirmwareUpdate) {
        defaults.set(update.version.versionString, forKey: Self.cacheVersionKey)
        defaults.set(update.downloadURL.absoluteString, forKey: Self.cacheURLKey)
        defaults.set(update.releaseNotes, forKey: Self.cacheNotesKey)
        defaults.set(now(), forKey: Self.cacheTimestampKey)
    }
}

// MARK: - URLSession abstraction for testability

/// Minimal protocol wrapping the URLSession data task API.
public protocol URLSessionProtocol: Sendable {
    func dataForRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {
    public func dataForRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
