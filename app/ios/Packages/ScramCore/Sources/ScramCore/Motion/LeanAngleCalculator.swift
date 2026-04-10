import Foundation
import BLEProtocol
import RideSimulatorKit

/// Pure-value lean-angle estimator that consumes ``MotionSample`` values
/// and tracks the current lean, the historical max-left and max-right
/// extremes, and a confidence score derived from non-gravitational
/// acceleration.
///
/// **Sign convention** (locked in by Slice 10):
///   - `currentLeanDegrees > 0`  →  bike leaning **right**
///   - `currentLeanDegrees < 0`  →  bike leaning **left**
///   - `currentLeanDegrees == 0` →  upright
/// This matches the wire format in `LeanAngleData.currentLeanDegX10`.
///
/// **Phone mount assumption**: portrait orientation on the bars. In the
/// iPhone reference frame, +X grows toward the right edge of the screen
/// and +Y grows toward the top. With the bike upright the gravity vector
/// is roughly `(0, -1, 0)`. When the bike leans right, the right edge of
/// the device tilts down so gravity gains a *negative* X component; when
/// it leans left, gravity gains a positive X component. The formula
/// below maps that to the wire convention:
///
///     leanDegrees = atan2(-gravityX, -gravityY) * 180/π
///
/// This is a pure value type — no actor, no mutable storage outside the
/// `private(set)` fields. Use ``ingesting(_:)`` to fold a sample in and
/// receive a fresh calculator.
public struct LeanAngleCalculator: Sendable, Equatable {
    /// Exponential-moving-average smoothing factor in `(0, 1]`.
    /// Higher = more responsive, lower = more smoothing. 0.2 keeps the
    /// dial readable on a jittery handlebar mount without adding more
    /// than ~50 ms of perceived lag at our 50 Hz sample rate.
    public static let defaultSmoothingAlpha: Double = 0.2

    /// User-acceleration magnitude (in G) at which confidence drops to 0.
    /// Hard braking and bumps push `userAcceleration` past 0.5 G; we want
    /// the lean readout to wave a flag long before that point.
    public static let confidenceCutoffG: Double = 0.5

    public private(set) var currentLeanDegrees: Double
    public private(set) var maxLeftLeanDegrees: Double
    public private(set) var maxRightLeanDegrees: Double
    public private(set) var confidencePercent: UInt8
    public private(set) var samplesSeen: UInt32

    public let smoothingAlpha: Double

    public init(smoothingAlpha: Double = LeanAngleCalculator.defaultSmoothingAlpha) {
        self.currentLeanDegrees = 0
        self.maxLeftLeanDegrees = 0
        self.maxRightLeanDegrees = 0
        self.confidencePercent = 100
        self.samplesSeen = 0
        self.smoothingAlpha = smoothingAlpha
    }

    /// Fold a sample into the calculator and return the updated value.
    public func ingesting(_ sample: MotionSample) -> LeanAngleCalculator {
        // Raw lean from the gravity vector. See doc comment for the
        // sign-convention derivation.
        let rawDegrees = atan2(-sample.gravityX, -sample.gravityY) * 180.0 / .pi

        // Smoothing: first sample seeds the EMA, subsequent samples
        // blend toward the new reading.
        let smoothed: Double
        if samplesSeen == 0 {
            smoothed = rawDegrees
        } else {
            smoothed = currentLeanDegrees * (1.0 - smoothingAlpha) + rawDegrees * smoothingAlpha
        }

        // Clamp to the wire range (±90°). Anything beyond ±90° is either
        // a phone that fell off the bars or a crashed bike — clipping is
        // a safer default than relying on the codec to throw later.
        let clamped = min(max(smoothed, -90.0), 90.0)

        // Max tracking. Wire format stores the magnitudes as separate
        // unsigned fields so we keep them in sync here.
        var newMaxLeft = maxLeftLeanDegrees
        var newMaxRight = maxRightLeanDegrees
        if clamped > newMaxRight {
            newMaxRight = clamped
        }
        if -clamped > newMaxLeft {
            newMaxLeft = -clamped
        }

        // Confidence: drops linearly with userAccel magnitude until it
        // hits 0 at `confidenceCutoffG`. Mounted compass / IMU jitter
        // typically lives well under 0.1 G so the dial stays at 100% on
        // a steady cruise.
        let ux = sample.userAccelX
        let uy = sample.userAccelY
        let uz = sample.userAccelZ
        let userAccelMagnitude = (ux * ux + uy * uy + uz * uz).squareRoot()
        let confidenceDouble = max(
            0.0,
            100.0 - userAccelMagnitude * (100.0 / Self.confidenceCutoffG)
        )
        let confidenceRounded = Int(confidenceDouble.rounded())
        let newConfidence = UInt8(min(100, max(0, confidenceRounded)))

        var next = self
        next.currentLeanDegrees = clamped
        next.maxLeftLeanDegrees = newMaxLeft
        next.maxRightLeanDegrees = newMaxRight
        next.confidencePercent = newConfidence
        next.samplesSeen = samplesSeen &+ 1
        return next
    }

    /// Return a fresh calculator with all rolling state reset to zero,
    /// preserving the original smoothing alpha so callers don't need to
    /// re-thread it.
    public func reset() -> LeanAngleCalculator {
        LeanAngleCalculator(smoothingAlpha: smoothingAlpha)
    }

    /// Snapshot the current state in the wire-ready ``LeanAngleData``
    /// shape, with all values clamped/rounded to fit the codec's range.
    public var snapshot: LeanAngleData {
        let currentX10 = Int((currentLeanDegrees * 10).rounded())
        let leftX10 = Int((maxLeftLeanDegrees * 10).rounded())
        let rightX10 = Int((maxRightLeanDegrees * 10).rounded())
        let maxAbs = Int(LeanAngleData.maxAbsoluteLeanX10)
        let clampedCurrent = Int16(min(maxAbs, max(-maxAbs, currentX10)))
        let clampedLeft = UInt16(min(maxAbs, max(0, leftX10)))
        let clampedRight = UInt16(min(maxAbs, max(0, rightX10)))
        return LeanAngleData(
            currentLeanDegX10: clampedCurrent,
            maxLeftLeanDegX10: clampedLeft,
            maxRightLeanDegX10: clampedRight,
            confidencePercent: confidencePercent
        )
    }
}
