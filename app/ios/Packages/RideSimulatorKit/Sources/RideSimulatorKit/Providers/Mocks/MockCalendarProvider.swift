import Foundation

public final class MockCalendarProvider: CalendarProvider, @unchecked Sendable {
    private let channel = ProviderChannel<CalendarEvent>()
    public let events: AsyncStream<CalendarEvent>

    public init() {
        self.events = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ event: CalendarEvent) { channel.emit(event) }
}
