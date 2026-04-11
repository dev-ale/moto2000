import ScramCore
import SwiftUI

struct TankView: View {
    @AppStorage("scramscreen.fuel.tankCapacityLiters")
    private var tankCapacityLiters: Double = 15

    @State private var fuelLog: FuelLog
    @State private var fills: [FuelFillEntry] = []
    @State private var estimate: FuelRangeCalculator.Estimate = .init()

    @State private var litersInput: String = ""
    @State private var isFull: Bool = false
    @State private var isSaving: Bool = false
    @State var nearbyStations: [GasStation] = []
    @State var loadingStations: Bool = false

    private let odometer: GPSOdometer

    init(fuelLog: FuelLog, odometer: GPSOdometer = GPSOdometer()) {
        self._fuelLog = State(initialValue: fuelLog)
        self.odometer = odometer
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                // MARK: - Title
                Text("Tank")
                    .font(.scramTitle)
                    .foregroundStyle(Color.scramTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScramSpacing.xxl)

                // MARK: - Current estimates
                estimatesSection

                // MARK: - Nearby gas stations
                nearbyStationsSection

                // MARK: - Fill entry
                fillEntrySection

                // MARK: - Fill history
                fillHistorySection
            }
            .padding(.horizontal, ScramSpacing.xl)
            .padding(.bottom, ScramSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .task {
            await loadData()
            await searchNearbyStations()
        }
    }

    // MARK: - Estimates

    private var estimatesSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Current")
            HStack(spacing: ScramSpacing.sm) {
                StatCard(
                    value: estimate.rangeKm.map { "\(Int($0))" } ?? "--",
                    label: "Range km"
                )
                StatCard(
                    value: estimate.consumptionMlPerKm.map {
                        String(format: "%.1f", 1000.0 / $0)
                    } ?? "--",
                    label: "km/L"
                )
                StatCard(
                    value: distanceSinceLastFullFillFormatted,
                    label: "Since fill km"
                )
            }
        }
    }

    private var distanceSinceLastFullFillFormatted: String {
        guard let lastFull = fills.last(where: { $0.isFull }) else { return "--" }
        // Sum distance of all fills after the last full fill, plus current distance
        let fillsAfterLastFull = fills.drop(while: { $0.id != lastFull.id }).dropFirst()
        let loggedDistance = fillsAfterLastFull.reduce(0.0) { $0 + $1.distanceSinceLastFillKm }
        // The current distance since the most recent fill is tracked by FuelService;
        // for display we approximate using the odometer delta
        return "\(Int(loggedDistance))"
    }

    // MARK: - Fill entry

    private var fillEntrySection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Fuel Stop")
            VStack(spacing: ScramSpacing.lg) {
                // Liters input
                HStack(spacing: ScramSpacing.md) {
                    Image(systemName: "fuelpump")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                        .frame(width: 24)

                    TextField("Liter", text: $litersInput)
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)
                        .keyboardType(.decimalPad)

                    Text("L")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                }
                .padding(ScramSpacing.lg)
                .background(Color.scramSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))

                // Tank voll toggle
                HStack(spacing: ScramSpacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                        .frame(width: 24)

                    Text("Tank full")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)

                    Spacer()

                    Toggle("", isOn: $isFull)
                        .labelsHidden()
                        .tint(Color.scramGreen)
                }
                .padding(ScramSpacing.lg)
                .background(Color.scramSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))

                // Save button
                Button {
                    Task { await saveFill() }
                } label: {
                    Text("Save")
                        .font(.scramHeadline)
                        .foregroundStyle(Color.scramBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ScramSpacing.md)
                        .background(Color.scramGreen)
                        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
                }
                .disabled(isSaving || parsedLiters == nil)
                .opacity(parsedLiters == nil ? 0.5 : 1.0)
            }
            .padding(ScramSpacing.lg)
            .background(Color.scramSurface)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
        }
    }

    // MARK: - Fill history

    private var fillHistorySection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Fuel Stops")

            if fills.isEmpty {
                emptyState
            } else {
                VStack(spacing: 1) {
                    ForEach(fills.reversed()) { fill in
                        fillRow(fill)
                    }
                }
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ScramSpacing.md) {
            Image(systemName: "fuelpump")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.scramTextTertiary)
            Text("No fuel stops yet")
                .font(.scramBody)
                .foregroundStyle(Color.scramTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ScramSpacing.xxl)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    private func fillRow(_ fill: FuelFillEntry) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: fill.isFull ? "fuelpump.fill" : "fuelpump")
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: ScramSpacing.xs) {
                Text(fill.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)

                HStack(spacing: ScramSpacing.sm) {
                    Text(String(format: "%.1f L", fill.amountMilliliters / 1000.0))
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)

                    if fill.isFull, fill.distanceSinceLastFillKm > 0 {
                        let kmPerL = fill.distanceSinceLastFillKm / (fill.amountMilliliters / 1000.0)
                        Text(String(format: "%.1f km/L", kmPerL))
                            .font(.scramCaption)
                            .foregroundStyle(Color.scramTextTertiary)
                    }
                }
            }

            Spacer()

            if fill.distanceSinceLastFillKm > 0 {
                Text("\(Int(fill.distanceSinceLastFillKm)) km")
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
            }
        }
        .padding(ScramSpacing.lg)
    }

    // MARK: - Helpers

    private var parsedLiters: Double? {
        let cleaned = litersInput.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private func saveFill() async {
        guard let liters = parsedLiters else { return }
        isSaving = true
        defer { isSaving = false }

        let entry = FuelFillEntry(
            amountMilliliters: liters * 1000.0,
            distanceSinceLastFillKm: odometer.totalKm,
            isFull: isFull
        )

        do {
            try await fuelLog.addFill(entry)
            litersInput = ""
            isFull = false
            if entry.isFull {
                odometer.reset()
            }
            await loadData()
        } catch {
            // Silently fail — future slice can add error display
        }
    }

    private func loadData() async {
        do {
            fills = try await fuelLog.allEntries()
            let settings = FuelSettings(tankCapacityMl: tankCapacityLiters * 1000.0)
            estimate = FuelRangeCalculator.estimate(
                fills: fills,
                currentDistanceSinceLastFillKm: odometer.totalKm,
                settings: settings
            )
        } catch {
            // Silently fail
        }
    }
}
