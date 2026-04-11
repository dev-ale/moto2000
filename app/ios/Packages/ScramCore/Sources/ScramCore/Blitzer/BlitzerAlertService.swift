import Foundation
import BLEProtocol
import RideSimulatorKit

/// Monitors GPS location and emits encoded BLE blitzer payloads when the
/// rider approaches a known speed camera.
///
/// Key behaviour:
/// - On each location sample, queries the database for cameras within the
///   alert radius.
/// - If a camera is found within range, encodes a `BlitzerData` payload
///   with the `ALERT` flag set and emits it.
/// - If no camera is in range AND the previous emission had `ALERT` set,
///   emits one final payload with `ALERT` cleared (to tell the ESP32 to
///   dismiss the overlay).
/// - Configurable via ``BlitzerSettings``.
public actor BlitzerAlertService {
    private let locationProvider: any LocationProvider
    private let database: any SpeedCameraDatabase
    private let settings: BlitzerSettings
    private let channel = PayloadChannelHelper()

    /// Encoded BLE payloads ready to write to the peripheral.
    public nonisolated let payloads: AsyncStream<Data>

    private var monitorTask: Task<Void, Never>?
    private var lastEmittedAlert = false

    public init(
        locationProvider: any LocationProvider,
        database: any SpeedCameraDatabase,
        settings: BlitzerSettings = BlitzerSettings()
    ) {
        self.locationProvider = locationProvider
        self.database = database
        self.settings = settings
        self.payloads = channel.makeStream()
    }

    public func start() {
        guard monitorTask == nil else { return }
        let stream = locationProvider.samples
        monitorTask = Task { [weak self] in
            for await sample in stream {
                guard let self else { return }
                await self.handleLocation(sample)
            }
            await self?.finish()
        }
    }

    public func stop() {
        let task = monitorTask
        monitorTask = nil
        task?.cancel()
        channel.finish()
    }

    // MARK: - Private

    private func handleLocation(_ sample: LocationSample) async {
        guard settings.enabled else { return }

        let cameras: [SpeedCamera]
        do {
            cameras = try await database.camerasNear(
                latitude: sample.latitude,
                longitude: sample.longitude,
                radiusMeters: settings.alertRadiusMeters
            )
        } catch {
            return
        }

        // Pass rider heading for direction-aware filtering.
        // courseDegrees < 0 means invalid (stationary) — pass nil to skip filter.
        let heading: Double? = sample.courseDegrees >= 0 ? sample.courseDegrees : nil

        let result = ProximityCalculator.findNearest(
            cameras: cameras,
            latitude: sample.latitude,
            longitude: sample.longitude,
            alertRadiusMeters: settings.alertRadiusMeters,
            riderHeadingDegrees: heading
        )

        if let result, result.isInAlertRange, let camera = result.nearestCamera {
            let currentSpeedKmhX10 = sample.speedMps >= 0
                ? UInt16(clamping: Int(round(sample.speedMps * 3.6 * 10)))
                : 0

            let cameraTypeWire: BlitzerData.CameraTypeWire
            switch camera.cameraType {
            case .fixed: cameraTypeWire = .fixed
            case .mobile: cameraTypeWire = .mobile
            case .redLight: cameraTypeWire = .redLight
            case .section: cameraTypeWire = .section
            case .unknown: cameraTypeWire = .unknown
            }

            let blitzer = BlitzerData(
                distanceMeters: UInt16(clamping: Int(round(result.distanceMeters))),
                speedLimitKmh: camera.speedLimitKmh ?? BlitzerData.unknownSpeedLimit,
                currentSpeedKmhX10: currentSpeedKmhX10,
                cameraType: cameraTypeWire
            )

            if let data = encodePayload(blitzer, alert: true) {
                channel.emit(data)
                lastEmittedAlert = true
            }
        } else if lastEmittedAlert {
            // Emit a clear payload — no camera in range, dismiss the overlay.
            let blitzer = BlitzerData(
                distanceMeters: 0xFFFF,
                speedLimitKmh: BlitzerData.unknownSpeedLimit,
                currentSpeedKmhX10: 0,
                cameraType: .unknown
            )
            if let data = encodePayload(blitzer, alert: false) {
                channel.emit(data)
            }
            lastEmittedAlert = false
        }
    }

    private func finish() {
        channel.finish()
    }

    private nonisolated func encodePayload(_ blitzer: BlitzerData, alert: Bool) -> Data? {
        let flags: ScreenFlags = alert ? [.alert] : []
        return try? ScreenPayloadCodec.encode(.blitzer(blitzer, flags: flags))
    }
}

/// A simple AsyncStream-backed channel for emitting Data payloads.
/// Same pattern as the one in SpeedHeadingService.
private final class PayloadChannelHelper: @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<Data> {
        AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: Data) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(element)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
