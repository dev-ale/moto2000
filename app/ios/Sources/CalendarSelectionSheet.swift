import EventKit
import ScramCore
import SwiftUI

struct CalendarSelectionSheet: View {
    let calendars: [EKCalendar]
    let preferences: CalendarPreferences

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    HStack(spacing: ScramSpacing.md) {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: 12, height: 12)

                        Text(calendar.title)
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextPrimary)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: {
                                preferences.isSelected(
                                    calendar.calendarIdentifier
                                )
                            },
                            set: { _ in
                                preferences.toggleSelection(
                                    calendar.calendarIdentifier
                                )
                            }
                        ))
                        .labelsHidden()
                        .tint(Color.scramGreen)
                    }
                    .listRowBackground(Color.scramSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.scramBackground)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.scramGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
