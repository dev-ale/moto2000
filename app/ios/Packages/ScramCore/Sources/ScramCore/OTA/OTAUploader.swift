import CryptoKit
import Foundation

/// Triggers a WiFi-HTTPS OTA on the firmware by writing three small
/// frames to the BLE `ota_data` characteristic:
///
///   0x20 SET_SSID   body = ssid bytes
///   0x21 SET_PWD    body = password bytes
///   0x22 BEGIN_OTA  body = URL bytes
///
/// The firmware stores the credentials in NVS, connects to WiFi,
/// downloads the firmware from the URL, applies it, and reboots.
/// Progress is reported back over the BLE status characteristic and
/// also rendered directly on the display.
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

    /// Send the WiFi credentials + the firmware download URL to the
    /// firmware. Returns immediately after the URL frame is acked —
    /// the actual download + flash + reboot happen on the firmware side
    /// over WiFi and progress is reported via the BLE status channel.
    public func startWifiOTA(
        ssid: String,
        password: String,
        url: URL,
        send: SendBlock,
        progress: ProgressBlock? = nil
    ) async throws {
        guard !ssid.isEmpty else {
            state = .failed(reason: "missing WiFi SSID")
            throw UploadError.missingCredentials
        }

        // Each frame is one BLE write to the ota_data characteristic.
        // Body bytes are raw (no length prefix — frame length = body
        // length + 1 type byte).
        let ssidFrame = Data([0x20]) + Data(ssid.utf8)
        let pwdFrame = Data([0x21]) + Data(password.utf8)
        let urlFrame = Data([0x22]) + Data(url.absoluteString.utf8)

        state = .uploading(bytesSent: 0, totalBytes: 3)
        progress?(state)
        try await send(ssidFrame)

        state = .uploading(bytesSent: 1, totalBytes: 3)
        progress?(state)
        try await send(pwdFrame)

        state = .uploading(bytesSent: 2, totalBytes: 3)
        progress?(state)
        try await send(urlFrame)

        state = .finalizing
        progress?(state)
    }

    public enum UploadError: Error, Sendable, Equatable {
        case missingCredentials
    }
}
