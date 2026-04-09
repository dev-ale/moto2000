import Foundation

/// Static metadata about the app, exposed so tests can assert on it without
/// reaching into the bundle or the view layer.
enum AppInfo {
    /// Short tagline rendered on the placeholder root view.
    static let tagline = "Custom round motorcycle display — Slice 0 scaffold"

    /// Protocol version advertised by the Slice 0 stub. Bumped in Slice 1 when
    /// the wire format is finalized.
    static let protocolVersion: UInt8 = 0x01
}
