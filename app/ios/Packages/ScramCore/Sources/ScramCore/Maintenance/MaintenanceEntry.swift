import Foundation

/// A single maintenance log entry for the motorcycle.
public struct MaintenanceEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let type: MaintenanceType
    public let odometerKm: Double
    public let notes: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: MaintenanceType,
        odometerKm: Double,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.odometerKm = odometerKm
        self.notes = notes
    }
}

/// The kind of maintenance performed.
public enum MaintenanceType: String, Codable, CaseIterable, Sendable {
    case oilChange = "Oil Change"
    case chainLube = "Chain Lube"
    case chainReplace = "Chain Replace"
    case tires = "Tires"
    case brakes = "Brakes"
    case sparkPlugs = "Spark Plugs"
    case airFilter = "Air Filter"
    case general = "General Service"

    /// SF Symbol name for the maintenance type.
    public var iconName: String {
        switch self {
        case .oilChange: return "drop.fill"
        case .chainLube: return "link"
        case .chainReplace: return "link.badge.plus"
        case .tires: return "circle.circle"
        case .brakes: return "exclamationmark.octagon"
        case .sparkPlugs: return "bolt.fill"
        case .airFilter: return "wind"
        case .general: return "wrench.and.screwdriver"
        }
    }
}
