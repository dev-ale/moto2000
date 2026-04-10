import BLECentralClient
import EventKit
import ScramCore
import SwiftUI

struct MehrView: View {
    @State var connection: ConnectionViewModel

    @AppStorage("scramscreen.unit.speed")
    private var useKmh = true
    @AppStorage("scramscreen.unit.temp")
    private var useCelsius = true
    @AppStorage("scramscreen.alert.sound")
    private var alertSounds = true
    @AppStorage("scramscreen.display.autoSleep")
    private var autoSleepMinutes = 5
    @AppStorage("scramscreen.display.brightness")
    private var brightness: Double = 80

    @State private var showUnpairConfirm = false
    @State var ekCalendars: [EKCalendar] = []

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                Text("Mehr")
                    .font(.scramTitle)
                    .foregroundStyle(Color.scramTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScramSpacing.xxl)

                // MARK: - Device

                settingsSection("Geraet") {
                    deviceSection
                }

                // MARK: - Display

                settingsSection("Anzeige") {
                    displaySection
                }

                // MARK: - Units

                settingsSection("Einheiten") {
                    unitsSection
                }

                // MARK: - Calendar

                settingsSection("Kalender") {
                    calendarSection
                }

                // MARK: - Alerts

                settingsSection("Benachrichtigungen") {
                    alertsSection
                }

                // MARK: - About

                settingsSection("Info") {
                    aboutSection
                }
            }
            .padding(.horizontal, ScramSpacing.xl)
            .padding(.bottom, ScramSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .onAppear { refreshCalendars() }
    }

    // MARK: - Section wrapper

    func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            SectionHeader(title: title)
            VStack(spacing: 1) {
                content()
            }
            .background(Color.scramSurface)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
        }
    }

    // MARK: - Device

    private var deviceSection: some View {
        Group {
            if connection.isPaired {
                settingsRow(
                    icon: "circle.circle",
                    title: connection.accessoryManager.deviceName,
                    detail: connection.statusText,
                    detailColor: connection.statusColor
                )

                settingsRow(
                    icon: "cpu",
                    title: "Firmware",
                    detail: "--"
                )

                Button { showUnpairConfirm = true } label: {
                    settingsRow(
                        icon: "xmark.circle",
                        title: "Geraet entkoppeln",
                        titleColor: .scramRed
                    )
                }
                .alert("Geraet entkoppeln?", isPresented: $showUnpairConfirm) {
                    Button("Abbrechen", role: .cancel) {}
                    Button("Entkoppeln", role: .destructive) {
                        connection.unpair()
                    }
                } message: {
                    Text("Das Display wird entkoppelt und muss erneut hinzugefuegt werden.")
                }
            } else {
                Button { connection.showPicker() } label: {
                    settingsRow(
                        icon: "plus.circle",
                        title: "Geraet hinzufuegen",
                        titleColor: .scramBlue
                    )
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Group {
            VStack(spacing: ScramSpacing.sm) {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundStyle(Color.scramTextTertiary)
                    Slider(value: $brightness, in: 10...100, step: 5)
                        .tint(Color.scramGreen)
                    Image(systemName: "sun.max")
                        .foregroundStyle(Color.scramTextTertiary)
                    Text("\(Int(brightness))%")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(ScramSpacing.lg)

            settingsPickerRow(
                icon: "moon",
                title: "Auto-Sleep",
                options: [2, 5, 10, 15, 30],
                labels: ["2 Min", "5 Min", "10 Min", "15 Min", "30 Min"],
                selection: $autoSleepMinutes
            )
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Group {
            settingsToggleRow(
                icon: "speedometer",
                title: "Geschwindigkeit",
                onLabel: "km/h",
                offLabel: "mph",
                isOn: $useKmh
            )

            settingsToggleRow(
                icon: "thermometer.medium",
                title: "Temperatur",
                onLabel: "°C",
                offLabel: "°F",
                isOn: $useCelsius
            )
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Group {
            HStack {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.scramGreen)
                    .frame(width: 24)

                Text("Alarm-Ton")
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)

                Spacer()

                Toggle("", isOn: $alertSounds)
                    .labelsHidden()
                    .tint(Color.scramGreen)
            }
            .padding(ScramSpacing.lg)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            settingsRow(
                icon: "app",
                title: "App Version",
                detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "1.0"
            )

            settingsRow(
                icon: "number",
                title: "Protokoll",
                detail: "v\(AppInfo.protocolVersion)"
            )

            settingsRow(
                icon: "doc.text",
                title: "Lizenzen",
                chevron: true
            )

            settingsRow(
                icon: "envelope",
                title: "Feedback",
                chevron: true
            )
        }
    }
}
