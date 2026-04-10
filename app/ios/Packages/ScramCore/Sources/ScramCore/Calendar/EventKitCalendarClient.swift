import Foundation
import RideSimulatorKit

#if canImport(EventKit)
import EventKit

/// Real EventKit calendar client that fetches upcoming events from the
/// user's on-device calendars.
///
/// Requires `NSCalendarsFullAccessUsageDescription` in the app's Info.plist
/// (iOS 17+). On first call, the client requests full calendar access via
/// `EKEventStore.requestFullAccessToEvents()`. If the user denies access,
/// the client throws ``CalendarServiceError/accessDenied`` so the caller
/// (``RealCalendarProvider``) can swallow the error and keep polling without
/// crashing.
public struct EventKitCalendarClient: CalendarServiceClient, Sendable {
    private let preferences: CalendarPreferences?
    private let store: EKEventStore

    /// Look-ahead window: fetch events starting within the next 24 hours.
    private static let lookAheadSeconds: TimeInterval = 24 * 60 * 60

    public init(preferences: CalendarPreferences? = nil) {
        self.preferences = preferences
        self.store = EKEventStore()
    }

    public func fetchNextEvent() async throws -> CalendarServiceResponse? {
        try await requestAccessIfNeeded()

        let now = Date()
        let end = now.addingTimeInterval(Self.lookAheadSeconds)

        // Build the list of calendars to search, filtered by user preferences.
        let allCalendars = store.calendars(for: .event)
        let selectedCalendars: [EKCalendar]
        if let preferences {
            selectedCalendars = allCalendars.filter { preferences.isSelected($0.calendarIdentifier) }
        } else {
            selectedCalendars = allCalendars
        }

        guard !selectedCalendars.isEmpty else {
            return nil
        }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: end,
            calendars: selectedCalendars
        )
        let events = store.events(matching: predicate)

        // Find the earliest event by start date.
        guard let earliest = events.min(by: { $0.startDate < $1.startDate }) else {
            return nil
        }

        let startsInSeconds = earliest.startDate.timeIntervalSince(now)
        return CalendarServiceResponse(
            title: earliest.title ?? "",
            startsInSeconds: startsInSeconds,
            location: earliest.location ?? ""
        )
    }

    // MARK: - Private

    private func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized, .fullAccess:
            return
        case .denied, .restricted:
            throw CalendarServiceError.accessDenied
        case .notDetermined:
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            guard granted else {
                throw CalendarServiceError.accessDenied
            }
        case .writeOnly:
            throw CalendarServiceError.accessDenied
        @unknown default:
            throw CalendarServiceError.accessDenied
        }
    }
}
#endif
