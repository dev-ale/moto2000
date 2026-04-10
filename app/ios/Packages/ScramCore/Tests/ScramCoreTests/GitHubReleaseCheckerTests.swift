import Foundation
import XCTest

@testable import ScramCore

// MARK: - Mock URLSession

private final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var responseData: Data = Data()
    var responseStatusCode: Int = 200
    var error: (any Error)?

    /// When set, the mock returns this for the *second* request (list endpoint).
    var listResponseData: Data?
    private var callCount = 0

    func dataForRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let error { throw error }
        callCount += 1
        let data: Data
        if callCount > 1, let listData = listResponseData {
            data = listData
        } else {
            data = responseData
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Sendable clock for cache tests

private final class SendableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ date: Date = Date()) { _now = date }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(interval)
        lock.unlock()
    }
}

// MARK: - Helpers

private func makeReleaseJSON(
    tagName: String,
    body: String? = "Release notes",
    assetName: String = "firmware.bin",
    assetURL: String = "https://example.com/firmware.bin"
) -> Data {
    var json: [String: Any] = [
        "tag_name": tagName,
        "assets": [
            [
                "name": assetName,
                "browser_download_url": assetURL,
            ] as [String: Any],
        ] as [[String: Any]],
    ]
    if let body {
        json["body"] = body
    }
    return try! JSONSerialization.data(withJSONObject: json)
}

private func makeReleasesListJSON(_ releases: [(tag: String, assetName: String, assetURL: String)]) -> Data {
    let list: [[String: Any]] = releases.map { release in
        [
            "tag_name": release.tag,
            "body": "Notes for \(release.tag)",
            "assets": [
                [
                    "name": release.assetName,
                    "browser_download_url": release.assetURL,
                ] as [String: Any],
            ] as [[String: Any]],
        ] as [String: Any]
    }
    return try! JSONSerialization.data(withJSONObject: list)
}

// MARK: - Tests

final class GitHubReleaseCheckerTests: XCTestCase {

    // MARK: - Tag parsing

    func test_parsesTag_fw_v1_2_3() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v1.2.3")

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertEqual(update?.version, FirmwareVersion(major: 1, minor: 2, patch: 3))
    }

    func test_parsesTag_fw_v0_0_1() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v0.0.1")

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 0, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertEqual(update?.version, FirmwareVersion(major: 0, minor: 0, patch: 1))
    }

    // MARK: - Version comparison

    func test_newerVersion_returnsUpdate() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v2.0.0")

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertNotNil(update)
        XCTAssertEqual(update?.version, FirmwareVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(update?.downloadURL.absoluteString, "https://example.com/firmware.bin")
        XCTAssertEqual(update?.releaseNotes, "Release notes")
    }

    func test_sameVersion_returnsNil() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v1.0.0")

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertNil(update)
    }

    func test_olderVersion_returnsNil() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v0.9.0")

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertNil(update)
    }

    // MARK: - Fallback to release list

    func test_fallsBackToReleaseList_whenLatestTagDoesNotMatch() async throws {
        let session = MockURLSession()
        // Latest release has a non-firmware tag
        session.responseData = makeReleaseJSON(tagName: "app-v3.0.0")
        // List includes a firmware release
        session.listResponseData = makeReleasesListJSON([
            (tag: "app-v3.0.0", assetName: "app.ipa", assetURL: "https://example.com/app.ipa"),
            (tag: "fw-v1.5.0", assetName: "firmware.bin", assetURL: "https://example.com/fw.bin"),
        ])

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let update = try await checker.checkForUpdate(currentVersion: current)

        XCTAssertEqual(update?.version, FirmwareVersion(major: 1, minor: 5, patch: 0))
        XCTAssertEqual(update?.downloadURL.absoluteString, "https://example.com/fw.bin")
    }

    // MARK: - Cache behavior

    func test_cache_returnsWithoutNetwork_withinTTL() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v2.0.0")

        let defaults = ephemeralDefaults()
        let clock = SendableClock()

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: defaults,
            now: { clock.now }
        )

        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)

        // First call — populates cache
        let first = try await checker.checkForUpdate(currentVersion: current)
        XCTAssertNotNil(first)

        // Change the network response — if cache works, we should still get the old result
        session.responseData = makeReleaseJSON(tagName: "fw-v3.0.0")

        // Advance time by 1 hour (within 24h TTL)
        clock.advance(by: 3600)
        let second = try await checker.checkForUpdate(currentVersion: current)
        XCTAssertEqual(second?.version, FirmwareVersion(major: 2, minor: 0, patch: 0))
    }

    func test_cache_expiresAfterTTL() async throws {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(tagName: "fw-v2.0.0")

        let defaults = ephemeralDefaults()
        let clock = SendableClock()

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: defaults,
            now: { clock.now }
        )

        let current = FirmwareVersion(major: 1, minor: 0, patch: 0)

        // First call — populates cache
        _ = try await checker.checkForUpdate(currentVersion: current)

        // Change response and advance past TTL
        session.responseData = makeReleaseJSON(tagName: "fw-v3.0.0")
        clock.advance(by: GitHubReleaseChecker.cacheTTL + 1)

        let update = try await checker.checkForUpdate(currentVersion: current)
        XCTAssertEqual(update?.version, FirmwareVersion(major: 3, minor: 0, patch: 0))
    }

    // MARK: - Error cases

    func test_noBinaryAsset_throws() async {
        let session = MockURLSession()
        session.responseData = makeReleaseJSON(
            tagName: "fw-v1.0.0",
            assetName: "readme.txt",
            assetURL: "https://example.com/readme.txt"
        )

        let checker = GitHubReleaseChecker(
            session: session,
            defaults: ephemeralDefaults(),
            now: { Date() }
        )
        let current = FirmwareVersion(major: 0, minor: 9, patch: 0)

        do {
            _ = try await checker.checkForUpdate(currentVersion: current)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    // MARK: - Helpers

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }
}
