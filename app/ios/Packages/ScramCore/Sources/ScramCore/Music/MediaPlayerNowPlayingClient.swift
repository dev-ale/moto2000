import Foundation

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer

/// iOS-only stub for ``NowPlayingClient``.
///
/// # Why is this a stub?
///
/// Accessing `MPNowPlayingInfoCenter.default().nowPlayingInfo` from a
/// *non-Now-Playing-app* context is restricted by iOS: reads only return
/// data the current process itself has published. Third-party players
/// like Spotify never expose their metadata through that API from another
/// app. A real integration therefore has to pick one of:
///
///   1. Make ScramScreen itself the Now Playing source (playing audio in
///      our process) — wrong for a motorcycle dashboard.
///   2. Use ``MPMusicPlayerController`` (system music player), which only
///      sees tracks played through the Apple Music app and needs
///      `NSAppleMusicUsageDescription` plus user consent.
///   3. Ask the user to pair ScramScreen with a Media Remote private API
///      — off limits for App Store submission.
///
/// Slice 8 ships the ``NowPlayingClient`` protocol seam so the rest of
/// the domain (``RealNowPlayingProvider``, ``MusicService``, the BLE
/// pipeline) can be fully tested today. A follow-up slice will wire one
/// of the options above. Until then this client always throws
/// ``NowPlayingClientError/notImplemented``.
public final class MediaPlayerNowPlayingClient: NowPlayingClient, @unchecked Sendable {
    public init() {}

    public func fetchNowPlaying() async throws -> NowPlayingClientResponse? {
        throw NowPlayingClientError.notImplemented
    }
}
#else

/// Non-iOS platforms never have MediaPlayer; the type exists only so code
/// that references it compiles on macOS unit tests. It also throws
/// ``NowPlayingClientError/notImplemented`` so callers cannot
/// accidentally depend on it.
public final class MediaPlayerNowPlayingClient: NowPlayingClient, @unchecked Sendable {
    public init() {}

    public func fetchNowPlaying() async throws -> NowPlayingClientResponse? {
        throw NowPlayingClientError.notImplemented
    }
}
#endif
