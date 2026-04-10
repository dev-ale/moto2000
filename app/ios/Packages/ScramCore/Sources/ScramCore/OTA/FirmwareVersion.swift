import Foundation

/// Semantic version for ESP32 firmware images.
///
/// Components are `UInt8` to match the C-side `ota_version_t` which uses
/// single bytes. The range 0.0.0 through 255.255.255 is sufficient for
/// firmware versioning.
public struct FirmwareVersion: Equatable, Sendable, Hashable {
    public let major: UInt8
    public let minor: UInt8
    public let patch: UInt8

    public init(major: UInt8, minor: UInt8, patch: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

// MARK: - Comparable

extension FirmwareVersion: Comparable {
    public static func < (lhs: FirmwareVersion, rhs: FirmwareVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - Convenience

extension FirmwareVersion {
    /// Returns `true` if `self` is strictly newer than `other`.
    public func isNewer(than other: FirmwareVersion) -> Bool {
        self > other
    }

    /// The string representation in "major.minor.patch" format.
    public var versionString: String {
        "\(major).\(minor).\(patch)"
    }

    /// Parse a "major.minor.patch" string. Returns `nil` if the format is
    /// invalid or any component exceeds 255.
    public init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let maj = UInt8(parts[0]),
              let min = UInt8(parts[1]),
              let pat = UInt8(parts[2])
        else { return nil }
        self.init(major: maj, minor: min, patch: pat)
    }
}

// MARK: - CustomStringConvertible

extension FirmwareVersion: CustomStringConvertible {
    public var description: String { versionString }
}
