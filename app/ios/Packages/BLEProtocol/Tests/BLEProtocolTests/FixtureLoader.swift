import Foundation
import XCTest

@testable import BLEProtocol

/// Locates and loads golden fixtures from `protocol/fixtures/` at the repo root.
///
/// The path is resolved from `#filePath` so tests work regardless of the
/// build directory (SwiftPM, Xcode, or CI). If you move this file, update
/// ``repoRoot`` accordingly.
enum FixtureLoader {
    /// Repo-relative path from this source file to `protocol/fixtures/`.
    private static let fixturesRelativePath = "../../../../../../protocol/fixtures"

    static let fixturesDirectory: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(fixturesRelativePath, isDirectory: true)
            .standardizedFileURL
    }()

    static func load(_ relativePath: String) throws -> Data {
        let url = fixturesDirectory.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    static func loadJSON(_ relativePath: String) throws -> [String: Any] {
        let data = try load(relativePath)
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            XCTFail("fixture \(relativePath) is not a JSON object")
            return [:]
        }
        return object
    }

    /// All basenames (without extension) under `valid/`.
    static func validFixtureNames() throws -> [String] {
        try listNames(in: "valid")
    }

    /// All basenames (without extension) under `invalid/`.
    static func invalidFixtureNames() throws -> [String] {
        try listNames(in: "invalid")
    }

    /// All basenames (without extension) under `control/valid/`.
    static func controlValidFixtureNames() throws -> [String] {
        try listNames(in: "control/valid")
    }

    /// All basenames (without extension) under `control/invalid/`.
    static func controlInvalidFixtureNames() throws -> [String] {
        try listNames(in: "control/invalid")
    }

    /// All basenames (without extension) under `status/valid/`.
    static func statusValidFixtureNames() throws -> [String] {
        try listNames(in: "status/valid")
    }

    /// All basenames (without extension) under `status/invalid/`.
    static func statusInvalidFixtureNames() throws -> [String] {
        try listNames(in: "status/invalid")
    }

    private static func listNames(in subdirectory: String) throws -> [String] {
        let url = fixturesDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
