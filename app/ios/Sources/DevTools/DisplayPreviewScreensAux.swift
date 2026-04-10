import BLEProtocol
import SwiftUI

private let gold = Color(hex: 0xEBAB00)
private let blue = Color(hex: 0x5BACF5)
private let green = Color(hex: 0x4CD964)
private let dimGray = Color(hex: 0x666666)
private let lightGray = Color(hex: 0x999999)

// MARK: - Weather

struct WeatherScreenContent: View {
    let screenData: WeatherData

    private var conditionText: String {
        switch screenData.condition {
        case .clear: "klar"
        case .cloudy: "bewoelkt"
        case .rain: "Regen"
        case .snow: "Schnee"
        case .fog: "Nebel"
        case .thunderstorm: "Gewitter"
        @unknown default: ""
        }
    }

    private var conditionIcon: String {
        switch screenData.condition {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .fog: "cloud.fog.fill"
        case .thunderstorm: "cloud.bolt.fill"
        @unknown default: "cloud"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: conditionIcon)
                .font(.system(size: 48))
                .symbolRenderingMode(.multicolor)
            Spacer().frame(height: 4)
            Text("\(screenData.temperatureCelsiusX10 / 10)\u{00B0}")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(conditionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(blue)
            Spacer().frame(height: 8)
            HStack(spacing: 30) {
                Text("H: \(screenData.highCelsiusX10 / 10)\u{00B0}")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(lightGray)
                Text("L: \(screenData.lowCelsiusX10 / 10)\u{00B0}")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(lightGray)
            }
            if !screenData.locationName.isEmpty {
                Text(screenData.locationName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(gold)
            }
            Spacer()
        }
    }
}

// MARK: - Music

struct MusicScreenContent: View {
    let screenData: MusicData

    var body: some View {
        let progress = screenData.durationSeconds > 0
            ? Double(screenData.positionSeconds) / Double(screenData.durationSeconds)
            : 0

        VStack(spacing: 6) {
            Spacer()
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: 0x333333))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: 0x555555))
                )
            Spacer().frame(height: 8)
            Text(screenData.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(screenData.artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(lightGray)
                .lineLimit(1)
            Spacer().frame(height: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0x333333))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(green)
                        .frame(width: geo.size.width * progress, height: 4)
                    Circle()
                        .fill(green)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, geo.size.width * progress - 5))
                }
            }
            .frame(height: 10)
            .padding(.horizontal, 24)
            HStack {
                Text(fmtTime(screenData.positionSeconds))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(dimGray)
                Spacer()
                Text(fmtTime(screenData.durationSeconds))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(dimGray)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func fmtTime(_ seconds: UInt16) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Fuel

struct FuelScreenContent: View {
    let screenData: FuelData

    var body: some View {
        let pct = Int(screenData.tankPercent)
        let range = Int(screenData.estimatedRangeKm)

        VStack(spacing: 4) {
            Text("KRAFTSTOFF")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dimGray)
                .tracking(1.5)
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: 0x555555), lineWidth: 2)
                    .frame(width: 56, height: 72)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x555555))
                    .frame(width: 16, height: 6)
                    .offset(x: 12, y: -36)
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gold)
                        .frame(width: 48, height: max(4, 64 * CGFloat(pct) / 100.0))
                        .overlay(
                            Text("\(pct)%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                        )
                }
                .frame(width: 52, height: 66)
                .clipped()
            }

            Text("\(range)km")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Reichweite")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dimGray)

            HStack {
                VStack(spacing: 0) {
                    Text(String(format: "%.1fL", Double(screenData.consumptionMlPerKm) * 100.0 / 1000.0))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(green)
                    Text("/100km")
                        .font(.system(size: 9))
                        .foregroundStyle(dimGray)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(String(format: "%.1fL", Double(screenData.fuelRemainingMl) / 1000.0))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(blue)
                    Text("im Tank")
                        .font(.system(size: 9))
                        .foregroundStyle(dimGray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Navigation

struct NavScreenContent: View {
    let screenData: NavData

    var body: some View {
        let distM = Int(screenData.distanceToManeuverMeters)
        let distStr = distM >= 1000
            ? String(format: "%.1fkm", Double(distM) / 1000.0)
            : "\(distM)m"
        let remaining = Double(screenData.remainingKmX10) / 10.0
        let eta = screenData.etaMinutes
        let etaH = eta / 60
        let etaM = eta % 60
        let etaStr = etaH > 0
            ? String(format: "ETA %d:%02d", etaH, etaM)
            : String(format: "ETA %d min", etaM)

        VStack(spacing: 6) {
            Spacer()
            Image(systemName: maneuverIcon(screenData.maneuver))
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(green)
            Spacer().frame(height: 8)
            if !screenData.streetName.isEmpty {
                Text(screenData.streetName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(lightGray)
                    .lineLimit(1)
            }
            Text(distStr)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(maneuverText(screenData.maneuver))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(green)
            Spacer().frame(height: 8)
            Text("\(etaStr) — \(String(format: "%.1f km", remaining))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dimGray)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func maneuverIcon(_ type: ManeuverType) -> String {
        switch type {
        case .left, .sharpLeft, .slightLeft: "arrow.turn.up.left"
        case .right, .sharpRight, .slightRight: "arrow.turn.up.right"
        case .uTurnLeft: "arrow.uturn.left"
        case .uTurnRight: "arrow.uturn.right"
        case .arrive: "location.fill"
        case .roundaboutEnter, .roundaboutExit: "arrow.triangle.2.circlepath"
        case .forkLeft: "arrow.branch"
        case .forkRight: "arrow.branch"
        default: "arrow.up"
        }
    }

    private func maneuverText(_ type: ManeuverType) -> String {
        switch type {
        case .left, .sharpLeft, .slightLeft: "Links abbiegen"
        case .right, .sharpRight, .slightRight: "Rechts abbiegen"
        case .uTurnLeft: "Wenden links"
        case .uTurnRight: "Wenden rechts"
        case .arrive: "Ziel erreicht"
        case .roundaboutEnter: "Kreisverkehr"
        case .merge: "Einfaedeln"
        default: "Geradeaus"
        }
    }
}

// MARK: - Appointment

struct AppointmentScreenContent: View {
    let screenData: AppointmentData

    var body: some View {
        VStack(spacing: 8) {
            Text("NAECHSTER TERMIN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dimGray)
                .tracking(1.5)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(screenData.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !screenData.location.isEmpty {
                    Text(screenData.location)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(lightGray)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(hex: 0x1A1A1A))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(blue, lineWidth: 2)
            )
            .padding(.horizontal, 16)

            Text("in \(screenData.startsInMinutes) min")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(gold)

            Spacer()
        }
    }
}

// MARK: - Incoming Call

struct IncomingCallScreenContent: View {
    let screenData: IncomingCallData

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 40))
                .foregroundStyle(green)
            Text("Eingehender Anruf")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(dimGray)
            Text(screenData.callerHandle.isEmpty ? "Unbekannt" : screenData.callerHandle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - Blitzer

struct BlitzerScreenContent: View {
    let screenData: BlitzerData

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(gold)
            Text("BLITZER")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gold)
                .tracking(1.5)
            Text("\(screenData.distanceMeters)m")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if screenData.speedLimitKmh > 0 {
                Text("Limit: \(screenData.speedLimitKmh) km/h")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(lightGray)
            }
            Spacer()
        }
    }
}
