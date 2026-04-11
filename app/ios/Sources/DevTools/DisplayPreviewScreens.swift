// swiftlint:disable file_length
import BLEProtocol
import SwiftUI

private let gold = Color(hex: 0xEBAB00)
private let blue = Color(hex: 0x5BACF5)
private let green = Color(hex: 0x4CD964)
private let red = Color(hex: 0xE24B4A)
private let dimGray = Color(hex: 0x666666)
private let lightGray = Color(hex: 0x999999)

// MARK: - Speed + Heading

struct SpeedScreenContent: View {
    let screenData: SpeedHeadingData

    var body: some View {
        let speed = Int(screenData.speedKmhX10 / 10)
        let headingDeg = Double(screenData.headingDegX10) / 10.0
        let dir = compassDirection(headingDeg)
        let alt = Int(screenData.altitudeMeters)

        VStack(spacing: 2) {
            Spacer()

            Text("\(speed)")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("km/h")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dimGray)

            Spacer().frame(height: 6)

            Text("\(dir) \(String(format: "%03.0f", headingDeg))\u{00B0}")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(blue)

            Spacer().frame(height: 6)

            HStack {
                Text("\(alt)m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(dimGray)
                Spacer()
                Text("\(screenData.temperatureCelsiusX10 / 10)\u{00B0}C")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(dimGray)
            }
            .padding(.horizontal, 50)

            Spacer().frame(height: 24)
        }
    }

    private func compassDirection(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(round(deg / 45.0)) % 8
        return dirs[max(0, min(index, dirs.count - 1))]
    }
}

// MARK: - Compass

struct CompassScreenContent: View {
    let screenData: CompassData

    var body: some View {
        let heading = Double(screenData.magneticHeadingDegX10) / 10.0

        ZStack {
            // Compass circle
            Circle()
                .stroke(Color(hex: 0x333333), lineWidth: 1)
                .frame(width: 190, height: 190)

            // Tick marks
            ForEach(0..<36, id: \.self) { tick in
                let isMajor = tick % 9 == 0
                Rectangle()
                    .fill(isMajor ? Color.white.opacity(0.6) : Color(hex: 0x444444))
                    .frame(width: isMajor ? 2 : 1, height: isMajor ? 10 : 5)
                    .offset(y: -90)
                    .rotationEffect(.degrees(Double(tick) * 10))
            }

            // N S E W labels
            compassLabel("N", angle: 0, color: red)
            compassLabel("E", angle: 90, color: lightGray)
            compassLabel("S", angle: 180, color: lightGray)
            compassLabel("W", angle: 270, color: lightGray)

            // Needle
            VStack(spacing: 0) {
                Triangle()
                    .fill(red)
                    .frame(width: 12, height: 50)
                Circle()
                    .fill(Color(hex: 0x222222))
                    .frame(width: 8, height: 8)
                Triangle()
                    .fill(Color(hex: 0x555555))
                    .frame(width: 12, height: 50)
                    .rotationEffect(.degrees(180))
            }
            .rotationEffect(.degrees(-heading))

            // Degree readout
            Text(String(format: "%03.0f\u{00B0}", heading))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .offset(y: -5)
        }
    }

    private func compassLabel(_ text: String, angle: Double, color: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(color)
            .offset(y: -105)
            .rotationEffect(.degrees(angle))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Trip Stats

struct TripStatsScreenContent: View {
    let screenData: TripStatsData

    var body: some View {
        let hours = screenData.rideTimeSeconds / 3600
        let minutes = (screenData.rideTimeSeconds % 3600) / 60
        let distKm = Double(screenData.distanceMeters) / 1000.0
        let avg = Double(screenData.averageSpeedKmhX10) / 10.0
        let maxSpd = Double(screenData.maxSpeedKmhX10) / 10.0

        VStack(spacing: 4) {
            Text("ACTIVE RIDE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(green)
                .tracking(1.5)

            Text(String(format: "%d:%02dh", hours, minutes))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Ride Time")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(dimGray)

            Divider().background(Color(hex: 0x333333)).padding(.horizontal, 20).padding(.vertical, 4)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", distKm))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("km")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(dimGray)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color(hex: 0x333333)).frame(width: 1, height: 40)

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", avg))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("avg km/h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(dimGray)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(screenData.ascentMeters)m")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(green)
                    Text("Elevation")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(dimGray)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", maxSpd))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(gold)
                    Text("max km/h")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(dimGray)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Lean Angle

struct LeanAngleScreenContent: View {
    let screenData: LeanAngleData

    var body: some View {
        let current = Double(screenData.currentLeanDegX10) / 10.0
        let maxL = Double(screenData.maxLeftLeanDegX10) / 10.0
        let maxR = Double(screenData.maxRightLeanDegX10) / 10.0
        let direction = current < 0 ? "left" : current > 0 ? "right" : "--"

        ZStack {
            // Arc gauge background
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color(hex: 0x333333), lineWidth: 3)
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(0))

            // Colored zones (green/amber)
            Circle()
                .trim(from: 0.15, to: 0.35)
                .stroke(
                    LinearGradient(colors: [gold, green], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 6
                )
                .frame(width: 180, height: 180)

            Circle()
                .trim(from: 0.65, to: 0.85)
                .stroke(
                    LinearGradient(colors: [green, gold], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 6
                )
                .frame(width: 180, height: 180)

            // Needle
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 70)
                .offset(y: -35)
                .rotationEffect(.degrees(current * 2.0))

            // Center dot
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)

            VStack(spacing: 2) {
                Text("LEAN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(dimGray)
                    .tracking(1.5)
                    .padding(.top, 10)

                Spacer()

                Text(String(format: "%.0f\u{00B0}", abs(current)))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(direction)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(green)

                Spacer().frame(height: 4)

                HStack {
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f\u{00B0}", abs(maxL)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(gold)
                        Text("max L")
                            .font(.system(size: 9))
                            .foregroundStyle(dimGray)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f\u{00B0}", abs(maxR)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(gold)
                        Text("max R")
                            .font(.system(size: 9))
                            .foregroundStyle(dimGray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Clock

struct ClockScreenContent: View {
    let screenData: ClockData

    var body: some View {
        let date = Date(timeIntervalSince1970: TimeInterval(screenData.unixTime))
        let tz = TimeZone(secondsFromGMT: Int(screenData.tzOffsetMinutes) * 60) ?? .current

        let timeFmt = DateFormatter()
        timeFmt.timeZone = tz
        timeFmt.dateFormat = "HH:mm"

        let dateFmt = DateFormatter()
        dateFmt.timeZone = tz
        dateFmt.locale = Locale(identifier: "en_US")
        dateFmt.dateFormat = "EEE, MMMM d"

        return VStack(spacing: 6) {
            Spacer()

            Text(dateFmt.string(from: date).uppercased())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dimGray)
                .tracking(0.5)

            Text(timeFmt.string(from: date))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Basel — 18\u{00B0}C")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dimGray)

            Spacer().frame(height: 12)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(green).frame(width: 6, height: 6)
                    Text("BLE")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dimGray)
                }
                HStack(spacing: 4) {
                    Circle().fill(blue).frame(width: 6, height: 6)
                    Text("WiFi")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dimGray)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Altitude

struct AltitudeScreenContent: View {
    let screenData: AltitudeProfileData

    var body: some View {
        VStack(spacing: 4) {
            Text("ELEVATION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dimGray)
                .tracking(1.5)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatAltitude(screenData.currentAltitudeM))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("m")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(lightGray)
            }

            // Elevation profile graph
            ElevationGraph(samples: screenData.profile)
                .frame(height: 60)
                .padding(.horizontal, 16)

            HStack {
                VStack(spacing: 0) {
                    Text("\u{2191} \(formatAltitude(Int32(screenData.totalAscentM)))m")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(green)
                    Text("Ascent")
                        .font(.system(size: 9))
                        .foregroundStyle(dimGray)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\u{2193} \(formatAltitude(Int32(screenData.totalDescentM)))m")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(gold)
                    Text("Descent")
                        .font(.system(size: 9))
                        .foregroundStyle(dimGray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    private func formatAltitude(_ value: some BinaryInteger) -> String {
        let num = Int(value)
        if num >= 1000 {
            return "\(num / 1000)'\(String(format: "%03d", num % 1000))"
        }
        return "\(num)"
    }
}

private struct ElevationGraph: View {
    let samples: [Int16]

    var body: some View {
        GeometryReader { geo in
            let filtered = samples.filter { $0 != 0 }
            if filtered.count > 1 {
                let minAlt = Double(filtered.min() ?? 0)
                let maxAlt = Double(filtered.max() ?? 1)
                let range = max(maxAlt - minAlt, 1)

                Path { path in
                    for (idx, sample) in filtered.enumerated() {
                        let px = geo.size.width * CGFloat(idx) / CGFloat(filtered.count - 1)
                        let py = geo.size.height * (1.0 - (Double(sample) - minAlt) / range)
                        if idx == 0 {
                            path.move(to: CGPoint(x: px, y: py))
                        } else {
                            path.addLine(to: CGPoint(x: px, y: py))
                        }
                    }
                }
                .stroke(green, lineWidth: 2)
            }
        }
    }
}

// MARK: - Waiting / Placeholder

struct PreviewWaitingIndicator: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: gold))
            .scaleEffect(1.2)
    }
}

struct PreviewPlaceholder: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(dimGray)
            .multilineTextAlignment(.center)
    }
}
// swiftlint:enable file_length
