import Foundation

public enum FTMSUUID {
    public static let fitnessMachineService = "1826"
    public static let fitnessMachineFeature = "2ACC"
    public static let indoorBikeData = "2AD2"
    public static let supportedResistanceLevelRange = "2AD6"
    public static let supportedPowerRange = "2AD8"
    public static let fitnessMachineControlPoint = "2AD9"
    public static let fitnessMachineStatus = "2ADA"
}

public struct FTMSMachineFeatures: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let cadence = Self(rawValue: 1 << 1)
    public static let resistanceLevel = Self(rawValue: 1 << 7)
    public static let heartRateMeasurement = Self(rawValue: 1 << 10)
    public static let elapsedTime = Self(rawValue: 1 << 12)
    public static let powerMeasurement = Self(rawValue: 1 << 14)
}

public struct FTMSTargetSettingFeatures: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let resistanceLevel = Self(rawValue: 1 << 2)
    public static let power = Self(rawValue: 1 << 3)
    public static let indoorBikeSimulationParameters = Self(rawValue: 1 << 13)
    public static let wheelCircumference = Self(rawValue: 1 << 14)
}

public struct FitnessMachineFeature: Equatable, Sendable {
    public let machineFeatures: FTMSMachineFeatures
    public let targetSettingFeatures: FTMSTargetSettingFeatures

    public init(
        machineFeatures: FTMSMachineFeatures,
        targetSettingFeatures: FTMSTargetSettingFeatures
    ) {
        self.machineFeatures = machineFeatures
        self.targetSettingFeatures = targetSettingFeatures
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count == 8 else {
            throw FTMSCodecError.unexpectedLength(expected: 8, actual: data.count)
        }
        var reader = FTMSByteReader(data)
        let machineLow = UInt32(try reader.readUInt16())
        let machineHigh = UInt32(try reader.readUInt16()) << 16
        let targetLow = UInt32(try reader.readUInt16())
        let targetHigh = UInt32(try reader.readUInt16()) << 16
        return Self(
            machineFeatures: .init(rawValue: machineLow | machineHigh),
            targetSettingFeatures: .init(rawValue: targetLow | targetHigh)
        )
    }

    public func encode() -> Data {
        var writer = FTMSByteWriter()
        writer.write(UInt16(truncatingIfNeeded: machineFeatures.rawValue))
        writer.write(UInt16(truncatingIfNeeded: machineFeatures.rawValue >> 16))
        writer.write(UInt16(truncatingIfNeeded: targetSettingFeatures.rawValue))
        writer.write(UInt16(truncatingIfNeeded: targetSettingFeatures.rawValue >> 16))
        return writer.data
    }
}

public struct SupportedPowerRange: Equatable, Sendable {
    public let minimumWatts: Int16
    public let maximumWatts: Int16
    public let incrementWatts: UInt16

    public init(
        minimumWatts: Int16,
        maximumWatts: Int16,
        incrementWatts: UInt16
    ) throws {
        guard minimumWatts <= maximumWatts else {
            throw FTMSCodecError.invalidParameter("power range")
        }
        guard incrementWatts > 0 else {
            throw FTMSCodecError.invalidParameter("power increment")
        }
        self.minimumWatts = minimumWatts
        self.maximumWatts = maximumWatts
        self.incrementWatts = incrementWatts
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count == 6 else {
            throw FTMSCodecError.unexpectedLength(expected: 6, actual: data.count)
        }
        var reader = FTMSByteReader(data)
        return try Self(
            minimumWatts: reader.readInt16(),
            maximumWatts: reader.readInt16(),
            incrementWatts: reader.readUInt16()
        )
    }

    public func encode() -> Data {
        var writer = FTMSByteWriter()
        writer.write(minimumWatts)
        writer.write(maximumWatts)
        writer.write(incrementWatts)
        return writer.data
    }
}

public struct SupportedResistanceLevelRange: Equatable, Sendable {
    public let minimumTenths: Int16
    public let maximumTenths: Int16
    public let incrementTenths: UInt16

    public init(
        minimumTenths: Int16,
        maximumTenths: Int16,
        incrementTenths: UInt16
    ) throws {
        guard minimumTenths <= maximumTenths else {
            throw FTMSCodecError.invalidParameter("resistance range")
        }
        guard incrementTenths > 0 else {
            throw FTMSCodecError.invalidParameter("resistance increment")
        }
        self.minimumTenths = minimumTenths
        self.maximumTenths = maximumTenths
        self.incrementTenths = incrementTenths
    }

    public var minimum: Double { Double(minimumTenths) / 10 }
    public var maximum: Double { Double(maximumTenths) / 10 }
    public var increment: Double { Double(incrementTenths) / 10 }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count == 6 else {
            throw FTMSCodecError.unexpectedLength(expected: 6, actual: data.count)
        }
        var reader = FTMSByteReader(data)
        return try Self(
            minimumTenths: reader.readInt16(),
            maximumTenths: reader.readInt16(),
            incrementTenths: reader.readUInt16()
        )
    }

    public func encode() -> Data {
        var writer = FTMSByteWriter()
        writer.write(minimumTenths)
        writer.write(maximumTenths)
        writer.write(incrementTenths)
        return writer.data
    }
}
