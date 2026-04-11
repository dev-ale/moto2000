import Foundation
import BLEProtocol
import RideSimulatorKit

/// Combines location tracking (for distance since last fill), the fuel log,
/// and the range calculator to emit encoded `fuelEstimate` BLE payloads.
///
/// The service tracks cumulative distance from GPS samples since the last
/// ``resetDistance()`` call (which the app should invoke when a fill is logged).
/// It emits one fuel payload per location sample, matching the cadence of
/// ``TripStatsService``.
public final class FuelService: PayloadService, @unchecked Sendable {
    private let provider: any LocationProvider
    private let fuelLog: FuelLog
    private let settings: FuelSettings
    private let channel = PayloadChannel()
    public let payloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { payloads }

    private let lock = NSLock()
    private var distanceKm: Double = 0
    private var lastSample: LocationSample?
    private var forwardingTask: Task<Void, Never>?

    public init(
        provider: any LocationProvider,
        fuelLog: FuelLog,
        settings: FuelSettings = FuelSettings()
    ) {
        self.provider = provider
        self.fuelLog = fuelLog
        self.settings = settings
        self.payloads = channel.makeStream()
    }

    public func start() {
        lock.lock()
        let alreadyStarted = forwardingTask != nil
        lock.unlock()
        if alreadyStarted { return }

        let stream = provider.samples
        let task = Task { [weak self] in
            for await sample in stream {
                guard let self else { return }
                await self.ingest(sample)
            }
            self?.channel.finish()
        }
        lock.lock()
        forwardingTask = task
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

    /// Reset distance tracking (call after logging a fill).
    public func resetDistance() {
        lock.lock()
        distanceKm = 0
        lastSample = nil
        lock.unlock()
    }

    /// Current tracked distance in km.
    public var currentDistanceKm: Double {
        lock.lock()
        defer { lock.unlock() }
        return distanceKm
    }

    /// Ingest a location sample: update distance, then compute and emit
    /// a fuel payload. The distance tracking is synchronous; the log
    /// query is async.
    func ingest(_ sample: LocationSample) async {
        let dist = updateDistance(with: sample)

        // Compute estimate from log
        let fills: [FuelFillEntry]
        do {
            fills = try await fuelLog.allEntries()
        } catch {
            return
        }

        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: dist,
            settings: settings
        )

        let fuelData = FuelData(
            tankPercent: estimate.tankPercent.map { UInt8(min(max($0.rounded(), 0), 100)) } ?? 0,
            estimatedRangeKm: estimate.rangeKm.map { UInt16(min(max($0.rounded(), 0), Double(UInt16.max - 1))) } ?? FuelData.unknown,
            consumptionMlPerKm: estimate.consumptionMlPerKm.map { UInt16(min(max($0.rounded(), 0), Double(UInt16.max - 1))) } ?? FuelData.unknown,
            fuelRemainingMl: estimate.remainingMl.map { UInt16(min(max($0.rounded(), 0), Double(UInt16.max - 1))) } ?? FuelData.unknown
        )

        do {
            let blob = try ScreenPayloadCodec.encode(.fuelEstimate(fuelData, flags: []))
            channel.emit(blob)
        } catch {
            // Encoding should not fail after clamping — drop on the impossible path.
        }
    }

    /// Update cumulative distance from a location sample. Returns the
    /// current distance in km. Runs synchronously under the lock.
    private func updateDistance(with sample: LocationSample) -> Double {
        lock.lock()
        defer { lock.unlock() }
        if let previous = lastSample {
            let meters = GeoMath.haversineMeters(
                lat1: previous.latitude, lon1: previous.longitude,
                lat2: sample.latitude, lon2: sample.longitude
            )
            distanceKm += meters / 1000.0
        }
        lastSample = sample
        return distanceKm
    }
}
