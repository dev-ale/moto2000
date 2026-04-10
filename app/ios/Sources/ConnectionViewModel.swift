import BLECentralClient
import Observation
import RideSimulatorKit
import SwiftUI

@Observable
@MainActor
final class ConnectionViewModel {
    private(set) var state: ConnectionState = .idle
    private(set) var healthLevel: ConnectionHealthLevel = .down

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
            guard let self else { return }
            for await newState in await self.coordinator.client.stateStream {
                guard !Task.isCancelled else { break }
                self.state = newState
                self.healthLevel = self.level(for: newState)

                switch newState {
                case .connected:
                    await self.coordinator.handle(.didConnect)
                case .disconnected(let reason):
                    await self.coordinator.handle(.didDisconnect(reason: reason))
                default:
                    break
                }
            }
        }
    }

    /// Show the AccessorySetupKit picker — Apple's native one-tap pairing UI.
    func showPicker() {
        accessoryManager.showPicker()
    }

    func connect() {
        if accessoryManager.isPaired {
            Task { await coordinator.handle(.startRequested) }
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
            return "Nicht gekoppelt"
        }
        switch state {
        case .idle:
            return "Nicht verbunden"
        case .scanning:
            return "Suche..."
        case .connecting:
            return "Verbinde..."
        case .connected:
            return "Verbunden"
        case .disconnected(let reason):
            switch reason {
            case .linkLost: return "Verbindung verloren"
            case .userInitiated: return "Getrennt"
            case .bluetoothOff: return "Bluetooth aus"
            case .unauthorized: return "Nicht autorisiert"
            case .unknown: return "Getrennt"
            }
        case .reconnecting(let attempt):
            return "Wiederverbinden (\(attempt))..."
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
