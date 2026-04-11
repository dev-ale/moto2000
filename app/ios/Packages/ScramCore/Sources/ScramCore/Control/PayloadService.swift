import Foundation

/// The uniform interface every dashboard service conforms to.
///
/// RideSession doesn't need to know what provider a service uses,
/// what data it transforms, or how it encodes — just that it
/// produces `Data` payloads and can be started/stopped.
public protocol PayloadService: AnyObject, Sendable {
    /// Encoded BLE payloads ready to write to the peripheral.
    /// Consumers drain this exactly once after calling ``start()``.
    var payloadStream: AsyncStream<Data> { get }

    /// Begin producing payloads. Idempotent.
    func start() async

    /// Stop producing and finish the payloads stream.
    func stop() async
}

/// Describes how to create a service from available dependencies.
///
/// The factory closure inspects ``RideSessionDependencies`` and returns
/// a configured service, or `nil` if the required providers are missing.
public struct ServiceRegistration: Sendable {
    /// Human-readable label for logging and debugging.
    public let name: String

    /// Attempt to build a service from the given dependencies.
    public let factory: @Sendable (RideSessionDependencies) -> (any PayloadService)?

    public init(
        name: String,
        factory: @escaping @Sendable (RideSessionDependencies) -> (any PayloadService)?
    ) {
        self.name = name
        self.factory = factory
    }
}

/// The declarative list of all dashboard services.
///
/// Adding a new service is one entry here — no RideSession changes needed.
public enum ServiceRegistry {
    public static let all: [ServiceRegistration] = [
        // Single-provider services
        ServiceRegistration(name: "speedHeading") { deps in
            deps.locationProvider.map { SpeedHeadingService(provider: $0) }
        },
        ServiceRegistration(name: "tripStats") { deps in
            deps.locationProvider.map { TripStatsService(provider: $0) }
        },
        ServiceRegistration(name: "weather") { deps in
            deps.weatherProvider.map { WeatherService(provider: $0) }
        },
        ServiceRegistration(name: "leanAngle") { deps in
            deps.motionProvider.map { LeanAngleService(provider: $0) }
        },
        ServiceRegistration(name: "music") { deps in
            deps.nowPlayingProvider.map { MusicService(provider: $0) }
        },
        ServiceRegistration(name: "calendar") { deps in
            deps.calendarProvider.map { CalendarService(provider: $0) }
        },
        ServiceRegistration(name: "callAlert") { deps in
            deps.callObserver.map { CallAlertService(observer: $0) }
        },
        ServiceRegistration(name: "altitude") { deps in
            deps.locationProvider.map { AltitudeService(provider: $0) }
        },

        // Multi-provider services
        ServiceRegistration(name: "fuel") { deps in
            guard let loc = deps.locationProvider,
                  let fuelLog = deps.fuelLog else { return nil }
            return FuelService(provider: loc, fuelLog: fuelLog, settings: deps.fuelSettings)
        },
        ServiceRegistration(name: "blitzerAlert") { deps in
            guard let loc = deps.locationProvider,
                  let db = deps.speedCameraDatabase else { return nil }
            return BlitzerAlertService(locationProvider: loc, database: db)
        },
    ]
}
