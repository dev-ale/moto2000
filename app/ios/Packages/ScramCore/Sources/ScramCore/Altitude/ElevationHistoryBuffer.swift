import Foundation
import BLEProtocol

/// Pure value-type that accumulates elevation samples from a ride and
/// produces downsampled altitude profile snapshots for the BLE wire format.
///
/// Stores the full altitude trace (every sample fed via ``ingesting(_:)``).
/// When converting to ``AltitudeProfileData`` via ``snapshot``, the trace
/// is binned into at most ``maxSamples`` (60) evenly-spaced buckets by
/// averaging altitudes within each bucket.
///
/// Ascent/descent are tracked incrementally using the same jitter threshold
/// as ``TripStatsAccumulator`` (1m) to filter GPS noise.
public struct ElevationHistoryBuffer: Sendable, Equatable {
    /// Maximum number of samples in the downsampled profile.
    public static let maxSamples = 60

    /// Altitude deltas under this many metres are treated as GPS jitter
    /// and discarded for ascent/descent accounting.
    public static let altitudeJitterThresholdMeters: Double = 1.0

    /// Raw altitude readings from every location sample.
    public private(set) var samples: [Double]
    /// Cumulative ascent in metres (jitter-filtered).
    public private(set) var totalAscentMeters: Double
    /// Cumulative descent in metres (jitter-filtered).
    public private(set) var totalDescentMeters: Double
    /// The most recently ingested altitude, or nil if no samples yet.
    public private(set) var lastAltitude: Double?

    public init() {
        self.samples = []
        self.totalAscentMeters = 0
        self.totalDescentMeters = 0
        self.lastAltitude = nil
    }

    /// Returns a new buffer that includes the given altitude reading.
    /// Pure: does not mutate `self`.
    public func ingesting(_ altitudeMeters: Double) -> ElevationHistoryBuffer {
        var next = self
        next.samples.append(altitudeMeters)

        if let previous = lastAltitude {
            let delta = altitudeMeters - previous
            if delta > Self.altitudeJitterThresholdMeters {
                next.totalAscentMeters += delta
            } else if delta < -Self.altitudeJitterThresholdMeters {
                next.totalDescentMeters += -delta
            }
        }

        next.lastAltitude = altitudeMeters
        return next
    }

    /// Downsample the full altitude history into `count` evenly-spaced
    /// buckets. Each bucket is the average altitude of all samples that
    /// fall into that time window.
    ///
    /// If fewer samples exist than `count`, returns one Int16 per sample.
    public func downsampled(to count: Int) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let n = min(count, samples.count)
        if n == samples.count {
            // Fewer samples than buckets: return all of them.
            return samples.map { clampToInt16($0) }
        }

        var result = [Int16]()
        result.reserveCapacity(n)
        let samplesPerBucket = Double(samples.count) / Double(n)
        for i in 0..<n {
            let startIdx = Int((Double(i) * samplesPerBucket).rounded(.down))
            let endIdx = Int((Double(i + 1) * samplesPerBucket).rounded(.down))
            let clamped = min(endIdx, samples.count)
            let slice = samples[startIdx..<clamped]
            if slice.isEmpty {
                result.append(0)
            } else {
                let avg = slice.reduce(0.0, +) / Double(slice.count)
                result.append(clampToInt16(avg))
            }
        }
        return result
    }

    /// Convert the current buffer state to the BLE wire format.
    public var snapshot: AltitudeProfileData {
        let currentAlt: Int16
        if let last = lastAltitude {
            currentAlt = clampToInt16(last)
        } else {
            currentAlt = 0
        }

        let profileBins = downsampled(to: Self.maxSamples)
        let sampleCount = UInt8(min(profileBins.count, Self.maxSamples))

        // Pad to 60 entries.
        var profile = profileBins
        while profile.count < Self.maxSamples {
            profile.append(0)
        }

        return AltitudeProfileData(
            currentAltitudeM: clampInt16(currentAlt, min: -500, max: 9000),
            totalAscentM: clampUInt16(totalAscentMeters),
            totalDescentM: clampUInt16(totalDescentMeters),
            sampleCount: sampleCount,
            profile: profile
        )
    }

    // MARK: - Clamping helpers

    private func clampToInt16(_ value: Double) -> Int16 {
        if value <= Double(Int16.min) { return Int16.min }
        if value >= Double(Int16.max) { return Int16.max }
        return Int16(value.rounded())
    }

    private func clampInt16(_ value: Int16, min lo: Int16, max hi: Int16) -> Int16 {
        if value < lo { return lo }
        if value > hi { return hi }
        return value
    }

    private func clampUInt16(_ value: Double) -> UInt16 {
        if value <= 0 { return 0 }
        if value >= Double(UInt16.max) { return UInt16.max }
        return UInt16(value.rounded())
    }
}
