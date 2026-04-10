import BLECentralClient
import MapKit
import SwiftUI

struct HomeView: View {
    @State var connection: ConnectionViewModel

    @State private var showLivePreview = false
    #if DEBUG
    @State private var showSimulator = false
    @State private var showScreenPicker = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                // MARK: - Connection pill + title

                VStack(spacing: ScramSpacing.lg) {
                    ConnectionPill(connected: connection.isConnected)
                        .animation(.easeInOut(duration: 0.3), value: connection.isConnected)

                    Text("ScramScreen")
                        .font(.scramLargeTitle)
                        .foregroundStyle(Color.scramTextPrimary)
                }
                .padding(.top, ScramSpacing.xxl)

                // MARK: - Main card

                if connection.isPaired {
                    connectedCard
                } else {
                    setupCard
                }

                // MARK: - Navigation search

                NavigationSearchView()

                // MARK: - Quick stats (only when paired)

                if connection.isPaired {
                    HStack(spacing: ScramSpacing.sm) {
                        StatCard(
                            value: connection.isConnected ? "80%" : "--",
                            label: "Helligkeit"
                        )
                        StatCard(value: "Tag", label: "Modus")
                        StatCard(value: "--", label: "Firmware")
                    }
                }

                // MARK: - Live Preview

                livePreviewSection

                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, ScramSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .onAppear {
            connection.startObserving()
        }
    }

    // MARK: - Setup card (not yet paired)

    private var setupCard: some View {
        VStack(spacing: ScramSpacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.scramBlue.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "plus.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.scramBlue)
            }

            VStack(spacing: ScramSpacing.sm) {
                Text("Display koppeln")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text("Koppele dein ScramScreen Display mit einem Tippen")
                    .font(.scramSubhead)
                    .foregroundStyle(Color.scramTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button { connection.showPicker() } label: {
                Text("Geraet hinzufuegen")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
            }
            .background(Color.scramBlue)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
        .padding(ScramSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Connected/paired card

    private var connectedCard: some View {
        VStack(spacing: ScramSpacing.xl) {
            ZStack {
                Circle()
                    .fill(connection.statusColor.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: connection.statusIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(connection.statusColor)
                    .symbolEffect(.pulse, isActive: connection.healthLevel == .degraded)
            }

            VStack(spacing: ScramSpacing.sm) {
                Text(connection.accessoryManager.deviceName)
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text(connection.statusText)
                    .font(.scramSubhead)
                    .foregroundStyle(connection.statusColor)
            }

            // Action buttons
            switch connection.state {
            case .idle, .disconnected:
                HStack(spacing: ScramSpacing.sm) {
                    Button { connection.connect() } label: {
                        Text("Verbinden")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ScramSpacing.md)
                    }
                    .background(Color.scramGreen)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))

                    Button { connection.unpair() } label: {
                        Text("Entkoppeln")
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextTertiary)
                            .padding(.vertical, ScramSpacing.md)
                            .padding(.horizontal, ScramSpacing.lg)
                    }
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
                }

            case .connected:
                Button { connection.disconnect() } label: {
                    Text("Trennen")
                        .font(.scramHeadline)
                        .foregroundStyle(Color.scramRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ScramSpacing.md)
                }
                .background(Color.scramRedBg)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))

            default:
                Button { connection.disconnect() } label: {
                    HStack(spacing: ScramSpacing.sm) {
                        ProgressView()
                            .tint(Color.scramTextSecondary)
                        Text("Abbrechen")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                }
                .background(Color.scramSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
            }
        }
        .padding(ScramSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Live Preview

    private var livePreviewSection: some View {
        VStack(spacing: ScramSpacing.sm) {
            SectionHeader(title: "Display Vorschau")

            Button {
                showLivePreview = true
            } label: {
                HStack(spacing: ScramSpacing.sm) {
                    Image(systemName: "circle.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                    Text("Live Preview starten")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.scramTextTertiary)
                }
                .padding(ScramSpacing.lg)
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            }
            .fullScreenCover(isPresented: $showLivePreview) {
                DisplayPreviewView(isPresented: $showLivePreview)
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: ScramSpacing.sm) {
            SectionHeader(title: "Debug")

            HStack(spacing: ScramSpacing.sm) {
                Button("Ride Simulator") { showSimulator = true }
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
                    .sheet(isPresented: $showSimulator) {
                        ScenarioPickerView()
                    }

                Button("Screen Picker") { showScreenPicker = true }
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
                    .sheet(isPresented: $showScreenPicker) {
                        ScreenPickerView()
                    }
            }

        }
    }
    #endif
}
