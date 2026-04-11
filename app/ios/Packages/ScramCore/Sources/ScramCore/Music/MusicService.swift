import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``NowPlayingSnapshot`` values from any ``NowPlayingProvider``
/// into encoded BLE payloads for the `music` screen, and exposes them as
/// an ``AsyncStream`` of `Data` blobs ready to write to the peripheral.
///
/// Transform rules:
///  - `title`/`artist`/`album`: UTF-8 truncated so the encoded form fits
///    within the wire field length (31/23/23 bytes respectively — one
///    byte is reserved for the terminator). Truncation is byte-accurate
///    and will not split a multi-byte UTF-8 sequence.
///  - `positionSeconds` / `durationSeconds`:
///    - Values `< 0` (the "unknown" convention from the scripted
///      scenario snapshots) map to the `0xFFFF` wire sentinel.
///    - Non-negative values are clamped to `0...65534` and rounded.
///  - `isPlaying` → `BLE_MUSIC_FLAG_PLAYING`.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. Calling ``stop()`` terminates both the
/// forwarding task and the output stream.
public final class MusicService: PayloadService, @unchecked Sendable {
    private let provider: any NowPlayingProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    private let lock = NSLock()
    private var forwardingTask: Task<Void, Never>?

    public init(provider: any NowPlayingProvider) {
        self.provider = provider
        self.encodedPayloads = channel.makeStream()
    }

    public func start() {
        lock.lock()
        guard forwardingTask == nil else {
            lock.unlock()
            return
        }
        let stream = provider.snapshots
        forwardingTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                if let data = self.encode(snapshot) {
                    self.channel.emit(data)
                }
            }
            self?.channel.finish()
        }
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let task = forwardingTask
        forwardingTask = nil
        lock.unlock()
        task?.cancel()
        channel.finish()
    }

    // MARK: - Transform

    func encode(_ snapshot: NowPlayingSnapshot) -> Data? {
        let flags: UInt8 = snapshot.isPlaying ? MusicData.playingFlag : 0
        let position = Self.packSeconds(snapshot.positionSeconds)
        let duration = Self.packSeconds(snapshot.durationSeconds)
        let title = Self.truncateUTF8(
            snapshot.title,
            maxByteCount: MusicData.titleFieldLength - 1
        )
        let artist = Self.truncateUTF8(
            snapshot.artist,
            maxByteCount: MusicData.artistFieldLength - 1
        )
        let album = Self.truncateUTF8(
            snapshot.album,
            maxByteCount: MusicData.albumFieldLength - 1
        )
        let data = MusicData(
            musicFlags: flags,
            positionSeconds: position,
            durationSeconds: duration,
            title: title,
            artist: artist,
            album: album
        )
        do {
            return try ScreenPayloadCodec.encode(.music(data, flags: []))
        } catch {
            return nil
        }
    }

    /// Packs a `Double` seconds value into the wire `uint16`. Negative
    /// values (the "unknown" convention) map to the `0xFFFF` sentinel.
    /// Finite positive values are rounded and clamped to `0...65534` so
    /// they never collide with the sentinel.
    static func packSeconds(_ value: Double) -> UInt16 {
        if !value.isFinite || value < 0 {
            return MusicData.unknownU16
        }
        let rounded = value.rounded()
        if rounded >= 65535 {
            return 65534
        }
        return UInt16(rounded)
    }

    /// Truncates `value` to at most `maxByteCount` UTF-8 bytes without
    /// splitting a multi-byte scalar. Returns the (possibly unchanged)
    /// truncated string.
    static func truncateUTF8(_ value: String, maxByteCount: Int) -> String {
        if value.utf8.count <= maxByteCount {
            return value
        }
        var result = ""
        var total = 0
        for scalar in value.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if total + scalarBytes > maxByteCount {
                break
            }
            result.unicodeScalars.append(scalar)
            total += scalarBytes
        }
        return result
    }
}
