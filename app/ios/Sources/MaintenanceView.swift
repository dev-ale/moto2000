import ScramCore
import SwiftUI

struct MaintenanceView: View {
    private let store: MaintenanceStore
    @State private var entries: [MaintenanceEntry] = []
    @State private var showAddSheet = false

    init(store: MaintenanceStore = MaintenanceStore()) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                Text("Service Log")
                    .font(.scramTitle)
                    .foregroundStyle(Color.scramTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScramSpacing.xxl)

                if entries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .padding(.horizontal, ScramSpacing.xl)
            .padding(.bottom, ScramSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.scramGreen)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMaintenanceSheet(store: store) {
                entries = store.loadAll()
            }
        }
        .onAppear {
            entries = store.loadAll()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: ScramSpacing.lg) {
            Spacer()
                .frame(height: 80)
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.scramTextTertiary)
            Text("No service entries")
                .font(.scramTitle)
                .foregroundStyle(Color.scramTextPrimary)
            Text("Tap + to log maintenance")
                .font(.scramSubhead)
                .foregroundStyle(Color.scramTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry list

    private var entryList: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Maintenance History")
            VStack(spacing: ScramSpacing.md) {
                ForEach(entries) { entry in
                    entryCard(entry)
                }
            }
        }
    }

    // MARK: - Entry card

    private func entryCard(_ entry: MaintenanceEntry) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: entry.type.iconName)
                .font(.system(size: 20))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: ScramSpacing.xs) {
                Text(entry.type.rawValue)
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)

                HStack(spacing: ScramSpacing.sm) {
                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)

                    Text("\(Self.formatOdometer(entry.odometerKm)) km")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextTertiary)
                }

                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(ScramSpacing.lg)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static func formatOdometer(_ km: Double) -> String {
        if km >= 1000 {
            return String(format: "%.0f", km)
        }
        return String(format: "%.1f", km)
    }
}

// MARK: - Add Maintenance Sheet

private struct AddMaintenanceSheet: View {
    let store: MaintenanceStore
    let onSave: () -> Void
    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedType: MaintenanceType = .general
    @State private var odometerText = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ScramSpacing.xxl) {
                    // Type picker
                    VStack(alignment: .leading, spacing: ScramSpacing.sm) {
                        Text("Type")
                            .font(.scramOverline)
                            .foregroundStyle(Color.scramTextTertiary)
                            .textCase(.uppercase)

                        VStack(spacing: 1) {
                            ForEach(MaintenanceType.allCases, id: \.rawValue) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    HStack(spacing: ScramSpacing.md) {
                                        Image(systemName: type.iconName)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.scramGreen)
                                            .frame(width: 24)

                                        Text(type.rawValue)
                                            .font(.scramBody)
                                            .foregroundStyle(Color.scramTextPrimary)

                                        Spacer()

                                        if selectedType == type {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Color.scramGreen)
                                        }
                                    }
                                    .padding(ScramSpacing.lg)
                                }
                            }
                        }
                        .background(Color.scramSurface)
                        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
                    }

                    // Odometer
                    VStack(alignment: .leading, spacing: ScramSpacing.sm) {
                        Text("Odometer (km)")
                            .font(.scramOverline)
                            .foregroundStyle(Color.scramTextTertiary)
                            .textCase(.uppercase)

                        TextField("e.g. 12500", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextPrimary)
                            .padding(ScramSpacing.lg)
                            .background(Color.scramSurface)
                            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: ScramSpacing.sm) {
                        Text("Notes")
                            .font(.scramOverline)
                            .foregroundStyle(Color.scramTextTertiary)
                            .textCase(.uppercase)

                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextPrimary)
                            .padding(ScramSpacing.lg)
                            .background(Color.scramSurface)
                            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
                    }

                    // Save button
                    Button {
                        let odometer = Double(odometerText) ?? 0
                        let entry = MaintenanceEntry(
                            type: selectedType,
                            odometerKm: odometer,
                            notes: notes
                        )
                        store.save(entry)
                        onSave()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramBackground)
                            .frame(maxWidth: .infinity)
                            .padding(ScramSpacing.lg)
                            .background(Color.scramGreen)
                            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
                    }
                }
                .padding(.horizontal, ScramSpacing.xl)
                .padding(.vertical, ScramSpacing.xxl)
            }
            .background(Color.scramBackground)
            .navigationTitle("Add Service Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.scramTextSecondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MaintenanceView(store: {
            // swiftlint:disable:next force_unwrapping
            let defaults = UserDefaults(suiteName: "MaintenancePreview")!
            defaults.removePersistentDomain(forName: "MaintenancePreview")
            let store = MaintenanceStore(defaults: defaults)
            store.save(MaintenanceEntry(
                date: Date(),
                type: .oilChange,
                odometerKm: 12500,
                notes: "Motul 7100 10W-40"
            ))
            store.save(MaintenanceEntry(
                date: Date().addingTimeInterval(-86400 * 30),
                type: .chainLube,
                odometerKm: 12000
            ))
            return store
        }())
    }
}
