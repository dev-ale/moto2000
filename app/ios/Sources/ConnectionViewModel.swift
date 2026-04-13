import BLECentralClient
import Observation
import RideSimulatorKit
import ScramCore
import SwiftUI

@Observable
@MainActor
final class ConnectionViewModel {
    private(set) var state: ConnectionState = .idle
    private(set) var healthLevel: ConnectionHealthLevel = .down
    private(set) var firmwareVersion: FirmwareVersion?

    let accessoryManager: AccessoryManager
    private let coordinator: ReconnectCoordinator
    private var observeTask: Task<Void, Never>?

    init(coordinator: ReconnectCoordinator, accessoryManager: AccessoryManager = AccessoryManager()) {
        self.coordinator = coordinator
        self.accessoryManager = accessoryManager
    }

    func startObserving() {
        accessoryManager.activate()

        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            await self?.runStateLoop()
        }
        Task { [weak self] in
            await self?.runAutoConnectLoop()
        }
    }

    private func runStateLoop() async {
        for await newState in await coordinator.client.stateStream {
            guard !Task.isCancelled else { break }
            print("[VM] state: \(newState)")
            state = newState
            healthLevel = level(for: newState)
            await forwardToCoordinator(newState)
        }
    }

    private func forwardToCoordinator(_ newState: ConnectionState) async {
        switch newState {
        case .connected:
            await coordinator.handle(.didConnect)
        case .disconnected(let reason):
            await coordinator.handle(.didDisconnect(reason: reason))
        default:
            break
        }
    }

    /* Auto-connect loop: every 2 seconds, if the device is paired and the
     * connection is idle/disconnected (not actively connecting), call
     * connect(). Handles both first-launch (AccessoryManager needs a
     * moment to surface its stored accessory) and transient drops. */
    private func runAutoConnectLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard accessoryManager.isPaired else { continue }
            if shouldAutoConnect(for: state) {
                connect()
            }
        }
    }

    private func shouldAutoConnect(for state: ConnectionState) -> Bool {
        switch state {
        case .idle:
            return true
        case .disconnected(let reason):
            return reason != .userInitiated
        default:
            return false
        }
    }

    /// Show the AccessorySetupKit picker — Apple's native one-tap pairing UI.
    func showPicker() {
        accessoryManager.showPicker()
    }

    func connect() {
        if accessoryManager.isPaired {
            // Pass the AccessorySetupKit Bluetooth identifier to the client
            // so it can reconnect by UUID instead of scanning.
            if let bleID = accessoryManager.bluetoothIdentifier {
                Task {
                    await coordinator.client.setPeripheralIdentifier(bleID)
                    await coordinator.handle(.startRequested)
                }
            } else {
                Task { await coordinator.handle(.startRequested) }
            }
        } else {
            showPicker()
        }
    }

    func disconnect() {
        Task { await coordinator.client.disconnect() }
    }

    func unpair() {
        accessoryManager.removeAccessory()
        Task { await coordinator.client.disconnect() }
    }

    var isConnected: Bool {
        state.canWrite
    }

    var isPaired: Bool {
        accessoryManager.isPaired
    }

    var statusText: String {
        if !isPaired {
            return "Not paired"
        }
        switch state {
        case .idle:
            return "Not connected"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .disconnected(let reason):
            switch reason {
            case .linkLost: return "Connection lost"
            case .userInitiated: return "Disconnected"
            case .bluetoothOff: return "Bluetooth off"
            case .unauthorized: return "Not authorized"
            case .unknown: return "Disconnected"
            }
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))..."
        }
    }

    var statusIcon: String {
        if !isPaired {
            return "antenna.radiowaves.left.and.right.slash"
        }
        switch healthLevel {
        case .good: return "antenna.radiowaves.left.and.right"
        case .degraded: return "antenna.radiowaves.left.and.right"
        case .down: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var statusColor: Color {
        if !isPaired { return .scramRed }
        switch healthLevel {
        case .good: return .scramGreen
        case .degraded: return .scramAmber
        case .down: return .scramRed
        }
    }

    private func level(for state: ConnectionState) -> ConnectionHealthLevel {
        switch state {
        case .connected: return .good
        case .scanning, .connecting, .reconnecting: return .degraded
        case .idle, .disconnected: return .down
        }
    }
}
