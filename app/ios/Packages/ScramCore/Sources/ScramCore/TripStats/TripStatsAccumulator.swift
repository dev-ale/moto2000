import Foundation
import BLEProtocol
import RideSimulatorKit

/// Pure value-type that accumulates ride statistics from a stream of
/// ``LocationSample`` values.
///
/// "Pure" means: every mutation returns a new value (no in-place
/// state on the caller side), every field is publicly observable, and
/// the snapshot conversion to the wire format is a deterministic
/// function of the accumulator alone. The accumulator does not
/// subscribe to any provider — that's ``TripStatsService``'s job.
///
/// Accounting rules:
///   - **Distance**: haversine distance between consecutive
///     ``LocationSample`` coordinates is added unconditionally.
///   - **Ride time**: sum of *positive* `Δt` between consecutive
///     samples. This means scenario gaps (where the player skips
///     ahead in time but does not emit samples) do **not** inflate
///     ride time. Going backwards in time is treated as a zero-delta.
///   - **Max speed**: tracks the maximum of `sample.speedMps * 3.6`
///     across every sample whose `speedMps >= 0`. Negative
///     "unknown" sentinels are skipped for max-speed *only*; the
///     sample still contributes to distance via its coordinates.
///   - **Average speed**: not stored. ``snapshot`` derives it from
///     `distanceMeters / rideTimeSeconds * 3.6`. Avoiding a separate
///     running mean keeps the accumulator immune to sample-rate
///     sensitivity.
///   - **Ascent / descent**: altitude deltas between consecutive
///     samples. Deltas with magnitude under
///     ``altitudeJitterThresholdMeters`` are ignored to suppress GPS
///     noise. Positive deltas add to ascent, negative deltas add their
///     magnitude to descent.
public struct TripStatsAccumulator: Sendable, Equatable {
    /// Altitude deltas under this many metres are treated as GPS jitter
    /// and discarded for ascent/descent accounting.
    public static let altitudeJitterThresholdMeters: Double = 1.0

    public private(set) var rideTimeSeconds: UInt32
    public private(set) var distanceMeters: Double
    public private(set) var maxSpeedKmh: Double
    public private(set) var ascentMeters: Double
    public private(set) var descentMeters: Double
    public private(set) var lastSample: LocationSample?

    public init() {
        self.rideTimeSeconds = 0
        self.distanceMeters = 0
        self.maxSpeedKmh = 0
        self.ascentMeters = 0
        self.descentMeters = 0
        self.lastSample = nil
    }

    /// Returns a new accumulator that includes `sample`. Pure: leaves
    /// `self` untouched.
    public func ingesting(_ sample: LocationSample) -> TripStatsAccumulator {
        var next = self

        if let previous = lastSample {
            // Distance — only when actually moving (filter GPS noise at standstill).
            let distance = GeoMath.haversineMeters(
                lat1: previous.latitude, lon1: previous.longitude,
                lat2: sample.latitude, lon2: sample.longitude
            )
            if sample.speedMps > 1.0 {
                next.distanceMeters += distance
            }

            // Time — positive deltas only.
            let dt = sample.scenarioTime - previous.scenarioTime
            if dt > 0 {
                let added = next.rideTimeSeconds &+ UInt32(min(max(dt, 0), Double(UInt32.max)))
                next.rideTimeSeconds = added
            }

            // Ascent / descent — discard jitter.
            let dAlt = sample.altitudeMeters - previous.altitudeMeters
            if dAlt > Self.altitudeJitterThresholdMeters {
                next.ascentMeters += dAlt
            } else if dAlt < -Self.altitudeJitterThresholdMeters {
                next.descentMeters += -dAlt
            }
        }

        // Max speed — every sample whose speed is known.
        if sample.speedMps >= 0 {
            let kmh = sample.speedMps * 3.6
            if kmh > next.maxSpeedKmh {
                next.maxSpeedKmh = kmh
            }
        }

        next.lastSample = sample
        return next
    }

    /// Returns a fresh, zeroed accumulator. Convenience for "new trip"
    /// flows that prefer the value-style API over `init()`.
    public func reset() -> TripStatsAccumulator {
        TripStatsAccumulator()
    }

    /// The wire-format snapshot. All values are clamped into the
    /// payload's `uint16` / `uint32` ranges. Average speed is computed
    /// from totals so it never drifts from `distance / time`.
    public var snapshot: TripStatsData {
        let avgKmh: Double
        if rideTimeSeconds > 0 {
            avgKmh = (distanceMeters / Double(rideTimeSeconds)) * 3.6
        } else {
            avgKmh = 0
        }
        let avgX10 = clampUInt16(round(avgKmh * 10), upperBound: 3000)
        let maxX10 = clampUInt16(round(maxSpeedKmh * 10), upperBound: 3000)
        let distanceClamped = clampUInt32(round(distanceMeters))
        let ascent = clampUInt16(round(ascentMeters), upperBound: UInt16.max)
        let descent = clampUInt16(round(descentMeters), upperBound: UInt16.max)
        return TripStatsData(
            rideTimeSeconds: rideTimeSeconds,
            distanceMeters: distanceClamped,
            averageSpeedKmhX10: avgX10,
            maxSpeedKmhX10: maxX10,
            ascentMeters: ascent,
            descentMeters: descent
        )
    }

    // MARK: - clamping helpers

    private func clampUInt16(_ value: Double, upperBound: UInt16) -> UInt16 {
        if value <= 0 { return 0 }
        if value >= Double(upperBound) { return upperBound }
        return UInt16(value)
    }

    private func clampUInt32(_ value: Double) -> UInt32 {
        if value <= 0 { return 0 }
        if value >= Double(UInt32.max) { return UInt32.max }
        return UInt32(value)
    }
}
