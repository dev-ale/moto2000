import Foundation

/// A cursor that reads little-endian fixed-width values from a `Data` buffer.
///
/// Every read advances the cursor. If the buffer is exhausted the reader
/// throws ``BLEProtocolError/truncatedBody(declared:available:)`` or
/// ``BLEProtocolError/truncatedHeader`` depending on the caller.
struct ByteReader {
    let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        guard remaining >= 1 else { throw BLEProtocolError.truncatedHeader }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        guard remaining >= 2 else { throw BLEProtocolError.truncatedHeader }
        defer { offset += 2 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    mutating func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    mutating func readUInt32() throws -> UInt32 {
        guard remaining >= 4 else { throw BLEProtocolError.truncatedBody(declared: 4, available: remaining) }
        defer { offset += 4 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readUInt64() throws -> UInt64 {
        guard remaining >= 8 else { throw BLEProtocolError.truncatedBody(declared: 8, available: remaining) }
        defer { offset += 8 }
        var value: UInt64 = 0
        let base = data.startIndex + offset
        for i in 0..<8 {
            value |= UInt64(data[base + i]) << (8 * i)
        }
        return value
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard remaining >= count else {
            throw BLEProtocolError.truncatedBody(declared: count, available: remaining)
        }
        defer { offset += count }
        let base = data.startIndex + offset
        return data.subdata(in: base..<(base + count))
    }

    mutating func readFixedString(length: Int) throws -> String {
        let raw = try readBytes(length)
        guard let terminatorIndex = raw.firstIndex(of: 0) else {
            throw BLEProtocolError.unterminatedString
        }
        let stringBytes = raw.prefix(upTo: terminatorIndex)
        return String(decoding: stringBytes, as: UTF8.self)
    }
}
