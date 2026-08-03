import Foundation

public enum FTMSCodecError: Error, Equatable, Sendable {
    case insufficientBytes(offset: Int, expected: Int, available: Int)
    case unexpectedLength(expected: Int, actual: Int)
    case unsupportedOpcode(UInt8)
    case invalidParameter(String)
}

public struct FTMSByteReader: Sendable {
    private let bytes: [UInt8]
    public private(set) var offset = 0

    public init(_ data: Data) {
        bytes = Array(data)
    }

    public var remainingCount: Int {
        bytes.count - offset
    }

    public mutating func readUInt8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func readUInt16() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    public mutating func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    public mutating func readUInt24() throws -> UInt32 {
        try require(3)
        defer { offset += 3 }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
    }

    public mutating func readData(count: Int) throws -> Data {
        try require(count)
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }

    public func requireEnd() throws {
        guard remainingCount == 0 else {
            throw FTMSCodecError.unexpectedLength(
                expected: offset,
                actual: bytes.count
            )
        }
    }

    private func require(_ count: Int) throws {
        guard count >= 0, remainingCount >= count else {
            throw FTMSCodecError.insufficientBytes(
                offset: offset,
                expected: max(count, 0),
                available: remainingCount
            )
        }
    }
}

public struct FTMSByteWriter: Sendable {
    private var bytes: [UInt8] = []

    public init() {}

    public mutating func write(_ value: UInt8) {
        bytes.append(value)
    }

    public mutating func write(_ value: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    public mutating func write(_ value: Int16) {
        write(UInt16(bitPattern: value))
    }

    public mutating func writeUInt24(_ value: UInt32) throws {
        guard value <= 0x00FF_FFFF else {
            throw FTMSCodecError.invalidParameter("UInt24")
        }
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    }

    public mutating func write(_ data: Data) {
        bytes.append(contentsOf: data)
    }

    public var data: Data {
        Data(bytes)
    }
}
