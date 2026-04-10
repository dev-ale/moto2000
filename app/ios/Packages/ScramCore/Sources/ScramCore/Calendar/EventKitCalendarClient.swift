import Foundation
import RideSimulatorKit

/*
 * EventKitCalendarClient — intentional stub (Slice 11).
 *
 * Real EventKit access requires:
 *
 *   1. An `NSCalendarsFullAccessUsageDescription` key in Info.plist (iOS 17+).
 *      On iOS 16 and earlier, the key is `NSCalendarsUsageDescription`.
 *
 *   2. A call to `EKEventStore.requestFullAccessToEvents()` at runtime.
 *      Denial must be handled gracefully — the service should stop emitting
 *      events rather than crashing.
 *
 * Rather than ship a half-working integration that needs runtime permissions
 * to even compile on CI, Slice 11 ships a stub that throws
 * `CalendarServiceError.notImplemented`. The `RealCalendarProvider`
 * swallows the error and keeps polling, so the rest of the system is
 * unaffected. A follow-up PR will swap this file for a real EventKit client
 * without touching `CalendarServiceClient`, `RealCalendarProvider`, or the
 * renderer.
 *
 * The type is gated on `canImport(EventKit)` so the stub compiles on
 * Linux CI without pulling in the framework.
 */
#if canImport(EventKit)
#warning("EventKit integration deferred to follow-up PR — Slice 11 ships a stub that always throws .notImplemented. Requires NSCalendarsFullAccessUsageDescription in Info.plist for iOS 17+.")

public struct EventKitCalendarClient: CalendarServiceClient, Sendable {
    private let preferences: CalendarPreferences?

    public init(preferences: CalendarPreferences? = nil) {
        self.preferences = preferences
    }

    public func fetchNextEvent() async throws -> CalendarServiceResponse? {
        throw CalendarServiceError.notImplemented
    }
}
#endif
