import Foundation

/// The output of the brightness policy decision.
public struct BrightnessDecision: Sendable, Equatable {
    /// Display brightness as a percentage (0-100).
    public var brightnessPercent: UInt8
    /// Whether night mode (red palette) should be active.
    public var nightMode: Bool

    public init(brightnessPercent: UInt8, nightMode: Bool) {
        self.brightnessPercent = brightnessPercent
        self.nightMode = nightMode
    }
}

/// User override for automatic brightness/night-mode decisions.
public enum BrightnessOverride: Sendable, Equatable {
    /// User forced a specific brightness percentage.
    case manual(percent: UInt8)
    /// User forced night mode on regardless of time/lux.
    case autoWithNightMode
    /// User forced day mode on regardless of time/lux.
    case autoWithDayMode
}

/// Pure-function brightness and night-mode policy.
///
/// Decision hierarchy:
/// 1. User override (manual brightness, forced night/day mode).
/// 2. Ambient lux sensor data (if available).
/// 3. Time-based fallback using sunrise/sunset times.
public enum BrightnessPolicy {

    /// Lux threshold below which night mode activates.
    private static let nightLuxThreshold: Double = 50
    /// Lux threshold above which day mode is certain.
    private static let dayLuxThreshold: Double = 200
    /// Twilight window in seconds (30 minutes).
    private static let twilightWindowSeconds: TimeInterval = 30 * 60

    /// Evaluate the brightness policy given the current inputs.
    ///
    /// - Parameters:
    ///   - currentTime: The current date/time.
    ///   - sunTimes: Computed sunrise and sunset for the current location.
    ///   - ambientLux: Current ambient light reading in lux, or `nil` if
    ///     no sensor is available.
    ///   - userOverride: An explicit user override, or `nil` for automatic.
    /// - Returns: A ``BrightnessDecision`` with the recommended brightness
    ///   percentage and night-mode flag.
    public static func decide(
        currentTime: Date,
        sunTimes: SunTimes,
        ambientLux: Double?,
        userOverride: BrightnessOverride?
    ) -> BrightnessDecision {
        // 1. User overrides.
        if let override = userOverride {
            switch override {
            case .manual(let percent):
                let clamped = min(percent, 100)
                let nightMode = nightModeFromContext(
                    currentTime: currentTime,
                    sunTimes: sunTimes,
                    ambientLux: ambientLux
                )
                return BrightnessDecision(brightnessPercent: clamped, nightMode: nightMode)
            case .autoWithNightMode:
                return BrightnessDecision(brightnessPercent: 20, nightMode: true)
            case .autoWithDayMode:
                return BrightnessDecision(brightnessPercent: 100, nightMode: false)
            }
        }

        // 2. Lux-based decision.
        if let lux = ambientLux {
            if lux >= dayLuxThreshold {
                return BrightnessDecision(brightnessPercent: 100, nightMode: false)
            }
            if lux < nightLuxThreshold {
                // Scale brightness linearly: 0 lux -> 10%, 50 lux -> 50%.
                let fraction = lux / nightLuxThreshold
                let brightness = UInt8(10.0 + fraction * 40.0)
                return BrightnessDecision(brightnessPercent: brightness, nightMode: true)
            }
            // Between 50 and 200 lux: transition zone — day mode, scaled brightness.
            let fraction = (lux - nightLuxThreshold) / (dayLuxThreshold - nightLuxThreshold)
            let brightness = UInt8(50.0 + fraction * 50.0)
            return BrightnessDecision(brightnessPercent: brightness, nightMode: false)
        }

        // 3. Time-based fallback (no sensor).
        return timeBased(currentTime: currentTime, sunTimes: sunTimes)
    }

    // MARK: - Internal helpers

    /// Determine night mode from lux or time, used when the user has set
    /// a manual brightness but not explicitly forced day/night mode.
    private static func nightModeFromContext(
        currentTime: Date,
        sunTimes: SunTimes,
        ambientLux: Double?
    ) -> Bool {
        if let lux = ambientLux {
            return lux < nightLuxThreshold
        }
        let timeDecision = timeBased(currentTime: currentTime, sunTimes: sunTimes)
        return timeDecision.nightMode
    }

    /// Pure time-based brightness decision.
    ///
    /// - Before sunrise or after sunset: night mode, 30%.
    /// - Within 30 min of sunrise/sunset (twilight): night mode, 50%.
    /// - Daytime: day mode, 100%.
    private static func timeBased(
        currentTime: Date,
        sunTimes: SunTimes
    ) -> BrightnessDecision {
        let sunrise = sunTimes.sunrise
        let sunset = sunTimes.sunset

        // Handle degenerate cases (polar night / midnight sun).
        if sunrise == sunset {
            // Polar night — always night mode.
            return BrightnessDecision(brightnessPercent: 30, nightMode: true)
        }
        if sunset.timeIntervalSince(sunrise) >= 86399 {
            // Midnight sun — always day mode.
            return BrightnessDecision(brightnessPercent: 100, nightMode: false)
        }

        let now = currentTime.timeIntervalSince1970

        let sunriseStart = sunrise.timeIntervalSince1970 - twilightWindowSeconds
        let sunriseEnd = sunrise.timeIntervalSince1970
        let sunsetStart = sunset.timeIntervalSince1970
        let sunsetEnd = sunset.timeIntervalSince1970 + twilightWindowSeconds

        if now < sunriseStart {
            // Before dawn twilight.
            return BrightnessDecision(brightnessPercent: 30, nightMode: true)
        }
        if now < sunriseEnd {
            // Dawn twilight — sunrise is approaching.
            return BrightnessDecision(brightnessPercent: 50, nightMode: true)
        }
        if now < sunsetStart {
            // Full daylight.
            return BrightnessDecision(brightnessPercent: 100, nightMode: false)
        }
        if now < sunsetEnd {
            // Dusk twilight — sunset just passed.
            return BrightnessDecision(brightnessPercent: 50, nightMode: true)
        }
        // After dusk twilight.
        return BrightnessDecision(brightnessPercent: 30, nightMode: true)
    }
}
