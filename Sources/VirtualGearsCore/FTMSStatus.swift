import Foundation

public enum FitnessMachineStatus: Equatable, Sendable {
    case reset
    case stoppedOrPaused(FTMSStopOrPause)
    case startedOrResumed
    case targetPowerChanged(watts: Int16)
    case targetResistanceLevelChanged(tenths: Int16)
    case indoorBikeSimulationParametersChanged(IndoorBikeSimulationParameters)
    case wheelCircumferenceChanged(tenthsOfMillimeter: UInt16)
    case controlPermissionLost

    public static func decode(_ data: Data) throws -> Self {
        var reader = FTMSByteReader(data)
        let opcode = try reader.readUInt8()
        let status: Self
        switch opcode {
        case 0x01:
            status = .reset
        case 0x02:
            let rawValue = try reader.readUInt8()
            guard let action = FTMSStopOrPause(rawValue: rawValue) else {
                throw FTMSCodecError.invalidParameter("stopped or paused")
            }
            status = .stoppedOrPaused(action)
        case 0x04:
            status = .startedOrResumed
        case 0x07:
            status = .targetResistanceLevelChanged(tenths: try reader.readInt16())
        case 0x08:
            status = .targetPowerChanged(watts: try reader.readInt16())
        case 0x12:
            status = .indoorBikeSimulationParametersChanged(
                .init(
                    windSpeedThousandthsMetersPerSecond: try reader.readInt16(),
                    gradeHundredthsPercent: try reader.readInt16(),
                    rollingResistanceCoefficientTenThousandths:
                        try reader.readUInt8(),
                    windResistanceCoefficientHundredthsKilogramsPerMeter:
                        try reader.readUInt8()
                )
            )
        case 0x13:
            status = .wheelCircumferenceChanged(
                tenthsOfMillimeter: try reader.readUInt16()
            )
        case 0xFF:
            status = .controlPermissionLost
        default:
            throw FTMSCodecError.unsupportedOpcode(opcode)
        }
        try reader.requireEnd()
        return status
    }

    public func encode() -> Data {
        var writer = FTMSByteWriter()
        switch self {
        case .reset:
            writer.write(UInt8(0x01))
        case let .stoppedOrPaused(action):
            writer.write(UInt8(0x02))
            writer.write(action.rawValue)
        case .startedOrResumed:
            writer.write(UInt8(0x04))
        case let .targetPowerChanged(watts):
            writer.write(UInt8(0x08))
            writer.write(watts)
        case let .targetResistanceLevelChanged(tenths):
            writer.write(UInt8(0x07))
            writer.write(tenths)
        case let .indoorBikeSimulationParametersChanged(parameters):
            writer.write(UInt8(0x12))
            writer.write(parameters.windSpeedThousandthsMetersPerSecond)
            writer.write(parameters.gradeHundredthsPercent)
            writer.write(parameters.rollingResistanceCoefficientTenThousandths)
            writer.write(
                parameters.windResistanceCoefficientHundredthsKilogramsPerMeter
            )
        case let .wheelCircumferenceChanged(circumference):
            writer.write(UInt8(0x13))
            writer.write(circumference)
        case .controlPermissionLost:
            writer.write(UInt8(0xFF))
        }
        return writer.data
    }
}
