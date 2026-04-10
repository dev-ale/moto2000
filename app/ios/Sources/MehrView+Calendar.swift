import EventKit
import ScramCore
import SwiftUI

extension MehrView {
    static let calendarPreferences = CalendarPreferences(
        store: UserDefaults.standard
    )

    private static let eventStore = EKEventStore()

    // MARK: - Calendar section

    var calendarSection: some View {
        Group {
            if ekCalendars.isEmpty {
                HStack(spacing: ScramSpacing.md) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                        .frame(width: 24)

                    Text("Keine Kalender verfuegbar")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextSecondary)

                    Spacer()
                }
                .padding(ScramSpacing.lg)
            } else {
                ForEach(ekCalendars, id: \.calendarIdentifier) { calendar in
                    calendarRow(calendar)
                }
            }
        }
    }

    func calendarRow(_ calendar: EKCalendar) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 12, height: 12)
                .frame(width: 24)

            Text(calendar.title)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            Toggle("", isOn: Binding(
                get: {
                    Self.calendarPreferences.isSelected(
                        calendar.calendarIdentifier
                    )
                },
                set: { _ in
                    Self.calendarPreferences.toggleSelection(
                        calendar.calendarIdentifier
                    )
                    ekCalendars = ekCalendars
                }
            ))
            .labelsHidden()
            .tint(Color.scramGreen)
        }
        .padding(ScramSpacing.lg)
    }

    func refreshCalendars() {
        let calendars = Self.eventStore
            .calendars(for: .event)
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedAscending
            }
        ekCalendars = calendars

        let knownIDs = Set(calendars.map(\.calendarIdentifier))
        Self.calendarPreferences.reconcile(knownCalendarIDs: knownIDs)
    }
}
