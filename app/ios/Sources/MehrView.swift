import BLECentralClient
import SwiftUI

// swiftlint:disable:next type_body_length
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
    @AppStorage("scramscreen.fuel.tankCapacityLiters")
    private var tankCapacityLiters: Double = 15

    @State private var showUnpairConfirm = false

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

                // MARK: - Tank

                settingsSection("Tank") {
                    tankSection
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
    }

    // MARK: - Section wrapper

    private func settingsSection<Content: View>(
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

    // MARK: - Tank

    private var tankSection: some View {
        Group {
            settingsPickerRow(
                icon: "fuelpump",
                title: "Tankvolumen",
                options: [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
                labels: ["9 L", "10 L", "11 L", "12 L", "13 L", "14 L", "15 L", "16 L", "17 L", "18 L", "19 L", "20 L"],
                selection: Binding(
                    get: { Int(tankCapacityLiters) },
                    set: { tankCapacityLiters = Double($0) }
                )
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
                detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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

    // MARK: - Row helpers

    private func settingsRow(
        icon: String,
        title: String,
        titleColor: Color = .scramTextPrimary,
        detail: String? = nil,
        detailColor: Color = .scramTextSecondary,
        chevron: Bool = false
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(titleColor == .scramRed ? Color.scramRed : Color.scramGreen)
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(titleColor)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.scramCaption)
                    .foregroundStyle(detailColor)
            }

            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.scramTextTertiary)
            }
        }
        .padding(ScramSpacing.lg)
    }

    private func settingsToggleRow(
        icon: String,
        title: String,
        onLabel: String,
        offLabel: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            HStack(spacing: 0) {
                unitButton(offLabel, selected: !isOn.wrappedValue) {
                    isOn.wrappedValue = false
                }
                unitButton(onLabel, selected: isOn.wrappedValue) {
                    isOn.wrappedValue = true
                }
            }
            .background(Color.scramSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
        .padding(ScramSpacing.lg)
    }

    private func unitButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.scramCaption)
                .foregroundStyle(selected ? Color.scramBackground : Color.scramTextSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(selected ? Color.scramGreen : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
    }

    private func settingsPickerRow(
        icon: String,
        title: String,
        options: [Int],
        labels: [String],
        selection: Binding<Int>
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            Menu {
                ForEach(Array(zip(options, labels)), id: \.0) { value, label in
                    Button(label) {
                        selection.wrappedValue = value
                    }
                }
            } label: {
                HStack(spacing: ScramSpacing.xs) {
                    Text(labels[options.firstIndex(of: selection.wrappedValue) ?? 1])
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.scramTextTertiary)
                }
            }
        }
        .padding(ScramSpacing.lg)
    }
}
