import Foundation

public struct IndoorBikeSimulationParameters: Equatable, Sendable {
    public let windSpeedThousandthsMetersPerSecond: Int16
    public let gradeHundredthsPercent: Int16
    public let rollingResistanceCoefficientTenThousandths: UInt8
    public let windResistanceCoefficientHundredthsKilogramsPerMeter: UInt8

    public init(
        windSpeedThousandthsMetersPerSecond: Int16,
        gradeHundredthsPercent: Int16,
        rollingResistanceCoefficientTenThousandths: UInt8,
        windResistanceCoefficientHundredthsKilogramsPerMeter: UInt8
    ) {
        self.windSpeedThousandthsMetersPerSecond =
            windSpeedThousandthsMetersPerSecond
        self.gradeHundredthsPercent = gradeHundredthsPercent
        self.rollingResistanceCoefficientTenThousandths =
            rollingResistanceCoefficientTenThousandths
        self.windResistanceCoefficientHundredthsKilogramsPerMeter =
            windResistanceCoefficientHundredthsKilogramsPerMeter
    }
}

public enum FTMSStopOrPause: UInt8, Equatable, Sendable {
    case stop = 1
    case pause = 2
}

public enum FitnessMachineControlPointRequest: Equatable, Sendable {
    case requestControl
    case reset
    case setTargetResistanceLevel(tenths: Int16)
    case setTargetPower(watts: Int16)
    case startOrResume
    case stopOrPause(FTMSStopOrPause)
    case setIndoorBikeSimulationParameters(IndoorBikeSimulationParameters)
    case setWheelCircumference(tenthsOfMillimeter: UInt16)

    public var opcode: UInt8 {
        switch self {
        case .requestControl: 0x00
        case .reset: 0x01
        case .setTargetResistanceLevel: 0x04
        case .setTargetPower: 0x05
        case .startOrResume: 0x07
        case .stopOrPause: 0x08
        case .setIndoorBikeSimulationParameters: 0x11
        case .setWheelCircumference: 0x12
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        var reader = FTMSByteReader(data)
        let opcode = try reader.readUInt8()
        let request: Self
        switch opcode {
        case 0x00:
            request = .requestControl
        case 0x01:
            request = .reset
        case 0x04:
            request = .setTargetResistanceLevel(tenths: try reader.readInt16())
        case 0x05:
            request = .setTargetPower(watts: try reader.readInt16())
        case 0x07:
            request = .startOrResume
        case 0x08:
            let rawValue = try reader.readUInt8()
            guard let action = FTMSStopOrPause(rawValue: rawValue) else {
                throw FTMSCodecError.invalidParameter("stop or pause")
            }
            request = .stopOrPause(action)
        case 0x11:
            request = .setIndoorBikeSimulationParameters(
                .init(
                    windSpeedThousandthsMetersPerSecond: try reader.readInt16(),
                    gradeHundredthsPercent: try reader.readInt16(),
                    rollingResistanceCoefficientTenThousandths:
                        try reader.readUInt8(),
                    windResistanceCoefficientHundredthsKilogramsPerMeter:
                        try reader.readUInt8()
                )
            )
        case 0x12:
            let circumference = try reader.readUInt16()
            guard circumference > 0 else {
                throw FTMSCodecError.invalidParameter("wheel circumference")
            }
            request = .setWheelCircumference(
                tenthsOfMillimeter: circumference
            )
        default:
            throw FTMSCodecError.unsupportedOpcode(opcode)
        }
        try reader.requireEnd()
        return request
    }

    public func encode() throws -> Data {
        var writer = FTMSByteWriter()
        writer.write(opcode)
        switch self {
        case .requestControl, .reset, .startOrResume:
            break
        case let .setTargetResistanceLevel(tenths):
            writer.write(tenths)
        case let .setTargetPower(watts):
            writer.write(watts)
        case let .stopOrPause(action):
            writer.write(action.rawValue)
        case let .setIndoorBikeSimulationParameters(parameters):
            writer.write(parameters.windSpeedThousandthsMetersPerSecond)
            writer.write(parameters.gradeHundredthsPercent)
            writer.write(parameters.rollingResistanceCoefficientTenThousandths)
            writer.write(
                parameters.windResistanceCoefficientHundredthsKilogramsPerMeter
            )
        case let .setWheelCircumference(circumference):
            guard circumference > 0 else {
                throw FTMSCodecError.invalidParameter("wheel circumference")
            }
            writer.write(circumference)
        }
        return writer.data
    }
}

public enum FTMSControlPointResult: UInt8, Equatable, Sendable {
    case success = 1
    case opcodeNotSupported = 2
    case invalidParameter = 3
    case operationFailed = 4
    case controlNotPermitted = 5
}

public struct FitnessMachineControlPointResponse: Equatable, Sendable {
    public let requestOpcode: UInt8
    public let result: FTMSControlPointResult

    public init(requestOpcode: UInt8, result: FTMSControlPointResult) {
        self.requestOpcode = requestOpcode
        self.result = result
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count == 3 else {
            throw FTMSCodecError.unexpectedLength(expected: 3, actual: data.count)
        }
        var reader = FTMSByteReader(data)
        guard try reader.readUInt8() == 0x80 else {
            throw FTMSCodecError.invalidParameter("response opcode")
        }
        let requestOpcode = try reader.readUInt8()
        guard let result = FTMSControlPointResult(
            rawValue: try reader.readUInt8()
        ) else {
            throw FTMSCodecError.invalidParameter("response result")
        }
        return Self(requestOpcode: requestOpcode, result: result)
    }

    public func encode() -> Data {
        Data([0x80, requestOpcode, result.rawValue])
    }
}
