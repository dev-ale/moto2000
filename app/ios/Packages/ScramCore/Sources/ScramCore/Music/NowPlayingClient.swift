import Foundation

/// Abstracts "where does the current playing info come from" so the rest of
/// the iOS domain never touches `MPNowPlayingInfoCenter` (or any other
/// system framework) directly.
///
/// Tests inject ``StaticNowPlayingClient``; production code eventually
/// injects ``MediaPlayerNowPlayingClient`` (or a replacement once a
/// follow-up slice decides how to wire the system framework — see
/// docs/platform-limits.md).
public protocol NowPlayingClient: Sendable {
    /// Fetches a snapshot of the currently playing track, or `nil` if
    /// nothing is playing / available.
    func fetchNowPlaying() async throws -> NowPlayingClientResponse?
}

/// Decoupled value type returned by ``NowPlayingClient`` implementations.
///
/// This is deliberately *not* `NowPlayingSnapshot` — the RideSimulatorKit
/// snapshot embeds a scenario timestamp which only makes sense for the
/// mock provider. The client returns the raw "now" values and lets
/// ``RealNowPlayingProvider`` stamp the scenario time itself.
public struct NowPlayingClientResponse: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    /// nil = unknown (e.g. live radio stream)
    public var positionSeconds: Double?
    /// nil = unknown
    public var durationSeconds: Double?

    public init(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        positionSeconds: Double?,
        durationSeconds: Double?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }
}

public enum NowPlayingClientError: Error, Sendable, Equatable {
    /// The client is a deferred stub — Slice 8 ships the protocol seam but
    /// no real system integration yet. See docs/platform-limits.md.
    case notImplemented
    /// The system denied access to now-playing info.
    case permissionDenied
    /// The system reported the service as unavailable.
    case unavailable
}
