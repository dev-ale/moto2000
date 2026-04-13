import BLECentralClient
import RideSimulatorKit
import SwiftUI

struct RootView: View {
    @State var connection: ConnectionViewModel
    let rideCoordinator: RideSessionCoordinator

    var body: some View {
        MainTabView(connection: connection, rideCoordinator: rideCoordinator)
    }
}

#Preview {
    let client = CoreBluetoothCentralClient()
    // swiftlint:disable:next force_try
    let clock = try! WallClock(speedMultiplier: 1)
    return RootView(
        connection: ConnectionViewModel(
            coordinator: ReconnectCoordinator(client: client, clock: clock)
        ),
        rideCoordinator: RideSessionCoordinator(bleClient: client)
    )
}
