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
/// **Calibration modes:**
///
/// - `.fixed` (default): Phone is mounted portrait on the bars. Gravity
///   vector `(0, -1, 0)` is the upright reference. This is the legacy
///   behaviour and all existing tests continue to use it.
///
/// - `.autoCalibrate`: Phone is in an unknown orientation (e.g. pocket).
///   The calculator starts with `confidence = 0` ("Kalibrierung...") and
///   waits for straight riding (speed > 20 km/h, heading variance < 5°
///   over 5 s) before capturing the current gravity vector as the upright
///   reference. Recalibrates every 10 minutes.
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

    /// Minimum speed (km/h) required for straight-riding detection.
    public static let calibrationMinSpeedKmh: Double = 20.0

    /// Maximum heading standard deviation (degrees) over the window for
    /// the segment to count as "straight".
    public static let calibrationMaxHeadingStdDev: Double = 5.0

    /// Duration of the heading window used for straight-riding detection.
    public static let calibrationWindowSeconds: Double = 5.0

    /// Interval between automatic recalibrations.
    public static let recalibrationIntervalSeconds: Double = 600.0 // 10 min

    // MARK: - Calibration mode

    /// Whether the calculator uses a fixed upright assumption or
    /// auto-calibrates from GPS + gravity data.
    public enum CalibrationMode: Sendable, Equatable {
        /// Legacy: phone mounted portrait on bars. No GPS needed.
        case fixed
        /// Pocket / unknown orientation: needs GPS to detect straight riding.
        case autoCalibrate
    }

    public let calibrationMode: CalibrationMode

    // MARK: - Public rolling state

    public private(set) var currentLeanDegrees: Double
    public private(set) var maxLeftLeanDegrees: Double
    public private(set) var maxRightLeanDegrees: Double
    public private(set) var confidencePercent: UInt8
    public private(set) var samplesSeen: UInt32

    public let smoothingAlpha: Double

    // MARK: - Auto-calibration internal state

    /// The captured upright gravity reference vector (x, y, z).
    /// `nil` means not yet calibrated (only relevant in `.autoCalibrate`).
    public private(set) var referenceGravity: (x: Double, y: Double, z: Double)?

    /// Whether auto-calibration has completed at least once.
    public var isCalibrated: Bool { referenceGravity != nil }

    /// Ring buffer of (scenarioTime, headingDegrees) pairs for the last
    /// `calibrationWindowSeconds`. Kept sorted by time (oldest first).
    private var headingBuffer: [(time: Double, heading: Double)]

    /// Ring buffer of recent gravity vectors, accumulated alongside heading
    /// samples so we can average them when calibration triggers.
    private var gravityBuffer: [(time: Double, x: Double, y: Double, z: Double)]

    /// The most recent speed value from GPS, in km/h.
    private var lastSpeedKmh: Double

    /// Scenario time at which the last calibration was performed.
    private var lastCalibrationTime: Double?

    /// Whether we are currently seeking a new calibration (either initial
    /// or periodic recalibration).
    private var seekingCalibration: Bool

    // MARK: - Background mode

    /// When `true`, the calculator skips samples to reduce effective rate
    /// to ~5 Hz.  The decimation counter tracks how many samples have been
    /// seen since the last one we actually processed.
    public private(set) var backgroundMode: Bool
    private var decimationCounter: UInt32

    /// At 50 Hz input, keeping every 10th sample gives ~5 Hz.
    private static let backgroundDecimationFactor: UInt32 = 10

    // MARK: - Init

    /// Create a calculator in `.fixed` mode (legacy). Confidence starts
    /// at 100 and lean angles are computed relative to the standard
    /// portrait-on-bars gravity assumption.
    public init(smoothingAlpha: Double = LeanAngleCalculator.defaultSmoothingAlpha) {
        self.calibrationMode = .fixed
        self.currentLeanDegrees = 0
        self.maxLeftLeanDegrees = 0
        self.maxRightLeanDegrees = 0
        self.confidencePercent = 100
        self.samplesSeen = 0
        self.smoothingAlpha = smoothingAlpha
        self.referenceGravity = nil
        self.headingBuffer = []
        self.gravityBuffer = []
        self.lastSpeedKmh = 0
        self.lastCalibrationTime = nil
        self.seekingCalibration = false
        self.backgroundMode = false
        self.decimationCounter = 0
    }

    /// Create a calculator in `.autoCalibrate` mode. Confidence starts at
    /// 0 and lean angles remain at 0 until straight riding is detected and
    /// the upright gravity reference is captured.
    public init(
        autoCalibrate: Bool,
        smoothingAlpha: Double = LeanAngleCalculator.defaultSmoothingAlpha
    ) {
        self.calibrationMode = autoCalibrate ? .autoCalibrate : .fixed
        self.currentLeanDegrees = 0
        self.maxLeftLeanDegrees = 0
        self.maxRightLeanDegrees = 0
        self.confidencePercent = autoCalibrate ? 0 : 100
        self.samplesSeen = 0
        self.smoothingAlpha = smoothingAlpha
        self.referenceGravity = nil
        self.headingBuffer = []
        self.gravityBuffer = []
        self.lastSpeedKmh = 0
        self.lastCalibrationTime = nil
        self.seekingCalibration = autoCalibrate
        self.backgroundMode = false
        self.decimationCounter = 0
    }

    // MARK: - Location updates

    /// Feed a GPS location update into the calibration logic. Call this
    /// alongside ``ingesting(_:)`` when in `.autoCalibrate` mode.
    ///
    /// - Parameters:
    ///   - speed: Ground speed in metres per second.
    ///   - heading: Course over ground in degrees (0 = north).
    ///   - time: Scenario time of the location fix.
    public func updatingLocation(speed: Double, heading: Double, time: Double) -> LeanAngleCalculator {
        guard calibrationMode == .autoCalibrate else { return self }

        var next = self
        next.lastSpeedKmh = speed * 3.6 // m/s -> km/h

        // Only accumulate heading when speed is above threshold and heading
        // is valid (CoreLocation uses -1 for unknown).
        if next.lastSpeedKmh > Self.calibrationMinSpeedKmh && heading >= 0 {
            next.headingBuffer.append((time: time, heading: heading))
            // Trim to window
            let cutoff = time - Self.calibrationWindowSeconds
            next.headingBuffer.removeAll { $0.time < cutoff }
        }

        return next
    }

    // MARK: - Background mode

    /// Toggle background mode. When enabled, only every ~10th motion
    /// sample is processed (effective ~5 Hz at a 50 Hz input rate).
    public func settingBackgroundMode(_ enabled: Bool) -> LeanAngleCalculator {
        var next = self
        next.backgroundMode = enabled
        next.decimationCounter = 0
        return next
    }

    // MARK: - Core ingestion

    /// Fold a sample into the calculator and return the updated value.
    public func ingesting(_ sample: MotionSample) -> LeanAngleCalculator {
        var next = self

        // Background decimation: skip samples when in background mode.
        if next.backgroundMode {
            next.decimationCounter = (next.decimationCounter &+ 1) % Self.backgroundDecimationFactor
            if next.decimationCounter != 1 {
                // Skip this sample but still count it.
                next.samplesSeen = samplesSeen &+ 1
                return next
            }
        }

        // In autoCalibrate mode, accumulate gravity samples and check for
        // calibration triggers.
        if calibrationMode == .autoCalibrate {
            // Store gravity for averaging.
            next.gravityBuffer.append((
                time: sample.scenarioTime,
                x: sample.gravityX,
                y: sample.gravityY,
                z: sample.gravityZ
            ))
            let cutoff = sample.scenarioTime - Self.calibrationWindowSeconds
            next.gravityBuffer.removeAll { $0.time < cutoff }

            // Check if we should seek recalibration.
            if let lastCal = next.lastCalibrationTime,
               !next.seekingCalibration,
               sample.scenarioTime - lastCal >= Self.recalibrationIntervalSeconds {
                next.seekingCalibration = true
            }

            // Attempt calibration if seeking.
            if next.seekingCalibration {
                next = next.attemptCalibration(at: sample.scenarioTime)
            }

            // If not yet calibrated, report zero lean and confidence 0.
            guard next.referenceGravity != nil else {
                next.samplesSeen = samplesSeen &+ 1
                next.confidencePercent = 0
                return next
            }
        }

        // Compute lean angle.
        let rawDegrees: Double
        if let ref = next.referenceGravity {
            rawDegrees = Self.leanAngleRelativeTo(
                reference: ref,
                current: (sample.gravityX, sample.gravityY, sample.gravityZ)
            )
        } else {
            // Fixed mode: original formula (portrait on bars).
            rawDegrees = atan2(-sample.gravityX, -sample.gravityY) * 180.0 / .pi
        }

        // Smoothing: first sample seeds the EMA, subsequent samples
        // blend toward the new reading.
        let smoothed: Double
        if samplesSeen == 0 {
            smoothed = rawDegrees
        } else {
            smoothed = currentLeanDegrees * (1.0 - smoothingAlpha) + rawDegrees * smoothingAlpha
        }

        // Clamp to the wire range (±90°).
        let clamped = min(max(smoothed, -90.0), 90.0)

        // Max tracking.
        var newMaxLeft = maxLeftLeanDegrees
        var newMaxRight = maxRightLeanDegrees
        if clamped > newMaxRight {
            newMaxRight = clamped
        }
        if -clamped > newMaxLeft {
            newMaxLeft = -clamped
        }

        // Confidence: drops linearly with userAccel magnitude.
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

        next.currentLeanDegrees = clamped
        next.maxLeftLeanDegrees = newMaxLeft
        next.maxRightLeanDegrees = newMaxRight
        next.confidencePercent = newConfidence
        next.samplesSeen = samplesSeen &+ 1
        return next
    }

    /// Return a fresh calculator with all rolling state reset to zero,
    /// preserving the original smoothing alpha and calibration mode.
    public func reset() -> LeanAngleCalculator {
        if calibrationMode == .fixed {
            return LeanAngleCalculator(smoothingAlpha: smoothingAlpha)
        } else {
            return LeanAngleCalculator(autoCalibrate: true, smoothingAlpha: smoothingAlpha)
        }
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

    // MARK: - Private helpers

    /// Check whether the heading buffer shows straight riding and, if so,
    /// capture the average gravity vector as the upright reference.
    private func attemptCalibration(at time: Double) -> LeanAngleCalculator {
        // Need enough heading data spanning the window.
        guard !headingBuffer.isEmpty else { return self }
        let windowStart = time - Self.calibrationWindowSeconds
        let inWindow = headingBuffer.filter { $0.time >= windowStart }
        guard inWindow.count >= 3 else { return self } // need a few samples

        // Speed must be above threshold right now.
        guard lastSpeedKmh > Self.calibrationMinSpeedKmh else { return self }

        // Calculate heading standard deviation (circular).
        let stdDev = Self.circularStdDev(of: inWindow.map(\.heading))
        guard stdDev < Self.calibrationMaxHeadingStdDev else { return self }

        // Gravity buffer must also have data.
        let gravityInWindow = gravityBuffer.filter { $0.time >= windowStart }
        guard !gravityInWindow.isEmpty else { return self }

        // Average gravity vector.
        let count = Double(gravityInWindow.count)
        let avgX = gravityInWindow.map(\.x).reduce(0, +) / count
        let avgY = gravityInWindow.map(\.y).reduce(0, +) / count
        let avgZ = gravityInWindow.map(\.z).reduce(0, +) / count

        var next = self
        next.referenceGravity = (x: avgX, y: avgY, z: avgZ)
        next.lastCalibrationTime = time
        next.seekingCalibration = false
        next.confidencePercent = 100
        return next
    }

    /// Calculate the lean angle of `current` gravity relative to a
    /// `reference` gravity vector. The lean is the rotation around the
    /// bike's forward axis (the axis orthogonal to gravity in the plane
    /// of the lean).
    ///
    /// We project both vectors onto the plane perpendicular to Earth's
    /// gravity (i.e. the horizontal plane), then compute the signed angle
    /// between them. In practice we use the cross-product / dot-product
    /// approach in the reference frame defined by the reference gravity.
    static func leanAngleRelativeTo(
        reference ref: (x: Double, y: Double, z: Double),
        current cur: (x: Double, y: Double, z: Double)
    ) -> Double {
        // Normalise the reference vector (should already be ~unit length
        // but be safe).
        let refMag = (ref.x * ref.x + ref.y * ref.y + ref.z * ref.z).squareRoot()
        guard refMag > 0.01 else { return 0 }
        let rn = (x: ref.x / refMag, y: ref.y / refMag, z: ref.z / refMag)

        // Normalise the current vector.
        let curMag = (cur.x * cur.x + cur.y * cur.y + cur.z * cur.z).squareRoot()
        guard curMag > 0.01 else { return 0 }
        let cn = (x: cur.x / curMag, y: cur.y / curMag, z: cur.z / curMag)

        // Dot product gives cosine of the angle between them.
        let dot = rn.x * cn.x + rn.y * cn.y + rn.z * cn.z
        let clampedDot = min(1.0, max(-1.0, dot))
        let angle = acos(clampedDot) * 180.0 / .pi

        // Cross product for sign: we need to determine left vs right lean.
        // The cross product ref x cur gives a vector; the sign of the
        // component along an arbitrary "forward" axis determines lean
        // direction. We use a heuristic: compute cross, then pick the
        // component with the largest magnitude in the reference frame.
        let cx = rn.y * cn.z - rn.z * cn.y
        let cy = rn.z * cn.x - rn.x * cn.z
        let cz = rn.x * cn.y - rn.y * cn.x

        // We want the sign to match the convention: positive = right lean.
        // For a phone lying in a pocket, the "forward" axis depends on
        // orientation. We use the cross product magnitude's sign projected
        // along the axis most aligned with the cross product itself.
        // Simplified: use the sum of all cross components weighted by the
        // reference, which works for arbitrary orientations.
        // Actually, the most robust approach: the sign of the lean is
        // determined by which way the gravity vector has rotated around
        // the forward axis. Since we don't know the forward axis from IMU
        // alone, we use the cross product's largest component as the sign.
        let crossMag = (cx * cx + cy * cy + cz * cz).squareRoot()
        guard crossMag > 1e-10 else { return 0 }

        // Pick the component of the cross product with the largest absolute
        // value and use its sign. This is stable for small lean angles.
        let absCx = abs(cx), absCy = abs(cy), absCz = abs(cz)
        let sign: Double
        if absCx >= absCy && absCx >= absCz {
            sign = cx > 0 ? -1 : 1
        } else if absCy >= absCx && absCy >= absCz {
            sign = cy > 0 ? -1 : 1
        } else {
            sign = cz > 0 ? -1 : 1
        }

        return sign * angle
    }

    /// Circular standard deviation for a list of heading values in degrees.
    /// Handles the 0°/360° wraparound correctly.
    static func circularStdDev(of headings: [Double]) -> Double {
        guard headings.count > 1 else { return 0 }
        let rads = headings.map { $0 * .pi / 180.0 }
        let sinSum = rads.map(sin).reduce(0, +)
        let cosSum = rads.map(cos).reduce(0, +)
        let n = Double(headings.count)
        let r = ((sinSum / n) * (sinSum / n) + (cosSum / n) * (cosSum / n)).squareRoot()
        // Circular variance = 1 - R, std dev = sqrt(-2 * ln(R)) for von Mises.
        // For small dispersion, approximate with: stddev ≈ sqrt(2*(1-R)) * 180/pi
        guard r > 0.001 else { return 180.0 } // nearly uniform → max spread
        let variance = max(0, -2.0 * log(r))
        return variance.squareRoot() * 180.0 / .pi
    }

    // MARK: - Equatable (manual because of tuples)

    public static func == (lhs: LeanAngleCalculator, rhs: LeanAngleCalculator) -> Bool {
        lhs.calibrationMode == rhs.calibrationMode
            && lhs.currentLeanDegrees == rhs.currentLeanDegrees
            && lhs.maxLeftLeanDegrees == rhs.maxLeftLeanDegrees
            && lhs.maxRightLeanDegrees == rhs.maxRightLeanDegrees
            && lhs.confidencePercent == rhs.confidencePercent
            && lhs.samplesSeen == rhs.samplesSeen
            && lhs.smoothingAlpha == rhs.smoothingAlpha
            && lhs.backgroundMode == rhs.backgroundMode
            && lhs.referenceGravity?.x == rhs.referenceGravity?.x
            && lhs.referenceGravity?.y == rhs.referenceGravity?.y
            && lhs.referenceGravity?.z == rhs.referenceGravity?.z
    }
}
