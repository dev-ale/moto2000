import Foundation
import RideSimulatorKit

/*
 * WeatherKitClient — intentional stub (Slice 7).
 *
 * Real WeatherKit access from a Swift-only package is gated on two things
 * that are out of scope for Slice 7:
 *
 *   1. An Apple Developer account with the WeatherKit capability enabled
 *      on the app identifier. This is an App Store Connect change that
 *      has to be made by a human with signing authority on the project.
 *
 *   2. A signed .p8 key and JWT minting so the REST endpoint authorizes
 *      requests. `import WeatherKit` from a Swift package (vs. an app
 *      target) is also limited; the REST client path is the documented
 *      replacement.
 *
 * Rather than ship a half-working integration that needs a runtime secret
 * to even compile on CI, Slice 7 ships a stub that throws
 * `WeatherServiceError.notImplemented`. The `RealWeatherProvider` below
 * swallows the error and keeps polling, so the rest of the system is
 * unaffected. A follow-up PR will swap this file for a real REST client
 * without touching `WeatherServiceClient`, `RealWeatherProvider`, or the
 * renderer.
 *
 * The type is gated on `canImport(WeatherKit)` so the stub compiles on
 * Linux CI without pulling in the framework.
 */
#if canImport(WeatherKit)
#warning("WeatherKit integration deferred to follow-up PR — Slice 7 ships a stub that always throws .notImplemented")

public struct WeatherKitClient: WeatherServiceClient, Sendable {
    public init() {}

    public func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherServiceResponse {
        throw WeatherServiceError.notImplemented
    }
}
#endif
