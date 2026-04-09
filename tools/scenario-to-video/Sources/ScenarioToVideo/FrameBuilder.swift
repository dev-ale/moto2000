import Foundation
import BLEProtocol
import RideSimulatorKit

/// Which screen to render for a given frame.
///
/// ``FrameBuilder`` currently supports the three screens whose wire format
/// lives in ``BLEProtocol``: clock, speedHeading, and navigation. Navigation
/// is not derived from scenarios yet (no nav events in the format), so only
/// ``clock`` and ``speedHeading`` are built from scenario data. Other values
/// of ``ScreenID`` are rejected at CLI-parse time.
public enum FrameScreen: Sendable, Equatable {
    case speedHeading
    case clock
    /// Rotate through every supported screen over the course of the ride,
    /// spending ``holdSeconds`` seconds on each before advancing.
    case rotating(holdSeconds: Int)
}

/// A derived frame: the wall-clock timestamp (in seconds of scenario time)
/// plus the ``ScreenPayload`` that should be rendered at that instant.
public struct Frame: Equatable, Sendable {
    public var timeSeconds: Double
    public var payload: ScreenPayload

    public init(timeSeconds: Double, payload: ScreenPayload) {
        self.timeSeconds = timeSeconds
        self.payload = payload
    }
}

/// Pure, deterministic conversion from a ``Scenario`` into a sequence of
/// ``ScreenPayload``s — one per simulated frame.
///
/// This type contains NO I/O: no host simulator, no ffmpeg, no filesystem.
/// That is deliberate — it is the easiest piece to unit-test, and the rest
/// of the pipeline just consumes its output.
public struct FrameBuilder: Sendable {
    /// Fixed epoch used for the synthesised clock screen so videos are
    /// byte-for-byte reproducible regardless of when they are rendered.
    /// Value matches the clock fixture epoch used elsewhere in the repo.
    public static let clockEpochSeconds: Int64 = 1_738_339_200

    /// Fixed timezone offset for the synthesised clock screen (UTC).
    public static let clockTzOffsetMinutes: Int16 = 0

    public let scenario: Scenario
    public let screen: FrameScreen
    public let stepSeconds: Double

    public init(
        scenario: Scenario,
        screen: FrameScreen,
        stepSeconds: Double = 1.0
    ) {
        self.scenario = scenario
        self.screen = screen
        self.stepSeconds = stepSeconds
    }

    /// Number of frames this builder will produce. Always at least 1 so the
    /// resulting video is never empty even for a zero-length scenario.
    public var frameCount: Int {
        let duration = max(scenario.durationSeconds, 0)
        let count = Int((duration / stepSeconds).rounded(.down)) + 1
        return max(count, 1)
    }

    /// Build frame at index `index` (0-based). `index` must be
    /// `< frameCount`.
    public func frame(at index: Int) throws -> Frame {
        precondition(index >= 0 && index < frameCount, "index out of range")
        let t = Double(index) * stepSeconds
        let selectedScreen = resolvedScreen(at: index)
        let payload: ScreenPayload
        switch selectedScreen {
        case .speedHeading:
            payload = .speedHeading(speedHeadingData(at: t), flags: [])
        case .clock:
            payload = .clock(clockData(at: t), flags: [])
        case .rotating:
            // Can't happen — `resolvedScreen` flattens `.rotating`.
            payload = .clock(clockData(at: t), flags: [])
        }
        return Frame(timeSeconds: t, payload: payload)
    }

    /// Build every frame for the scenario. Convenient for tests.
    public func allFrames() throws -> [Frame] {
        var out: [Frame] = []
        out.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            out.append(try frame(at: i))
        }
        return out
    }

    // MARK: - Screen selection

    private func resolvedScreen(at index: Int) -> FrameScreen {
        switch screen {
        case .speedHeading, .clock:
            return screen
        case .rotating(let hold):
            let bucket = (index / max(hold, 1)) % 2
            return bucket == 0 ? .clock : .speedHeading
        }
    }

    // MARK: - Derivation helpers

    /// Sample at-or-before `t` from an array sorted by `scenarioTime`. Linear
    /// scan — scenarios are short so this is fine.
    static func sampleAtOrBefore<S>(
        _ samples: [S],
        time t: Double,
        timeOf: (S) -> Double
    ) -> S? {
        var latest: S?
        for s in samples {
            if timeOf(s) <= t {
                latest = s
            } else {
                break
            }
        }
        return latest
    }

    func speedHeadingData(at t: Double) -> SpeedHeadingData {
        let loc = Self.sampleAtOrBefore(
            scenario.locationSamples, time: t, timeOf: { $0.scenarioTime }
        )

        // Speed: clamp, -1 (unknown) becomes 0.
        let speedMps = max(loc?.speedMps ?? 0, 0)
        let rawSpeed = (speedMps * 3.6 * 10).rounded()
        let speedClamped = min(max(rawSpeed, 0), 3000)
        let speedKmhX10 = UInt16(speedClamped)

        // Heading: prefer the heading sample track; fall back to location course.
        let headingDeg: Double
        if let hs = Self.sampleAtOrBefore(
            scenario.headingSamples, time: t, timeOf: { $0.scenarioTime }
        ) {
            headingDeg = hs.magneticDegrees
        } else if let loc, loc.courseDegrees >= 0 {
            headingDeg = loc.courseDegrees
        } else {
            headingDeg = 0
        }
        let normalisedHeading = ((headingDeg.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let headingDegX10 = UInt16(min(max((normalisedHeading * 10).rounded(), 0), 3599))

        // Altitude: clamp to Int16 protocol range.
        let altRaw = (loc?.altitudeMeters ?? 0).rounded()
        let altClamped = min(max(altRaw, -500), 9000)
        let altitudeMeters = Int16(altClamped)

        // Temperature: placeholder — scenarios carry weather snapshots but
        // plumbing that through is future work. Document in the README.
        let temperatureCelsiusX10: Int16 = 0

        return SpeedHeadingData(
            speedKmhX10: speedKmhX10,
            headingDegX10: headingDegX10,
            altitudeMeters: altitudeMeters,
            temperatureCelsiusX10: temperatureCelsiusX10
        )
    }

    func clockData(at t: Double) -> ClockData {
        let now = Self.clockEpochSeconds + Int64(t.rounded(.down))
        return ClockData(
            unixTime: now,
            tzOffsetMinutes: Self.clockTzOffsetMinutes,
            is24Hour: true
        )
    }
}
