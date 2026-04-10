import Foundation

/// Sunrise and sunset times for a given location and date.
public struct SunTimes: Sendable, Equatable {
    /// Local sunrise time.
    public var sunrise: Date
    /// Local sunset time.
    public var sunset: Date

    public init(sunrise: Date, sunset: Date) {
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Pure-function sunrise/sunset calculator using the NOAA solar position
/// algorithm (simplified). No network calls, no CoreLocation — just
/// trigonometry.
///
/// Accuracy target: +/-5 minutes, which is sufficient for "is it dark
/// outside?" decisions.
///
/// Reference: NOAA Solar Calculator spreadsheet
/// https://gml.noaa.gov/grad/solcalc/calcdetails.html
public enum SunriseSunsetCalculator {

    /// Standard solar zenith angle for sunrise/sunset (degrees).
    private static let zenith: Double = 90.833

    /// Compute sunrise and sunset for the given location and date.
    ///
    /// - Parameters:
    ///   - latitude: WGS-84 latitude in degrees (-90..90).
    ///   - longitude: WGS-84 longitude in degrees (-180..180).
    ///   - date: The calendar date to compute for.
    ///   - timeZoneOffset: Hours east of UTC (e.g. +1 for CET, -5 for EST).
    /// - Returns: A ``SunTimes`` value with sunrise and sunset as `Date`s.
    ///
    /// For locations inside the Arctic/Antarctic circle during polar day or
    /// polar night, the function returns a full-day window (sunrise = start
    /// of day, sunset = end of day) for midnight sun, or a zero-length
    /// window (sunrise = sunset = noon) for polar night.
    public static func calculate(
        latitude: Double,
        longitude: Double,
        date: Date,
        timeZoneOffset: Int
    ) -> SunTimes {
        let cal = Calendar(identifier: .gregorian)
        let dc = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        guard let year = dc.year, let month = dc.month, let day = dc.day else {
            // Fallback: return noon-to-noon (should never happen with valid dates).
            return SunTimes(sunrise: date, sunset: date)
        }

        let julianDay = julianDayNumber(year: year, month: month, day: day)
        let julianCentury = (julianDay - 2_451_545.0) / 36_525.0

        let geomMeanLongSun = fmod(280.46646 + julianCentury * (36_000.76983 + 0.0003032 * julianCentury), 360.0)
        let geomMeanAnomSun = 357.52911 + julianCentury * (35_999.05029 - 0.0001537 * julianCentury)
        let eccentEarthOrbit = 0.016708634 - julianCentury * (0.000042037 + 0.0000001267 * julianCentury)

        let sunEqOfCtr = sin(deg2rad(geomMeanAnomSun)) * (1.914602 - julianCentury * (0.004817 + 0.000014 * julianCentury))
            + sin(deg2rad(2 * geomMeanAnomSun)) * (0.019993 - 0.000101 * julianCentury)
            + sin(deg2rad(3 * geomMeanAnomSun)) * 0.000289

        let sunTrueLong = geomMeanLongSun + sunEqOfCtr
        let sunAppLong = sunTrueLong - 0.00569 - 0.00478 * sin(deg2rad(125.04 - 1934.136 * julianCentury))

        let meanObliqEcliptic = 23.0 + (26.0 + ((21.448 - julianCentury * (46.815 + julianCentury * (0.00059 - julianCentury * 0.001813)))) / 60.0) / 60.0
        let obliqCorr = meanObliqEcliptic + 0.00256 * cos(deg2rad(125.04 - 1934.136 * julianCentury))

        let sunDeclin = rad2deg(asin(sin(deg2rad(obliqCorr)) * sin(deg2rad(sunAppLong))))

        let varY = tan(deg2rad(obliqCorr / 2)) * tan(deg2rad(obliqCorr / 2))
        let eqOfTime = 4 * rad2deg(
            varY * sin(2 * deg2rad(geomMeanLongSun))
            - 2 * eccentEarthOrbit * sin(deg2rad(geomMeanAnomSun))
            + 4 * eccentEarthOrbit * varY * sin(deg2rad(geomMeanAnomSun)) * cos(2 * deg2rad(geomMeanLongSun))
            - 0.5 * varY * varY * sin(4 * deg2rad(geomMeanLongSun))
            - 1.25 * eccentEarthOrbit * eccentEarthOrbit * sin(2 * deg2rad(geomMeanAnomSun))
        )

        // Hour angle at sunrise/sunset.
        let cosHourAngle = (cos(deg2rad(zenith)) / (cos(deg2rad(latitude)) * cos(deg2rad(sunDeclin))))
            - tan(deg2rad(latitude)) * tan(deg2rad(sunDeclin))

        // Midnight of the target date in UTC.
        var startOfDay = DateComponents()
        startOfDay.year = year
        startOfDay.month = month
        startOfDay.day = day
        startOfDay.hour = 0
        startOfDay.minute = 0
        startOfDay.second = 0
        startOfDay.timeZone = TimeZone(identifier: "UTC")
        let midnight = cal.date(from: startOfDay) ?? date

        if cosHourAngle > 1 {
            // Polar night — sun never rises. Return sunrise == sunset == noon UTC.
            let noonMinutesUTC = 720.0 - 4 * longitude - eqOfTime
            let noon = midnight.addingTimeInterval(noonMinutesUTC * 60)
            return SunTimes(sunrise: noon, sunset: noon)
        }

        if cosHourAngle < -1 {
            // Midnight sun — sun never sets. Return full-day window.
            return SunTimes(sunrise: midnight, sunset: midnight.addingTimeInterval(86400))
        }

        let hourAngle = rad2deg(acos(cosHourAngle))

        // Compute times as minutes from UTC midnight. The timeZoneOffset
        // parameter is intentionally unused here — the returned Dates are
        // absolute UTC instants that callers can display in any time zone.
        // The offset is accepted in the API for future use (e.g. determining
        // which calendar date the user means when they say "today").
        let solarNoonMinutesUTC = 720.0 - 4 * longitude - eqOfTime
        let sunriseMinutes = solarNoonMinutesUTC - hourAngle * 4
        let sunsetMinutes = solarNoonMinutesUTC + hourAngle * 4

        let sunrise = midnight.addingTimeInterval(sunriseMinutes * 60)
        let sunset = midnight.addingTimeInterval(sunsetMinutes * 60)

        return SunTimes(sunrise: sunrise, sunset: sunset)
    }

    // MARK: - Helpers

    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day) + Double(b) - 1524.5
    }

    private static func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func rad2deg(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
