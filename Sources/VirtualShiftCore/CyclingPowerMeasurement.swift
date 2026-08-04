import Foundation

public enum CyclingPowerMeasurementError: Error, Equatable {
    case malformedData
}

public struct CyclingPowerMeasurement: Equatable, Sendable {
    public let powerWatts: Int
    public let cumulativeCrankRevolutions: UInt16?
    public let lastCrankEventTime: UInt16?

    public static func decode(_ data: Data) throws -> Self {
        var reader = ByteReader(data)
        let flags = try reader.readUInt16()
        let power = Int(Int16(bitPattern: try reader.readUInt16()))

        if flags & (1 << 0) != 0 { try reader.skip(1) }
        if flags & (1 << 2) != 0 { try reader.skip(2) }
        if flags & (1 << 4) != 0 { try reader.skip(6) }

        let crankRevolutions: UInt16?
        let crankEventTime: UInt16?
        if flags & (1 << 5) != 0 {
            crankRevolutions = try reader.readUInt16()
            crankEventTime = try reader.readUInt16()
        } else {
            crankRevolutions = nil
            crankEventTime = nil
        }

        if flags & (1 << 6) != 0 { try reader.skip(4) }
        if flags & (1 << 7) != 0 { try reader.skip(4) }
        if flags & (1 << 8) != 0 { try reader.skip(3) }
        if flags & (1 << 9) != 0 { try reader.skip(2) }
        if flags & (1 << 10) != 0 { try reader.skip(2) }
        if flags & (1 << 11) != 0 { try reader.skip(2) }

        return Self(
            powerWatts: power,
            cumulativeCrankRevolutions: crankRevolutions,
            lastCrankEventTime: crankEventTime
        )
    }
}

public struct CrankCadenceTracker: Sendable {
    private var previousRevolutions: UInt16?
    private var previousEventTime: UInt16?

    public init() {}

    public mutating func update(
        with measurement: CyclingPowerMeasurement
    ) -> Double? {
        guard let revolutions = measurement.cumulativeCrankRevolutions,
              let eventTime = measurement.lastCrankEventTime
        else {
            return nil
        }

        defer {
            previousRevolutions = revolutions
            previousEventTime = eventTime
        }

        guard let previousRevolutions, let previousEventTime else {
            return nil
        }

        let revolutionDelta = revolutions &- previousRevolutions
        let timeDelta = eventTime &- previousEventTime
        guard timeDelta > 0 else { return nil }

        return Double(revolutionDelta) * 60 * 1024 / Double(timeDelta)
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func readUInt16() throws -> UInt16 {
        guard index + 2 <= bytes.count else {
            throw CyclingPowerMeasurementError.malformedData
        }
        defer { index += 2 }
        return UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    mutating func skip(_ count: Int) throws {
        guard index + count <= bytes.count else {
            throw CyclingPowerMeasurementError.malformedData
        }
        index += count
    }
}
