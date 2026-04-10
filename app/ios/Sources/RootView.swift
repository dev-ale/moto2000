import BLECentralClient
import RideSimulatorKit
import SwiftUI

struct RootView: View {
    @State var connection: ConnectionViewModel

    var body: some View {
        MainTabView(connection: connection)
    }
}

#Preview {
    RootView(
        connection: ConnectionViewModel(
            coordinator: ReconnectCoordinator(
                client: CoreBluetoothCentralClient(),
                // swiftlint:disable:next force_try
                clock: try! WallClock(speedMultiplier: 1)
            )
        )
    )
}
