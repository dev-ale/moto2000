import BLEProtocol
import SwiftUI

// MARK: - Individual screen renderers for the live display preview

/// Shared gold accent color for the AMOLED display preview.
private let previewGold = Color(hex: 0xEBAB00)

struct SpeedScreenContent: View {
    let screenData: SpeedHeadingData

    var body: some View {
        let speedKmh = Double(screenData.speedKmhX10) / 10.0
        let headingDeg = Double(screenData.headingDegX10) / 10.0

        VStack(spacing: 4) {
            Text(String(format: "%.0f", speedKmh))
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundStyle(previewGold)
                .minimumScaleFactor(0.5)

            Text("km/h")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x666666))

            HStack(spacing: 16) {
                Label(
                    String(format: "%.0f\u{00B0}", headingDeg),
                    systemImage: "location.north.fill"
                )
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)

                Label(
                    "\(screenData.altitudeMeters) m",
                    systemImage: "mountain.2.fill"
                )
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            }
            .padding(.top, 8)
        }
    }
}

struct CompassScreenContent: View {
    let screenData: CompassData

    var body: some View {
        let heading = screenData.useTrueHeading
            && screenData.trueHeadingDegX10 != CompassData.trueHeadingUnknown
            ? Double(screenData.trueHeadingDegX10) / 10.0
            : Double(screenData.magneticHeadingDegX10) / 10.0

        VStack(spacing: 8) {
            Text(compassDirection(from: heading))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(previewGold)

            Text(String(format: "%.0f\u{00B0}", heading))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text(screenData.useTrueHeading ? "TRUE" : "MAG")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: 0x666666))
        }
    }

    private func compassDirection(from degrees: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45.0)
        return dirs[max(0, min(index, dirs.count - 1))]
    }
}

struct TripStatsScreenContent: View {
    let screenData: TripStatsData

    var body: some View {
        let hours = screenData.rideTimeSeconds / 3600
        let minutes = (screenData.rideTimeSeconds % 3600) / 60
        let seconds = screenData.rideTimeSeconds % 60
        let distKm = Double(screenData.distanceMeters) / 1000.0

        VStack(spacing: 6) {
            metricRow("TIME", String(format: "%d:%02d:%02d", hours, minutes, seconds))
            metricRow("DIST", String(format: "%.1f km", distKm))
            metricRow(
                "AVG",
                String(format: "%.1f km/h", Double(screenData.averageSpeedKmhX10) / 10.0)
            )
            metricRow(
                "MAX",
                String(format: "%.1f km/h", Double(screenData.maxSpeedKmhX10) / 10.0)
            )

            HStack(spacing: 12) {
                Label("\(screenData.ascentMeters)m", systemImage: "arrow.up")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x5BACF5))
                Label("\(screenData.descentMeters)m", systemImage: "arrow.down")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE24B4A))
            }
            .padding(.top, 2)
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: 0x666666))
                .frame(width: 36, alignment: .trailing)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct LeanAngleScreenContent: View {
    let screenData: LeanAngleData

    var body: some View {
        let current = Double(screenData.currentLeanDegX10) / 10.0
        let direction: String = {
            if current < 0 { return "LEFT" }
            if current > 0 { return "RIGHT" }
            return "--"
        }()

        VStack(spacing: 8) {
            Text(String(format: "%.1f\u{00B0}", abs(current)))
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(previewGold)

            Text(direction)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 20) {
                leanMaxColumn(
                    label: "L MAX",
                    value: Double(screenData.maxLeftLeanDegX10) / 10.0
                )
                leanMaxColumn(
                    label: "R MAX",
                    value: Double(screenData.maxRightLeanDegX10) / 10.0
                )
            }
            .padding(.top, 4)
        }
    }

    private func leanMaxColumn(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(hex: 0x666666))
            Text(String(format: "%.1f\u{00B0}", value))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct ClockScreenContent: View {
    let screenData: ClockData

    var body: some View {
        let date = Date(timeIntervalSince1970: TimeInterval(screenData.unixTime))
        let tz = TimeZone(secondsFromGMT: Int(screenData.tzOffsetMinutes) * 60) ?? .current
        let timeString = formatTime(date: date, timeZone: tz, is24Hour: screenData.is24Hour)
        let dateString = formatDate(date: date, timeZone: tz)

        VStack(spacing: 8) {
            Text(timeString)
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .foregroundStyle(previewGold)

            Text(dateString)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private func formatTime(date: Date, timeZone: TimeZone, is24Hour _: Bool) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDate(date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "EEE, d. MMM"
        return formatter.string(from: date)
    }
}

struct AltitudeScreenContent: View {
    let screenData: AltitudeProfileData

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(screenData.currentAltitudeM)")
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(previewGold)
                Text("m")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(hex: 0x999999))
            }

            HStack(spacing: 16) {
                Label("\(screenData.totalAscentM)m", systemImage: "arrow.up")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x5BACF5))
                Label("\(screenData.totalDescentM)m", systemImage: "arrow.down")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE24B4A))
            }
            .padding(.top, 4)
        }
    }
}

struct WeatherScreenContent: View {
    let screenData: WeatherData

    private static let weatherIcons: [WeatherConditionWire: String] = [
        .clear: "sun.max.fill",
        .cloudy: "cloud.fill",
        .rain: "cloud.rain.fill",
        .snow: "cloud.snow.fill",
        .fog: "cloud.fog.fill",
        .thunderstorm: "cloud.bolt.fill"
    ]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: Self.weatherIcons[screenData.condition] ?? "questionmark")
                .font(.system(size: 36))
                .foregroundStyle(previewGold)

            Text(String(
                format: "%.1f\u{00B0}C",
                Double(screenData.temperatureCelsiusX10) / 10.0
            ))
            .font(.system(size: 40, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)

            HStack(spacing: 12) {
                Text(String(format: "H:%.0f\u{00B0}", Double(screenData.highCelsiusX10) / 10.0))
                    .foregroundStyle(Color(hex: 0xE24B4A))
                Text(String(format: "L:%.0f\u{00B0}", Double(screenData.lowCelsiusX10) / 10.0))
                    .foregroundStyle(Color(hex: 0x5BACF5))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))

            if !screenData.locationName.isEmpty {
                Text(screenData.locationName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: 0x666666))
            }
        }
    }
}

struct MusicScreenContent: View {
    let screenData: MusicData

    var body: some View {
        VStack(spacing: 8) {
            Image(
                systemName: screenData.isPlaying
                    ? "play.circle.fill"
                    : "pause.circle.fill"
            )
            .font(.system(size: 28))
            .foregroundStyle(previewGold)

            Text(screenData.title.isEmpty ? "--" : screenData.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(screenData.artist.isEmpty ? "--" : screenData.artist)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x999999))
                .lineLimit(1)

            if screenData.durationSeconds != MusicData.unknownU16
                && screenData.durationSeconds > 0 {
                progressBar
            }
        }
        .padding(.horizontal, 16)
    }

    private var progressBar: some View {
        let progress = screenData.positionSeconds == MusicData.unknownU16
            ? 0.0
            : Double(screenData.positionSeconds) / Double(screenData.durationSeconds)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: 0x333333))
                    .frame(height: 3)

                Capsule()
                    .fill(previewGold)
                    .frame(width: geo.size.width * min(progress, 1.0), height: 3)
            }
        }
        .frame(width: 140, height: 3)
        .padding(.top, 4)
    }
}
