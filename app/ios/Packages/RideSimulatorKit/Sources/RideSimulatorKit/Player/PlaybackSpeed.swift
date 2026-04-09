import Foundation

/// How fast the wall clock should advance relative to scenario time.
///
/// Used only by ``WallClock`` — tests that drive a ``VirtualClock`` do not
/// consult this value since they advance the clock manually.
public enum PlaybackSpeed: Double, Equatable, Sendable, CaseIterable {
    case realtime = 1
    case fast = 5
    case veryFast = 10
    case veryVeryFast = 60

    public var label: String {
        switch self {
        case .realtime: return "1×"
        case .fast: return "5×"
        case .veryFast: return "10×"
        case .veryVeryFast: return "60×"
        }
    }
}
