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
    case compass
    case weather
    case tripStats
    case leanAngle
    case appointment
    case incomingCall
    case navigation
    case fuelEstimate
    case altitude
    case music
    case blitzer
    /// Rotate through every supported screen over the course of the ride,
    /// spending ``holdSeconds`` seconds on each before advancing.
    case rotating(holdSeconds: Int)

    /// All single-screen cases, in display rotation order.
    static let allSingle: [FrameScreen] = [
        .clock, .speedHeading, .compass, .navigation, .weather,
        .tripStats, .leanAngle, .altitude, .fuelEstimate,
        .appointment, .music, .blitzer, .incomingCall,
    ]
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
        let payload = buildPayload(screen: selectedScreen, at: t)
        return Frame(timeSeconds: t, payload: payload)
    }

    func buildPayload(screen: FrameScreen, at t: Double) -> ScreenPayload {
        switch screen {
        case .speedHeading:
            return .speedHeading(speedHeadingData(at: t), flags: [])
        case .clock:
            return .clock(clockData(at: t), flags: [])
        case .compass:
            return .compass(compassData(at: t), flags: [])
        case .navigation:
            return .navigation(navData(at: t), flags: [])
        case .weather:
            return .weather(weatherData(at: t), flags: [])
        case .tripStats:
            return .tripStats(tripStatsData(at: t), flags: [])
        case .leanAngle:
            return .leanAngle(leanAngleData(at: t), flags: [])
        case .appointment:
            return .appointment(appointmentData(at: t), flags: [])
        case .incomingCall:
            return .incomingCall(incomingCallData(at: t), flags: [])
        case .fuelEstimate:
            return .fuelEstimate(fuelData(at: t), flags: [])
        case .altitude:
            return .altitude(altitudeData(at: t), flags: [])
        case .music:
            return .music(musicData(at: t), flags: [])
        case .blitzer:
            return .blitzer(blitzerData(at: t), flags: [])
        case .rotating:
            // Can't happen — `resolvedScreen` flattens `.rotating`.
            return .clock(clockData(at: t), flags: [])
        }
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
        case .rotating(let hold):
            let screens = FrameScreen.allSingle
            let bucket = (index / max(hold, 1)) % screens.count
            return screens[bucket]
        default:
            return screen
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

    func navData(at t: Double) -> NavData {
        let loc = Self.sampleAtOrBefore(
            scenario.locationSamples, time: t, timeOf: { $0.scenarioTime }
        )
        let latE7 = Int32((loc?.latitude ?? 46.6) * 1e7)
        let lonE7 = Int32((loc?.longitude ?? 8.3) * 1e7)

        let speedMps = max(loc?.speedMps ?? 0, 0)
        let speedKmhX10 = UInt16(min(max(speedMps * 3.6 * 10, 0), 3000))

        let course = loc?.courseDegrees ?? 0
        let headingX10 = UInt16(min(max(
            ((course.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)) * 10, 0), 3599))

        // Simulate turn-by-turn maneuvers based on heading changes
        let maneuverCycle = Int(t / 20) % 8
        let maneuvers: [(ManeuverType, String, UInt16)] = [
            (.straight,   "Gotthardstrasse",    800),
            (.slightRight,"Tremola Vecchia",     350),
            (.sharpLeft,  "Kehre 7",            120),
            (.right,      "Gotthardpasshöhe",   500),
            (.slightLeft, "Passo San Gottardo",  250),
            (.sharpRight, "Tornante 4",         180),
            (.left,       "Via Tremola",        400),
            (.arrive,     "Airolo, TI",          50),
        ]
        let (maneuver, street, dist) = maneuvers[maneuverCycle]

        let fraction = t / max(scenario.durationSeconds, 1)
        let remainingKm = UInt16(max((1.0 - fraction) * 350, 0)) // 35.0 km total
        let etaMin = UInt16(max((1.0 - fraction) * 45, 0))       // 45 min total

        return NavData(
            latitudeE7: latE7,
            longitudeE7: lonE7,
            speedKmhX10: speedKmhX10,
            headingDegX10: headingX10,
            distanceToManeuverMeters: dist,
            maneuver: maneuver,
            streetName: street,
            etaMinutes: etaMin,
            remainingKmX10: remainingKm
        )
    }

    func compassData(at t: Double) -> CompassData {
        let hs = Self.sampleAtOrBefore(
            scenario.headingSamples, time: t, timeOf: { $0.scenarioTime }
        )
        let mag = hs?.magneticDegrees ?? 0
        let true_ = hs?.trueDegrees ?? -1
        let magNorm = ((mag.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let trueNorm = true_ < 0 ? mag : ((true_.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        return CompassData(
            magneticHeadingDegX10: UInt16(min(max((magNorm * 10).rounded(), 0), 3599)),
            trueHeadingDegX10: UInt16(min(max((trueNorm * 10).rounded(), 0), 3599)),
            headingAccuracyDegX10: 50,
            flags: true_ >= 0 ? 0x01 : 0x00
        )
    }

    func weatherData(at t: Double) -> WeatherData {
        let ws = Self.sampleAtOrBefore(
            scenario.weatherSnapshots, time: t, timeOf: { $0.scenarioTime }
        )
        let wireCondition: WeatherConditionWire
        switch ws?.condition ?? .clear {
        case .clear:        wireCondition = .clear
        case .cloudy:       wireCondition = .cloudy
        case .rain:         wireCondition = .rain
        case .snow:         wireCondition = .snow
        case .fog:          wireCondition = .fog
        case .thunderstorm: wireCondition = .thunderstorm
        }
        return WeatherData(
            condition: wireCondition,
            temperatureCelsiusX10: Int16((ws?.temperatureCelsius ?? 18) * 10),
            highCelsiusX10: Int16((ws?.highCelsius ?? 22) * 10),
            lowCelsiusX10: Int16((ws?.lowCelsius ?? 12) * 10),
            locationName: ws?.locationName ?? "Unknown"
        )
    }

    func tripStatsData(at t: Double) -> TripStatsData {
        let rideTime = UInt32(max(t, 0))
        // Accumulate distance from location samples
        var totalDistance: Double = 0
        var maxSpeed: Double = 0
        var totalAscent: Double = 0
        var totalDescent: Double = 0
        var prevLoc: (lat: Double, lon: Double, alt: Double)?
        for sample in scenario.locationSamples where sample.scenarioTime <= t {
            let speed = max(sample.speedMps, 0) * 3.6
            maxSpeed = max(maxSpeed, speed)
            if let prev = prevLoc {
                let dt = 10.0 // samples are ~10s apart
                totalDistance += max(sample.speedMps, 0) * dt
                let dAlt = sample.altitudeMeters - prev.alt
                if dAlt > 0 { totalAscent += dAlt } else { totalDescent += -dAlt }
            }
            prevLoc = (sample.latitude, sample.longitude, sample.altitudeMeters)
        }
        let avgSpeed = t > 0 ? (totalDistance / t) * 3.6 : 0
        return TripStatsData(
            rideTimeSeconds: rideTime,
            distanceMeters: UInt32(min(totalDistance, Double(UInt32.max))),
            averageSpeedKmhX10: UInt16(min(max(avgSpeed * 10, 0), 3000)),
            maxSpeedKmhX10: UInt16(min(max(maxSpeed * 10, 0), 3000)),
            ascentMeters: UInt16(min(totalAscent, Double(UInt16.max))),
            descentMeters: UInt16(min(totalDescent, Double(UInt16.max)))
        )
    }

    func leanAngleData(at t: Double) -> LeanAngleData {
        let ms = Self.sampleAtOrBefore(
            scenario.motionSamples, time: t, timeOf: { $0.scenarioTime }
        )
        // Derive lean angle from gravity vector: atan2(gx, gz) in degrees
        let gx = ms?.gravityX ?? 0
        let gz = ms?.gravityZ ?? -1
        let leanRad = atan2(gx, -gz)
        let leanDeg = leanRad * 180.0 / .pi
        let currentX10 = Int16(min(max(leanDeg * 10, -900), 900))

        // Track max lean from all motion samples up to t
        var maxLeft: Double = 0
        var maxRight: Double = 0
        for sample in scenario.motionSamples where sample.scenarioTime <= t {
            let lean = atan2(sample.gravityX, -sample.gravityZ) * 180.0 / .pi
            if lean < 0 { maxLeft = max(maxLeft, -lean) }
            if lean > 0 { maxRight = max(maxRight, lean) }
        }
        return LeanAngleData(
            currentLeanDegX10: currentX10,
            maxLeftLeanDegX10: UInt16(min(maxLeft * 10, 900)),
            maxRightLeanDegX10: UInt16(min(maxRight * 10, 900)),
            confidencePercent: ms != nil ? 95 : 0
        )
    }

    func appointmentData(at t: Double) -> AppointmentData {
        let event = Self.sampleAtOrBefore(
            scenario.calendarEvents, time: t, timeOf: { $0.scenarioTime }
        )
        let remaining = (event?.startsInSeconds ?? 1800) - t
        let minutesLeft = Int16(max(min(remaining / 60, Double(Int16.max)), -999))
        return AppointmentData(
            startsInMinutes: minutesLeft,
            title: event?.title ?? "No upcoming event",
            location: event?.location ?? ""
        )
    }

    func incomingCallData(at t: Double) -> IncomingCallData {
        let event = Self.sampleAtOrBefore(
            scenario.callEvents, time: t, timeOf: { $0.scenarioTime }
        )
        let wireState: IncomingCallData.CallStateWire
        switch event?.state ?? .ended {
        case .incoming:  wireState = .incoming
        case .connected: wireState = .connected
        case .ended:     wireState = .ended
        }
        return IncomingCallData(
            callState: wireState,
            callerHandle: event?.callerHandle ?? ""
        )
    }

    func fuelData(at t: Double) -> FuelData {
        // Simulate fuel consumption: start at 80% full, 5L tank, burning over the ride
        let fraction = t / max(scenario.durationSeconds, 1)
        let tankPercent = UInt8(max(80 - fraction * 30, 10))
        let remainingMl = UInt16(Double(tankPercent) / 100.0 * 5000)
        let rangeKm = UInt16(Double(remainingMl) / 50) // ~50ml/km
        return FuelData(
            tankPercent: tankPercent,
            estimatedRangeKm: rangeKm,
            consumptionMlPerKm: 50,
            fuelRemainingMl: remainingMl
        )
    }

    func musicData(at t: Double) -> MusicData {
        let snap = Self.sampleAtOrBefore(
            scenario.nowPlayingSnapshots, time: t, timeOf: { $0.scenarioTime }
        )
        let elapsed = snap.map { t - $0.scenarioTime + $0.positionSeconds } ?? 0
        let playing: UInt8 = (snap?.isPlaying ?? false) ? MusicData.playingFlag : 0
        return MusicData(
            musicFlags: playing,
            positionSeconds: UInt16(min(max(elapsed, 0), Double(UInt16.max))),
            durationSeconds: UInt16(snap?.durationSeconds ?? 0),
            title: snap?.title ?? "No music",
            artist: snap?.artist ?? "",
            album: snap?.album ?? ""
        )
    }

    func blitzerData(at t: Double) -> BlitzerData {
        // Simulate a speed camera appearing periodically
        let cycleT = t.truncatingRemainder(dividingBy: 60)
        let distance: UInt16
        if cycleT < 30 {
            distance = UInt16(max(1000 - cycleT * 33, 10)) // approaching
        } else {
            distance = UInt16(min((cycleT - 30) * 50, 1500)) // receding
        }
        let sh = speedHeadingData(at: t)
        return BlitzerData(
            distanceMeters: distance,
            speedLimitKmh: 80,
            currentSpeedKmhX10: sh.speedKmhX10,
            cameraType: .fixed
        )
    }

    func altitudeData(at t: Double) -> AltitudeProfileData {
        let loc = Self.sampleAtOrBefore(
            scenario.locationSamples, time: t, timeOf: { $0.scenarioTime }
        )
        let currentAlt = Int16(min(max(loc?.altitudeMeters ?? 0, -500), 9000))

        // Build altitude profile from all samples up to now
        var ascent: Double = 0
        var descent: Double = 0
        var altitudes: [Int16] = []
        var prevAlt: Double?
        for sample in scenario.locationSamples where sample.scenarioTime <= t {
            let alt = sample.altitudeMeters
            altitudes.append(Int16(min(max(alt, -500), 9000)))
            if let prev = prevAlt {
                let d = alt - prev
                if d > 0 { ascent += d } else { descent += -d }
            }
            prevAlt = alt
        }

        // Resample to exactly 60 profile slots
        var profile = [Int16](repeating: currentAlt, count: 60)
        if !altitudes.isEmpty {
            for i in 0..<60 {
                let srcIdx = i * altitudes.count / 60
                profile[i] = altitudes[min(srcIdx, altitudes.count - 1)]
            }
        }

        return AltitudeProfileData(
            currentAltitudeM: currentAlt,
            totalAscentM: UInt16(min(ascent, Double(UInt16.max))),
            totalDescentM: UInt16(min(descent, Double(UInt16.max))),
            sampleCount: UInt8(min(altitudes.count, 60)),
            profile: profile
        )
    }
}
