import BLECentralClient
import ScramCore
import SwiftUI

struct OTAUpdateView: View {
    let currentVersion: FirmwareVersion?
    let update: FirmwareUpdate
    let onStartUpdate: () -> Void
    /// Closure that writes one OTA frame to the BLE `ota_data`
    /// characteristic. Injected from the parent so this view stays
    /// transport-agnostic.
    let sendOTA: @Sendable (Data) async throws -> Void

    @AppStorage("scramscreen.wifi.ssid")
    private var wifiSSID: String = ""
    @AppStorage("scramscreen.wifi.pwd")
    private var wifiPassword: String = ""

    @Environment(\.dismiss)
    private var dismiss
    @State private var updateState: UpdateState = .ready

    enum UpdateState: Equatable {
        case ready
        case downloading(progress: Double)
        case verifying
        case applying
        case success
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.scramTextTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, ScramSpacing.md)
                .padding(.bottom, ScramSpacing.xxl)

            // Title
            Text("Firmware Update")
                .font(.scramTitle)
                .foregroundStyle(Color.scramTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(height: ScramSpacing.xxl)

            // Version comparison
            versionComparison

            // Release notes
            if let notes = update.releaseNotes, !notes.isEmpty {
                Spacer().frame(height: ScramSpacing.xl)
                releaseNotesSection(notes)
            }

            Spacer().frame(height: ScramSpacing.xxl)

            // Progress / Action area
            stateView

            Spacer()
        }
        .padding(.horizontal, ScramSpacing.xl)
        .padding(.bottom, ScramSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
    }

    // MARK: - Version comparison

    private var versionComparison: some View {
        HStack(spacing: ScramSpacing.lg) {
            versionBox(
                label: "Aktuell",
                version: currentVersion?.versionString ?? "--"
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.scramGreen)

            versionBox(
                label: "Neu",
                version: update.version.versionString
            )
        }
        .padding(ScramSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    private func versionBox(label: String, version: String) -> some View {
        VStack(spacing: ScramSpacing.xs) {
            Text(label.uppercased())
                .font(.scramOverline)
                .foregroundStyle(Color.scramTextTertiary)
                .tracking(0.5)

            Text("v\(version)")
                .font(.scramMetric)
                .foregroundStyle(Color.scramTextPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Release notes

    private func releaseNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: ScramSpacing.sm) {
            Text("CHANGES")
                .font(.scramOverline)
                .foregroundStyle(Color.scramTextTertiary)
                .tracking(0.5)

            ScrollView {
                Text(notes)
                    .font(.scramSubhead)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
        .padding(ScramSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - State view

    @ViewBuilder private var stateView: some View {
        switch updateState {
        case .ready:
            Button {
                startUpdate()
            } label: {
                Text("Start Update")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.lg)
                    .background(Color.scramGreen)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
            }

        case .downloading(let progress):
            progressView(label: "Downloading...", progress: progress)

        case .verifying:
            progressView(label: "Verifying...", progress: nil)

        case .applying:
            progressView(label: "Installing...", progress: nil)

        case .success:
            VStack(spacing: ScramSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.scramGreen)

                Text("Update successful")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text("The device will restart.")
                    .font(.scramSubhead)
                    .foregroundStyle(Color.scramTextSecondary)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramGreen)
                        .padding(.top, ScramSpacing.sm)
                }
            }

        case .failed(let message):
            VStack(spacing: ScramSpacing.md) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.scramRed)

                Text("Update failed")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text(message)
                    .font(.scramSubhead)
                    .foregroundStyle(Color.scramTextSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    updateState = .ready
                } label: {
                    Text("Try again")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramGreen)
                        .padding(.top, ScramSpacing.sm)
                }
            }
        }
    }

    private func progressView(label: String, progress: Double?) -> some View {
        VStack(spacing: ScramSpacing.lg) {
            ZStack {
                Circle()
                    .stroke(Color.scramSurfaceElevated, lineWidth: 6)
                    .frame(width: 80, height: 80)

                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.scramGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(progress * 100))%")
                        .font(.scramMetric)
                        .foregroundStyle(Color.scramTextPrimary)
                } else {
                    ProgressView()
                        .tint(Color.scramGreen)
                }
            }

            Text(label)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextSecondary)
        }
    }

    // MARK: - Update flow

    private func startUpdate() {
        guard !wifiSSID.isEmpty else {
            updateState = .failed("Set WiFi credentials in More tab first.")
            return
        }
        onStartUpdate()
        updateState = .downloading(progress: 0)

        let url = update.downloadURL
        let ssid = wifiSSID
        let password = wifiPassword
        let send = sendOTA
        Task {
            let uploader = OTAUploader()
            do {
                try await uploader.startWifiOTA(
                    ssid: ssid,
                    password: password,
                    url: url,
                    send: send
                )
                // The firmware now owns the rest of the flow. Show
                // "applying" until the BLE link drops on reboot — at
                // which point ConnectionViewModel will surface it.
                await MainActor.run {
                    updateState = .applying
                }
            } catch {
                let msg = describe(error)
                await MainActor.run {
                    updateState = .failed(msg)
                }
            }
        }
    }

    /// Render a useful error string instead of "BLECentralClientError error 1".
    private func describe(_ error: Error) -> String {
        if let bleError = error as? BLECentralClientError {
            switch bleError {
            case .notConnected:
                return "Display not connected. Reconnect and try again."
            case .writeFailed(let message):
                return "BLE write failed: \(message)"
            case .bluetoothOff:
                return "Bluetooth is off."
            }
        }
        return error.localizedDescription
    }
}
