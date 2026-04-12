@preconcurrency import CoreBluetooth
import Foundation

/// Production ``BLECentralClient`` backed by CoreBluetooth.
///
/// Scans for the ScramScreen peripheral by its 128-bit service UUID,
/// connects, discovers characteristics, and bridges writes/notifications
/// to the ``BLECentralClient`` protocol used by the rest of the app.
public actor CoreBluetoothCentralClient: BLECentralClient {

    // MARK: - BLE UUIDs (must match firmware ble_server.c)

    private static let serviceUUID = CBUUID(string: "b6ca8101-b172-4d33-8518-8b1700235ed2")
    private static let screenDataUUID = CBUUID(string: "3aa9d5d0-1d70-4edf-b2cc-bf1d84dc545b")
    private static let controlUUID = CBUUID(string: "160c1f54-82ec-45e2-8339-1680f16c1a94")
    private static let statusUUID = CBUUID(string: "b7066d36-d896-4e74-9648-500df789d969")

    // MARK: - State

    private var state: ConnectionState = .idle
    /// Multiple consumers can each call `stateStream` and get their own
    /// independent copy. Each subscriber receives the current state
    /// immediately, then all subsequent changes.
    private var stateObservers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    private let statusContinuation: AsyncStream<Data>.Continuation
    private let _statusStream: AsyncStream<Data>

    private let delegate: Delegate
    /// Lazily created — AccessorySetupKit refuses to show its picker when
    /// a CBCentralManager with global permissions already exists.
    private var centralManager: CBCentralManager?

    /// Optional Bluetooth identifier from AccessorySetupKit pairing.
    /// When set, we reconnect by identifier instead of scanning.
    private var peripheralIdentifier: UUID?

    private var peripheral: CBPeripheral?
    private var screenDataChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    // MARK: - Init

    public init(peripheralIdentifier: UUID? = nil) {
        var statusCont: AsyncStream<Data>.Continuation!
        self._statusStream = AsyncStream { statusCont = $0 }
        self.statusContinuation = statusCont

        self.peripheralIdentifier = peripheralIdentifier
        self.delegate = Delegate()
    }

    /// Create the CBCentralManager on demand (first connect() call).
    private func ensureCentralManager() -> CBCentralManager {
        if let cm = centralManager { return cm }
        let cm = CBCentralManager(delegate: delegate, queue: delegate.queue)
        delegate.owner = self
        centralManager = cm
        return cm
    }

    /// Update the peripheral identifier (e.g. after AccessorySetupKit pairing).
    public func setPeripheralIdentifier(_ id: UUID?) {
        peripheralIdentifier = id
    }

    // MARK: - BLECentralClient conformance

    public nonisolated var stateStream: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            Task {
                await self.addObserver(continuation)
            }
        }
    }
    public nonisolated var statusStream: AsyncStream<Data> { _statusStream }

    private func addObserver(_ continuation: AsyncStream<ConnectionState>.Continuation) {
        let id = UUID()
        continuation.yield(state)
        stateObservers[id] = continuation
        continuation.onTermination = { _ in
            Task { await self.removeObserver(id) }
        }
    }

    private func removeObserver(_ id: UUID) {
        stateObservers.removeValue(forKey: id)
    }

    public func currentState() -> ConnectionState { state }

    public func connect() {
        guard state == .idle || state.isTerminal || {
            if case .disconnected = state { return true }
            return false
        }() else {
            print("[BLE] connect() ignored, state=\(state)")
            return
        }

        setState(.scanning)

        let cm = ensureCentralManager()
        print("[BLE] connect() called, cmState=\(cm.state.rawValue)")

        // Scan by service UUID. If CM isn't powered on yet,
        // handleCentralStateUpdate will start the scan.
        if cm.state == .poweredOn {
            print("[BLE] scanning for service UUID...")
            cm.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        } else {
            print("[BLE] CM not powered on yet (\(cm.state.rawValue)), will scan on poweredOn")
        }
    }

    public func send(_ bytes: Data) throws {
        guard case .connected = state, let peripheral, let screenDataChar else {
            print("[BLE] send() failed: not connected (state=\(state), periph=\(self.peripheral != nil), char=\(self.screenDataChar != nil))")
            throw BLECentralClientError.notConnected
        }
        print("[BLE] send \(bytes.count) bytes")
        peripheral.writeValue(bytes, for: screenDataChar, type: .withoutResponse)
    }

    public func disconnect() {
        centralManager?.stopScan()
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        cleanup()
        setState(.disconnected(reason: .userInitiated))
    }

    // MARK: - Internal

    private func setState(_ new: ConnectionState) {
        state = new
        for (_, cont) in stateObservers {
            cont.yield(new)
        }
    }

    private func cleanup() {
        peripheral = nil
        screenDataChar = nil
        controlChar = nil
        statusChar = nil
    }

    // MARK: - Delegate callbacks (called from Delegate on actor)

    fileprivate func handleCentralStateUpdate(_ central: CBCentralManager) {
        print("[BLE] centralState changed: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if case .scanning = state {
                print("[BLE] poweredOn while scanning, starting scan for service UUID")
                central.scanForPeripherals(
                    withServices: [Self.serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        case .poweredOff:
            cleanup()
            setState(.disconnected(reason: .bluetoothOff))
        case .unauthorized:
            cleanup()
            setState(.disconnected(reason: .unauthorized))
        default:
            break
        }
    }

    fileprivate func handleDiscovered(_ central: CBCentralManager, peripheral: CBPeripheral) {
        print("[BLE] discovered: \(peripheral.name ?? "?") id=\(peripheral.identifier)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = delegate
        setState(.connecting)
        central.connect(peripheral, options: nil)
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        print("[BLE] connected! discovering services...")
        peripheral.discoverServices([Self.serviceUUID])
    }

    fileprivate func handleDisconnected(_ error: (any Error)?) {
        print("[BLE] disconnected: \(error?.localizedDescription ?? "no error")")
        cleanup()
        setState(.disconnected(reason: .linkLost))
    }

    fileprivate func handleServicesDiscovered(_ peripheral: CBPeripheral) {
        print("[BLE] services discovered: \(peripheral.services?.map(\.uuid.uuidString) ?? [])")
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            return
        }
        // Discover ALL characteristics (passing nil) to avoid filtering issues.
        peripheral.discoverCharacteristics(nil, for: service)
    }

    fileprivate func handleCharacteristicsDiscovered(_ peripheral: CBPeripheral, service: CBService) {
        print("[BLE] characteristics: \(service.characteristics?.map(\.uuid.uuidString) ?? [])")
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case Self.screenDataUUID:
                screenDataChar = char
            case Self.controlUUID:
                controlChar = char
            case Self.statusUUID:
                statusChar = char
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }

        // Connected once we have the service — screen_data is for writing,
        // we can proceed even if characteristic discovery is partial.
        print("[BLE] screenData=\(screenDataChar != nil), control=\(controlChar != nil), status=\(statusChar != nil)")
        print("[BLE] >>> calling setState(.connected)")
        setState(.connected)
        print("[BLE] >>> setState(.connected) done")
    }

    fileprivate func handleNotification(_ data: Data) {
        statusContinuation.yield(data)
    }
}

// MARK: - CBCentralManager / CBPeripheral Delegate

/// NSObject delegate that forwards CoreBluetooth callbacks to the actor.
/// Must be a class (not actor) because CB delegates are called on a specific queue.
private final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.scramscreen.ble", qos: .userInitiated)
    weak var owner: CoreBluetoothCentralClient?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { await owner?.handleCentralStateUpdate(central) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        Task { await owner?.handleDiscovered(central, peripheral: peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { await owner?.handleConnected(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task { await owner?.handleDisconnected(error) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        Task { await owner?.handleDisconnected(error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else { return }
        Task { await owner?.handleServicesDiscovered(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else { return }
        Task { await owner?.handleCharacteristicsDiscovered(peripheral, service: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, let data = characteristic.value else { return }
        Task { await owner?.handleNotification(data) }
    }
}
