import BLEProtocol
import SwiftUI

// MARK: - Additional screen renderers (split for file length)

/// Shared gold accent color for the AMOLED display preview.
private let auxPreviewGold = Color(hex: 0xEBAB00)

struct FuelScreenContent: View {
    let screenData: FuelData

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 28))
                .foregroundStyle(auxPreviewGold)

            Text("\(screenData.tankPercent)%")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            if screenData.estimatedRangeKm != FuelData.unknown {
                Text("\(screenData.estimatedRangeKm) km range")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x999999))
            }
        }
    }
}

struct NavScreenContent: View {
    let screenData: NavData

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: NavScreenContent.maneuverIcon(for: screenData.maneuver))
                .font(.system(size: 32))
                .foregroundStyle(auxPreviewGold)

            if screenData.distanceToManeuverMeters != NavData.unknownU16 {
                Text("\(screenData.distanceToManeuverMeters) m")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if !screenData.streetName.isEmpty {
                Text(screenData.streetName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x999999))
                    .lineLimit(1)
            }

            if screenData.etaMinutes != NavData.unknownU16 {
                Text("ETA \(screenData.etaMinutes) min")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x666666))
            }
        }
        .padding(.horizontal, 12)
    }

    private static let maneuverIcons: [ManeuverType: String] = [
        .none: "arrow.up",
        .straight: "arrow.up",
        .slightLeft: "arrow.up.left",
        .left: "arrow.left",
        .sharpLeft: "arrow.down.left",
        .uTurnLeft: "arrow.uturn.left",
        .slightRight: "arrow.up.right",
        .right: "arrow.right",
        .sharpRight: "arrow.down.right",
        .uTurnRight: "arrow.uturn.right",
        .roundaboutEnter: "arrow.triangle.capsulepath",
        .roundaboutExit: "arrow.triangle.capsulepath",
        .merge: "arrow.merge",
        .forkLeft: "arrow.up.left",
        .forkRight: "arrow.up.right",
        .arrive: "mappin.circle.fill"
    ]

    static func maneuverIcon(for maneuver: ManeuverType) -> String {
        maneuverIcons[maneuver] ?? "arrow.up"
    }
}

struct AppointmentScreenContent: View {
    let screenData: AppointmentData

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 28))
                .foregroundStyle(auxPreviewGold)

            Text(screenData.title.isEmpty ? "--" : screenData.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if !screenData.location.isEmpty {
                Text(screenData.location)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x999999))
                    .lineLimit(1)
            }

            let mins = screenData.startsInMinutes
            Text(mins < 0 ? "Started \(abs(mins)) min ago" : "In \(mins) min")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(auxPreviewGold)
        }
        .padding(.horizontal, 12)
    }
}

struct IncomingCallScreenContent: View {
    let screenData: IncomingCallData

    var body: some View {
        let stateText: String = {
            switch screenData.callState {
            case .incoming: return "Incoming"
            case .connected: return "Connected"
            case .ended: return "Ended"
            }
        }()

        VStack(spacing: 8) {
            Image(systemName: "phone.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    screenData.callState == .ended
                        ? Color(hex: 0xE24B4A)
                        : auxPreviewGold
                )

            Text(screenData.callerHandle.isEmpty ? "Unknown" : screenData.callerHandle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(stateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x999999))
        }
    }
}

struct BlitzerScreenContent: View {
    let screenData: BlitzerData

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: 0xE24B4A))

            Text("\(screenData.distanceMeters) m")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            if screenData.speedLimitKmh != BlitzerData.unknownSpeedLimit {
                Text("Limit: \(screenData.speedLimitKmh) km/h")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(auxPreviewGold)
            }

            Text(String(format: "%.1f km/h", Double(screenData.currentSpeedKmhX10) / 10.0))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Shared placeholder views

struct PreviewWaitingIndicator: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(Color(hex: 0x666666))
            Text("Waiting for data...")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x444444))
        }
    }
}

struct PreviewPlaceholder: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: 0x444444))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x444444))
                .multilineTextAlignment(.center)
        }
    }
}
