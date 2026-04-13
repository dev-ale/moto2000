import CryptoKit
import Foundation

/// Streams a firmware image to the ESP32 over the BLE `ota_data`
/// characteristic via a caller-provided send closure.
///
/// Wire format mirrors `components/ota_receiver` on the firmware side:
///
///   BEGIN  : [0x01][size:4 LE][sha256:32]
///   CHUNK  : [0x02][bytes…]
///   COMMIT : [0x03]
///   ABORT  : [0x04]
///
/// Decoupled from `BLECentralClient` so ScramCore stays transport-agnostic
/// — the caller passes a `send` closure that wraps `client.sendOTA(_:)`.
public actor OTAUploader {
    public enum State: Equatable, Sendable {
        case idle
        case uploading(bytesSent: Int, totalBytes: Int)
        case finalizing
        case completed
        case failed(reason: String)
    }

    public private(set) var state: State = .idle

    public typealias SendBlock = @Sendable (Data) async throws -> Void
    public typealias ProgressBlock = @Sendable (State) -> Void

    /// Maximum chunk size — keep below the negotiated MTU (256) minus the
    /// 1-byte frame type, the 3-byte ATT header, and a safety margin.
    public static let chunkBodyBytes = 240

    public init() {}

    /// Run the full upload flow. Returns when COMMIT has been sent
    /// (the firmware reboots after that).
    public func upload(
        firmware: Data,
        send: SendBlock,
        progress: ProgressBlock? = nil
    ) async throws {
        guard !firmware.isEmpty else {
            state = .failed(reason: "empty firmware")
            throw UploadError.emptyFirmware
        }

        let total = firmware.count
        let digest = SHA256.hash(data: firmware)
        let hashBytes = Data(digest)

        // BEGIN frame
        var begin = Data()
        begin.append(0x01)
        var size32 = UInt32(total).littleEndian
        withUnsafeBytes(of: &size32) { begin.append(contentsOf: $0) }
        begin.append(hashBytes)
        try await send(begin)

        // Initial progress update
        state = .uploading(bytesSent: 0, totalBytes: total)
        progress?(state)

        // CHUNK frames. We throttle to ~5 ms per chunk so the firmware's
        // NimBLE ACL buffer pool has time to drain — sending faster
        // than that exhausts it within seconds and the link dies
        // mid-update with "ACL buf alloc failed".
        var offset = 0
        while offset < total {
            let end = min(offset + Self.chunkBodyBytes, total)
            var frame = Data(capacity: end - offset + 1)
            frame.append(0x02)
            frame.append(firmware[offset..<end])
            try await send(frame)
            // 20 ms throttle: 1 MB / (240 B / 20 ms) ≈ 88 s. Slower
            // than 5 ms but well under the firmware's NimBLE buffer
            // drain rate so we don't exhaust the ACL pools.
            try? await Task.sleep(nanoseconds: 20_000_000)
            offset = end
            state = .uploading(bytesSent: offset, totalBytes: total)
            progress?(state)
        }

        // COMMIT frame — firmware verifies SHA256 and reboots.
        state = .finalizing
        progress?(state)
        var commit = Data()
        commit.append(0x03)
        try await send(commit)

        state = .completed
        progress?(state)
    }

    /// Send an ABORT frame. Use if the user cancels mid-flight.
    public func abort(send: SendBlock) async {
        var frame = Data()
        frame.append(0x04)
        _ = try? await send(frame)
        state = .idle
    }

    public enum UploadError: Error, Sendable, Equatable {
        case emptyFirmware
    }
}
