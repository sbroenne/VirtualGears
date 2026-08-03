import Foundation

public struct IndoorBikeData: Equatable, Sendable {
    public let instantaneousSpeedHundredths: UInt16?
    public let instantaneousCadenceHalfRPM: UInt16?
    public let resistanceLevel: Int16?
    public let instantaneousPowerWatts: Int16?
    public let heartRateBPM: UInt8?
    public let elapsedTimeSeconds: UInt16?

    private let encodedData: Data

    public var instantaneousSpeedKilometersPerHour: Double? {
        instantaneousSpeedHundredths.map { Double($0) / 100 }
    }

    public var instantaneousCadenceRPM: Double? {
        instantaneousCadenceHalfRPM.map { Double($0) / 2 }
    }

    public init(
        instantaneousSpeedHundredths: UInt16?,
        instantaneousCadenceHalfRPM: UInt16? = nil,
        resistanceLevel: Int16? = nil,
        instantaneousPowerWatts: Int16? = nil,
        heartRateBPM: UInt8? = nil,
        elapsedTimeSeconds: UInt16? = nil
    ) {
        self.instantaneousSpeedHundredths = instantaneousSpeedHundredths
        self.instantaneousCadenceHalfRPM = instantaneousCadenceHalfRPM
        self.resistanceLevel = resistanceLevel
        self.instantaneousPowerWatts = instantaneousPowerWatts
        self.heartRateBPM = heartRateBPM
        self.elapsedTimeSeconds = elapsedTimeSeconds

        var flags: UInt16 = instantaneousSpeedHundredths == nil ? 1 : 0
        if instantaneousCadenceHalfRPM != nil { flags |= 1 << 2 }
        if resistanceLevel != nil { flags |= 1 << 5 }
        if instantaneousPowerWatts != nil { flags |= 1 << 6 }
        if heartRateBPM != nil { flags |= 1 << 9 }
        if elapsedTimeSeconds != nil { flags |= 1 << 11 }

        var writer = FTMSByteWriter()
        writer.write(flags)
        if let value = instantaneousSpeedHundredths { writer.write(value) }
        if let value = instantaneousCadenceHalfRPM { writer.write(value) }
        if let value = resistanceLevel { writer.write(value) }
        if let value = instantaneousPowerWatts { writer.write(value) }
        if let value = heartRateBPM { writer.write(value) }
        if let value = elapsedTimeSeconds { writer.write(value) }
        encodedData = writer.data
    }

    private init(
        instantaneousSpeedHundredths: UInt16?,
        instantaneousCadenceHalfRPM: UInt16?,
        resistanceLevel: Int16?,
        instantaneousPowerWatts: Int16?,
        heartRateBPM: UInt8?,
        elapsedTimeSeconds: UInt16?,
        encodedData: Data
    ) {
        self.instantaneousSpeedHundredths = instantaneousSpeedHundredths
        self.instantaneousCadenceHalfRPM = instantaneousCadenceHalfRPM
        self.resistanceLevel = resistanceLevel
        self.instantaneousPowerWatts = instantaneousPowerWatts
        self.heartRateBPM = heartRateBPM
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.encodedData = encodedData
    }

    public static func decode(_ data: Data) throws -> Self {
        var reader = FTMSByteReader(data)
        let flags = try reader.readUInt16()
        let speed = flags & 1 == 0 ? try reader.readUInt16() : nil

        if flags & (1 << 1) != 0 { _ = try reader.readUInt16() }
        let cadence = flags & (1 << 2) != 0 ? try reader.readUInt16() : nil
        if flags & (1 << 3) != 0 { _ = try reader.readUInt16() }
        if flags & (1 << 4) != 0 { _ = try reader.readUInt24() }
        let resistance = flags & (1 << 5) != 0 ? try reader.readInt16() : nil
        let power = flags & (1 << 6) != 0 ? try reader.readInt16() : nil
        if flags & (1 << 7) != 0 { _ = try reader.readInt16() }
        if flags & (1 << 8) != 0 { _ = try reader.readData(count: 5) }
        let heartRate = flags & (1 << 9) != 0 ? try reader.readUInt8() : nil
        if flags & (1 << 10) != 0 { _ = try reader.readUInt8() }
        let elapsed = flags & (1 << 11) != 0 ? try reader.readUInt16() : nil
        if flags & (1 << 12) != 0 { _ = try reader.readUInt16() }
        try reader.requireEnd()

        return Self(
            instantaneousSpeedHundredths: speed,
            instantaneousCadenceHalfRPM: cadence,
            resistanceLevel: resistance,
            instantaneousPowerWatts: power,
            heartRateBPM: heartRate,
            elapsedTimeSeconds: elapsed,
            encodedData: data
        )
    }

    public func encode() -> Data {
        encodedData
    }
}
