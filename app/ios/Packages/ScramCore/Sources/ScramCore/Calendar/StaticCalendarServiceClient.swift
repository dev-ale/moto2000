import Foundation
import RideSimulatorKit

/// Test-only ``CalendarServiceClient`` that returns a scripted response on
/// every call. Used by the Slice 11 test suite and by the dev-build UI when
/// running against a scenario file.
///
/// The response can be swapped at runtime via ``setResponse(_:)`` so tests
/// can simulate the upstream changing between refreshes.
public final class StaticCalendarServiceClient: CalendarServiceClient, @unchecked Sendable {
    private let lock = NSLock()
    private var currentResponse: CalendarServiceResponse?
    private var fetchCount: Int = 0

    public init(response: CalendarServiceResponse? = nil) {
        self.currentResponse = response
    }

    public var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetchCount
    }

    public func setResponse(_ response: CalendarServiceResponse?) {
        lock.lock()
        currentResponse = response
        lock.unlock()
    }

    public func fetchNextEvent() async throws -> CalendarServiceResponse? {
        return readAndIncrement()
    }

    private func readAndIncrement() -> CalendarServiceResponse? {
        lock.lock()
        fetchCount += 1
        let response = currentResponse
        lock.unlock()
        return response
    }
}
