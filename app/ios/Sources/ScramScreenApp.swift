import BLECentralClient
import RideSimulatorKit
import SwiftUI

@main
struct ScramScreenApp: App {
    @State private var connection: ConnectionViewModel

    init() {
        let client = CoreBluetoothCentralClient()
        // swiftlint:disable:next force_try
        let clock = try! WallClock(speedMultiplier: 1)
        let coordinator = ReconnectCoordinator(client: client, clock: clock)
        _connection = State(initialValue: ConnectionViewModel(coordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(connection: connection)
        }
    }
}
