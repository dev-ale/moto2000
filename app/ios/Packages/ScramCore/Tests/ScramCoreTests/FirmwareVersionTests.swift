import XCTest

@testable import ScramCore

final class FirmwareVersionTests: XCTestCase {

    // MARK: - Comparison

    func test_equal_versions() {
        let a = FirmwareVersion(major: 1, minor: 2, patch: 3)
        let b = FirmwareVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isNewer(than: b))
        XCTAssertFalse(b.isNewer(than: a))
    }

    func test_newer_major() {
        let current = FirmwareVersion(major: 1, minor: 9, patch: 9)
        let available = FirmwareVersion(major: 2, minor: 0, patch: 0)
        XCTAssertTrue(available.isNewer(than: current))
        XCTAssertFalse(current.isNewer(than: available))
    }

    func test_newer_minor() {
        let current = FirmwareVersion(major: 1, minor: 2, patch: 9)
        let available = FirmwareVersion(major: 1, minor: 3, patch: 0)
        XCTAssertTrue(available.isNewer(than: current))
    }

    func test_newer_patch() {
        let current = FirmwareVersion(major: 1, minor: 2, patch: 3)
        let available = FirmwareVersion(major: 1, minor: 2, patch: 4)
        XCTAssertTrue(available.isNewer(than: current))
    }

    func test_older_version() {
        let current = FirmwareVersion(major: 2, minor: 0, patch: 0)
        let available = FirmwareVersion(major: 1, minor: 9, patch: 9)
        XCTAssertFalse(available.isNewer(than: current))
    }

    func test_comparable_sorting() {
        let versions = [
            FirmwareVersion(major: 2, minor: 0, patch: 0),
            FirmwareVersion(major: 1, minor: 0, patch: 0),
            FirmwareVersion(major: 1, minor: 1, patch: 0),
            FirmwareVersion(major: 1, minor: 0, patch: 1),
        ]
        let sorted = versions.sorted()
        XCTAssertEqual(sorted, [
            FirmwareVersion(major: 1, minor: 0, patch: 0),
            FirmwareVersion(major: 1, minor: 0, patch: 1),
            FirmwareVersion(major: 1, minor: 1, patch: 0),
            FirmwareVersion(major: 2, minor: 0, patch: 0),
        ])
    }

    // MARK: - Parsing

    func test_parse_valid() {
        let v = FirmwareVersion(string: "1.2.3")
        XCTAssertEqual(v, FirmwareVersion(major: 1, minor: 2, patch: 3))
    }

    func test_parse_zeros() {
        let v = FirmwareVersion(string: "0.0.0")
        XCTAssertEqual(v, FirmwareVersion(major: 0, minor: 0, patch: 0))
    }

    func test_parse_max() {
        let v = FirmwareVersion(string: "255.255.255")
        XCTAssertEqual(v, FirmwareVersion(major: 255, minor: 255, patch: 255))
    }

    func test_parse_overflow_returns_nil() {
        XCTAssertNil(FirmwareVersion(string: "256.0.0"))
    }

    func test_parse_too_few_components() {
        XCTAssertNil(FirmwareVersion(string: "1.2"))
    }

    func test_parse_too_many_components() {
        XCTAssertNil(FirmwareVersion(string: "1.2.3.4"))
    }

    func test_parse_empty() {
        XCTAssertNil(FirmwareVersion(string: ""))
    }

    func test_parse_garbage() {
        XCTAssertNil(FirmwareVersion(string: "abc"))
    }

    func test_parse_negative() {
        XCTAssertNil(FirmwareVersion(string: "-1.0.0"))
    }

    // MARK: - String round-trip

    func test_versionString() {
        let v = FirmwareVersion(major: 10, minor: 20, patch: 30)
        XCTAssertEqual(v.versionString, "10.20.30")
    }

    func test_roundtrip() {
        let original = FirmwareVersion(major: 42, minor: 0, patch: 255)
        let parsed = FirmwareVersion(string: original.versionString)
        XCTAssertEqual(parsed, original)
    }

    func test_description() {
        let v = FirmwareVersion(major: 1, minor: 0, patch: 0)
        XCTAssertEqual(String(describing: v), "1.0.0")
    }

    // MARK: - Edge cases

    func test_zero_zero_zero() {
        let v = FirmwareVersion(major: 0, minor: 0, patch: 0)
        XCTAssertFalse(v.isNewer(than: v))
    }

    func test_max_max_max() {
        let v = FirmwareVersion(major: 255, minor: 255, patch: 255)
        XCTAssertFalse(v.isNewer(than: v))
    }

    func test_hashable() {
        let a = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let b = FirmwareVersion(major: 1, minor: 0, patch: 0)
        let set: Set<FirmwareVersion> = [a, b]
        XCTAssertEqual(set.count, 1)
    }
}
