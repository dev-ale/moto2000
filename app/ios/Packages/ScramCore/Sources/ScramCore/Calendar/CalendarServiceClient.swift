import Foundation
import RideSimulatorKit

/// Abstraction over "where does a next-appointment snapshot come from".
///
/// Slice 11 injects either the test-only ``StaticCalendarServiceClient`` or
/// the ``EventKitCalendarClient`` stub. A follow-up slice will provide a real
/// EventKit implementation; see ``EventKitCalendarClient`` for why the
/// integration is deferred.
public protocol CalendarServiceClient: Sendable {
    /// Fetch the next upcoming calendar event.
    ///
    /// Returns `nil` if no events are found within the look-ahead window.
    func fetchNextEvent() async throws -> CalendarServiceResponse?
}

/// Raw response from a ``CalendarServiceClient``.
///
/// The shape mirrors the fields needed for ``AppointmentData`` minus the
/// scenario time, so a ``RealCalendarProvider`` can stamp its own clock
/// value when it emits downstream.
public struct CalendarServiceResponse: Sendable, Equatable {
    public var title: String
    public var startsInSeconds: Double
    public var location: String

    public init(
        title: String,
        startsInSeconds: Double,
        location: String
    ) {
        self.title = title
        self.startsInSeconds = startsInSeconds
        self.location = location
    }
}

/// Errors a ``CalendarServiceClient`` can throw.
public enum CalendarServiceError: Error, Sendable, Equatable {
    /// The client is a stub and cannot actually fetch calendar events.
    /// Thrown exclusively by ``EventKitCalendarClient`` in Slice 11.
    case notImplemented
    /// Calendar access was denied by the user.
    case accessDenied
    /// An unexpected failure occurred.
    case internalError(String)
}
