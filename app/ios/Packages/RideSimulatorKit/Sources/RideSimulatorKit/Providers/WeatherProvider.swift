import Foundation

public enum WeatherCondition: String, Equatable, Sendable, Codable, CaseIterable {
    case clear
    case cloudy
    case rain
    case snow
    case fog
    case thunderstorm
}

public struct WeatherSnapshot: Equatable, Sendable, Codable {
    public var scenarioTime: Double
    public var condition: WeatherCondition
    public var temperatureCelsius: Double
    public var highCelsius: Double
    public var lowCelsius: Double
    public var locationName: String

    public init(
        scenarioTime: Double,
        condition: WeatherCondition,
        temperatureCelsius: Double,
        highCelsius: Double,
        lowCelsius: Double,
        locationName: String
    ) {
        self.scenarioTime = scenarioTime
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.locationName = locationName
    }
}

public protocol WeatherProvider: Sendable {
    var snapshots: AsyncStream<WeatherSnapshot> { get }
    func start() async
    func stop() async
}
