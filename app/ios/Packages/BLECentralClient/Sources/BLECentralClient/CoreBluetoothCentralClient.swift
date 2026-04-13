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
    private static let otaDataUUID = CBUUID(string: "c8e9f3a4-1b2c-4d5e-9f8a-6b7c8d9e0f1a")

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
    private var otaDataChar: CBCharacteristic?

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
        /* Use a restore identifier so iOS keeps the CBCentralManager
         * state (including active connections) across app launches.
         * This is what makes retrieveConnectedPeripherals actually find
         * the existing system-held connection on app relaunch. */
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: "com.alejandro.moto2000.ScramScreen.central",
        ]
        let cm = CBCentralManager(delegate: delegate, queue: delegate.queue, options: options)
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

        let cm = ensureCentralManager()
        print("[BLE] connect() called, cmState=\(cm.state.rawValue)")

        guard cm.state == .poweredOn else {
            /* Don't claim "scanning" — Bluetooth is off or unauthorized.
             * Reflect the real reason so the UI doesn't lie. The
             * powered-on transition will retry via handleCentralStateUpdate. */
            print("[BLE] CM not powered on yet (\(cm.state.rawValue))")
            switch cm.state {
            case .poweredOff:
                setState(.disconnected(reason: .bluetoothOff))
            case .unauthorized:
                setState(.disconnected(reason: .unauthorized))
            default:
                setState(.disconnected(reason: .unknown))
            }
            return
        }

        // FAST PATH #1: system already has a live connection from a
        // previous app session. Reuse it — no scan, no pairing.
        let connected = cm.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        if let existing = connected.first {
            print("[BLE] reusing already-connected peripheral \(existing.identifier)")
            self.peripheral = existing
            existing.delegate = delegate
            setState(.connecting)
            cm.connect(existing, options: nil)
            return
        }

        // FAST PATH #2: we know the peripheral identifier from
        // AccessorySetupKit. Queue a *pending* connect that iOS
        // resolves whenever the peripheral comes back into range —
        // even if our app is force-quit. This is the **only** way
        // background autoreconnect works.
        if let peripheralIdentifier,
           let known = cm.retrievePeripherals(withIdentifiers: [peripheralIdentifier]).first {
            print("[BLE] queueing pending connect to \(known.identifier)")
            self.peripheral = known
            known.delegate = delegate
            setState(.connecting)
            cm.connect(known, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            ])
            return
        }

        // Last resort: active scan. Used for the very first pairing
        // before AccessorySetupKit has produced an identifier.
        print("[BLE] scanning for service UUID...")
        setState(.scanning)
        cm.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func send(_ bytes: Data) throws {
        guard case .connected = state, let peripheral, let screenDataChar else {
            print("[BLE] send() failed: not connected (state=\(state), periph=\(self.peripheral != nil), char=\(self.screenDataChar != nil))")
            throw BLECentralClientError.notConnected
        }
        print("[BLE] send \(bytes.count) bytes")
        peripheral.writeValue(bytes, for: screenDataChar, type: .withoutResponse)
    }

    public func sendControl(_ bytes: Data) throws {
        guard case .connected = state, let peripheral, let controlChar else {
            print("[BLE] sendControl() failed: not connected or no control char")
            throw BLECentralClientError.notConnected
        }
        print("[BLE] sendControl \(bytes.count) bytes")
        peripheral.writeValue(bytes, for: controlChar, type: .withResponse)
    }

    public func sendOTA(_ bytes: Data) throws {
        guard case .connected = state, let peripheral, let otaDataChar else {
            throw BLECentralClientError.notConnected
        }
        // write-without-response. Caller MUST throttle (OTAUploader
        // sleeps a few ms per chunk) — otherwise iOS pushes faster
        // than the NimBLE ACL buffer pool can drain and the firmware
        // logs "ACL buf alloc failed" until the link dies.
        peripheral.writeValue(bytes, for: otaDataChar, type: .withoutResponse)
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
        otaDataChar = nil
    }

    // MARK: - Delegate callbacks (called from Delegate on actor)

    fileprivate func handleCentralStateUpdate(_ central: CBCentralManager) {
        print("[BLE] centralState changed: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            // Whenever Bluetooth comes up (cold start, BT toggle on,
            // background relaunch) — kick off the autoconnect flow if
            // the link isn't already up.
            if case .connected = state { return }
            if case .connecting = state { return }
            // Try system-held connection, then pending connect by
            // identifier, then scan. Same precedence as connect().
            let connected = central.retrieveConnectedPeripherals(
                withServices: [Self.serviceUUID])
            if let existing = connected.first {
                print("[BLE] poweredOn: reusing system-connected peripheral \(existing.identifier)")
                self.peripheral = existing
                existing.delegate = delegate
                setState(.connecting)
                central.connect(existing, options: nil)
                return
            }
            if let peripheralIdentifier,
               let known = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier]).first {
                print("[BLE] poweredOn: queueing pending connect to \(known.identifier)")
                self.peripheral = known
                known.delegate = delegate
                setState(.connecting)
                central.connect(known, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                ])
                return
            }
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
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true])

        /* Bail out after 15 s if the connection hasn't succeeded —
         * SMP re-encryption after firmware reboot can take several
         * seconds; a too-aggressive timeout cancels mid-handshake. */
        let cancelHandle = peripheral
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            guard let self else { return }
            if case .connecting = await self.currentState() {
                print("[BLE] connect timeout — cancelling and re-scanning")
                await self.cancelStaleConnect(cancelHandle)
            }
        }
    }

    fileprivate func cancelStaleConnect(_ peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
        self.peripheral = nil
        setState(.idle)
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        print("[BLE] connected! discovering services...")
        peripheral.discoverServices([Self.serviceUUID])
    }

    fileprivate func handleDisconnected(_ error: (any Error)?) {
        print("[BLE] disconnected: \(error?.localizedDescription ?? "no error")")
        cleanup()
        /* Preserve a user-initiated disconnect — otherwise the auto-connect
         * loop would immediately reconnect because .linkLost is recoverable. */
        if case .disconnected(.userInitiated) = state {
            return
        }
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
            case Self.otaDataUUID:
                otaDataChar = char
            default:
                break
            }
        }

        // Connected once we have the service — screen_data is for writing,
        // we can proceed even if characteristic discovery is partial.
        print("[BLE] screenData=\(screenDataChar != nil), control=\(controlChar != nil), status=\(statusChar != nil), ota=\(otaDataChar != nil)")
        print("[BLE] >>> calling setState(.connected)")
        setState(.connected)
        print("[BLE] >>> setState(.connected) done")
    }

    fileprivate func handleNotification(_ data: Data) {
        statusContinuation.yield(data)
    }

    fileprivate func handleRestoredPeripheral(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = delegate
        switch peripheral.state {
        case .connected:
            print("[BLE] restored: already connected, discovering services")
            setState(.connecting)
            peripheral.discoverServices([Self.serviceUUID])
        case .connecting:
            print("[BLE] restored: still connecting")
            setState(.connecting)
        default:
            break
        }
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

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        /* iOS restored our CBCentralManager state — pick up any
         * peripherals we were connected/connecting to in the previous
         * session and re-attach delegates. The actual reconnect happens
         * in handleCentralStateUpdate when we detect powered-on state. */
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let first = peripherals.first {
            print("[BLE] willRestoreState: restored peripheral \(first.identifier), state=\(first.state.rawValue)")
            Task { await owner?.handleRestoredPeripheral(first) }
        }
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
