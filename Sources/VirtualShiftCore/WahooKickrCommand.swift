import Foundation

public enum WahooKickrCommandError: Error, Equatable {
    case invalidWheelCircumference(Double)
}

public enum WahooKickrResponseError: Error, Equatable {
    case malformedData
    case unsupportedCommand(UInt8)
}

public enum WahooKickrResponse: Equatable, Sendable {
    case unlock(result: UInt8)
    case wheelCircumference(result: UInt16, encodedTenthsOfMillimeter: UInt16)

    public static func decode(_ data: Data) throws -> Self {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0x01 else {
            throw WahooKickrResponseError.malformedData
        }

        switch bytes[1] {
        case 0x20:
            return .unlock(result: bytes[2])
        case 0x48:
            guard bytes.count >= 6 else {
                throw WahooKickrResponseError.malformedData
            }
            let result = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
            let encoded = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
            return .wheelCircumference(
                result: result,
                encodedTenthsOfMillimeter: encoded
            )
        default:
            throw WahooKickrResponseError.unsupportedCommand(bytes[1])
        }
    }

    public func verifies(command: Data) -> Bool {
        let bytes = Array(command)
        switch self {
        case .unlock:
            return command == WahooKickrCommand.unlock
        case let .wheelCircumference(_, encoded):
            guard bytes.count == 3, bytes[0] == 0x48 else { return false }
            return bytes[1] == UInt8(encoded & 0x00FF)
                && bytes[2] == UInt8(encoded >> 8)
        }
    }

    public var summary: String {
        switch self {
        case let .unlock(result):
            "unlock result 0x\(String(format: "%02X", result))"
        case let .wheelCircumference(result, encoded):
            "wheel circumference \(Double(encoded) / 10) mm, "
                + "result 0x\(String(format: "%04X", result))"
        }
    }
}

public enum WahooKickrProtocol {
    public static let cyclingPowerServiceUUID = "1818"
    public static let cyclingPowerMeasurementUUID = "2A63"
    public static let controlCharacteristicUUID =
        "A026E005-0A7D-4AB3-97FA-F1500F9FEB8B"
}

public enum WahooKickrProofSelection: CaseIterable, Sendable {
    case easier
    case baseline
    case harder

    public var label: String {
        switch self {
        case .easier:
            "Easier"
        case .baseline:
            "Starting value"
        case .harder:
            "Harder"
        }
    }
}

public enum WahooKickrProofValuesError: Error, Equatable {
    case invalidBaseline(Double)
    case invalidTestOffset(Double)
}

public struct WahooKickrProofValues: Equatable, Sendable {
    public static let defaultBaseline = 2070.0
    public static let defaultTestOffset = 500.0

    public let baseline: Double
    public let easier: Double
    public let harder: Double

    public init(
        baseline: Double,
        testOffset: Double = defaultTestOffset
    ) throws {
        guard testOffset.isFinite, testOffset > 0 else {
            throw WahooKickrProofValuesError.invalidTestOffset(testOffset)
        }
        guard baseline.isFinite,
              baseline - testOffset > 0,
              baseline + testOffset
                <= WahooKickrCommand.maximumCircumferenceMillimeters
        else {
            throw WahooKickrProofValuesError.invalidBaseline(baseline)
        }

        self.baseline = baseline
        easier = baseline - testOffset
        harder = baseline + testOffset
    }

    public subscript(selection: WahooKickrProofSelection) -> Double {
        switch selection {
        case .easier:
            easier
        case .baseline:
            baseline
        case .harder:
            harder
        }
    }
}

public enum WahooKickrCommand {
    public static let unlock = Data([0x20, 0xEE, 0xFC])
    public static let maximumCircumferenceMillimeters =
        Double(UInt16.max) / 10

    public static func setWheelCircumference(
        millimeters: Double
    ) throws -> Data {
        guard millimeters.isFinite,
              millimeters >= 0,
              millimeters <= maximumCircumferenceMillimeters
        else {
            throw WahooKickrCommandError.invalidWheelCircumference(
                millimeters
            )
        }

        let encoded = UInt16((millimeters * 10).rounded())
        return Data([
            0x48,
            UInt8(encoded & 0x00FF),
            UInt8(encoded >> 8),
        ])
    }
}
