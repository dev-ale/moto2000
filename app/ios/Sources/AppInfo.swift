import BLEProtocol
import Foundation

/// Static metadata about the app, exposed so tests can assert on it without
/// reaching into the bundle or the view layer.
enum AppInfo {
    /// Short tagline rendered on the placeholder root view.
    static let tagline = "Custom round motorcycle display — Slice 1 scaffold"

    /// Protocol version the app speaks on the wire. Sourced from the
    /// authoritative `BLEProtocol` package so bumping the wire format
    /// automatically updates any copy that reads from this type.
    static let protocolVersion: UInt8 = BLEProtocolConstants.protocolVersion
}
