import ScramCore
import SwiftUI

extension MehrView {
    var speedCameraSection: some View {
        Group {
            let db = try? UpdatableSpeedCameraDatabase()

            settingsRow(
                icon: "camera.fill",
                title: "Database",
                detail: "\(db?.count ?? 0) cameras (\(db?.source.rawValue ?? "—"))"
            )

            Button {
                Task { await updateCameraDatabase() }
            } label: {
                HStack(spacing: ScramSpacing.md) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                        .frame(width: 24)

                    Text("Update Now")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)

                    Spacer()

                    if isUpdatingCameras {
                        ProgressView()
                            .tint(Color.scramGreen)
                    } else if let status = cameraUpdateStatus {
                        Text(status)
                            .font(.scramCaption)
                            .foregroundStyle(Color.scramTextSecondary)
                    }
                }
                .padding(ScramSpacing.lg)
            }
            .disabled(isUpdatingCameras)
        }
    }

    func updateCameraDatabase() async {
        isUpdatingCameras = true
        cameraUpdateStatus = nil
        do {
            let count = try await SpeedCameraUpdater().update()
            cameraUpdateStatus = "\(count) cameras"
        } catch {
            cameraUpdateStatus = "Error"
        }
        isUpdatingCameras = false
    }
}
