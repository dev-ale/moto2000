import Foundation

/// Decoded body for an `incomingCall` screen payload.
///
/// Layout (little-endian, 32 bytes total):
/// ```
/// offset 0     : uint8   call_state               0x00=incoming, 0x01=connected, 0x02=ended
/// offset 1     : uint8   reserved                 must be 0
/// offset 2..31 : char[30] caller_handle            UTF-8, null-terminated
/// ```
///
/// The `ALERT` header flag should be set for `incoming` and `connected`
/// states, and cleared for `ended`. This signals the ESP32 screen FSM to
/// treat the payload as a priority overlay.
///
/// Matches `ble_incoming_call_data_t` in the C codec.
public struct IncomingCallData: Equatable, Sendable {
    public static let encodedSize: Int = 32
    public static let callerHandleFieldLength: Int = 30

    public enum CallStateWire: UInt8, Equatable, Sendable {
        case incoming  = 0x00
        case connected = 0x01
        case ended     = 0x02
    }

    public var callState: CallStateWire
    public var callerHandle: String

    public init(callState: CallStateWire, callerHandle: String) {
        self.callState = callState
        self.callerHandle = callerHandle
    }

    /// Whether the ALERT header flag should be set for this call state.
    public var shouldSetAlertFlag: Bool {
        switch callState {
        case .incoming, .connected:
            return true
        case .ended:
            return false
        }
    }

    /// Recommended header flags for this payload.
    public var recommendedFlags: ScreenFlags {
        shouldSetAlertFlag ? [.alert] : []
    }

    static func decode(_ body: Data) throws -> IncomingCallData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .incomingCall,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let stateRaw = try reader.readUInt8()
        guard let callState = CallStateWire(rawValue: stateRaw) else {
            throw BLEProtocolError.valueOutOfRange(field: "call.call_state")
        }
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "call.reserved")
        }
        let callerHandle = try reader.readFixedString(length: Self.callerHandleFieldLength)

        return IncomingCallData(
            callState: callState,
            callerHandle: callerHandle
        )
    }

    func encode() throws -> Data {
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(callState.rawValue)
        writer.writeUInt8(0) // reserved
        try writer.writeFixedString(callerHandle, length: Self.callerHandleFieldLength)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
