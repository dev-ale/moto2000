import Foundation

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer

/// iOS ``NowPlayingClient`` backed by ``MPNowPlayingInfoCenter``.
///
/// Reads the system now-playing info dictionary and playback state to
/// build a ``NowPlayingClientResponse``. Returns `nil` when no track
/// metadata is available (e.g. nothing is playing). Missing fields are
/// handled gracefully — title falls back to `"Unknown"`, artist and
/// album fall back to empty strings, and position/duration are `nil`
/// when unreported.
public final class MediaPlayerNowPlayingClient: NowPlayingClient, @unchecked Sendable {
    public init() {}

    public func fetchNowPlaying() async throws -> NowPlayingClientResponse? {
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard let info = infoCenter.nowPlayingInfo else {
            return nil
        }

        let title = info[MPMediaItemPropertyTitle] as? String ?? "Unknown"
        let artist = info[MPMediaItemPropertyArtist] as? String ?? ""
        let album = info[MPMediaItemPropertyAlbumTitle] as? String ?? ""

        let duration = info[MPMediaItemPropertyPlaybackDuration] as? Double
        let elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double

        let playbackState = infoCenter.playbackState
        let isPlaying = playbackState == .playing

        return NowPlayingClientResponse(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            positionSeconds: elapsed,
            durationSeconds: duration
        )
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
