import Foundation

public enum HeadwindMode: UInt8, Codable, CaseIterable, Equatable, Sendable {
    case off = 0x01
    case heartRate = 0x02
    case speed = 0x03
    case manual = 0x04
    case sleep = 0x05

    public var isSensorControlled: Bool {
        self == .heartRate || self == .speed
    }

    public var label: String {
        switch self {
        case .off: "Off"
        case .heartRate: "Heart-rate sensor"
        case .speed: "Speed sensor"
        case .manual: "Manual"
        case .sleep: "Sleeping"
        }
    }
}

public enum HeadwindCommand: Equatable, Sendable {
    case setMode(HeadwindMode)
    case setManualSpeed(Int)

    public func encode() throws -> Data {
        switch self {
        case let .setMode(mode):
            return Data([0x04, mode.rawValue, 0x00, 0x00])
        case let .setManualSpeed(percent):
            guard (0...100).contains(percent) else {
                throw HeadwindProtocolError.invalidSpeed(percent)
            }
            return Data([0x02, UInt8(percent), 0x00, 0x00])
        }
    }
}

public enum HeadwindMessage: Equatable, Sendable {
    case state(mode: HeadwindMode, manualSpeed: Int)
    case modeAcknowledged(HeadwindMode, succeeded: Bool)
    case speedAcknowledged(Int, succeeded: Bool)
}

public enum HeadwindProtocolError: Error, Equatable {
    case invalidSpeed(Int)
    case malformedMessage
    case unknownMode(UInt8)
}

public enum HeadwindMessageDecoder {
    public static func decode(_ data: Data) throws -> HeadwindMessage {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else {
            throw HeadwindProtocolError.malformedMessage
        }

        switch (bytes[0], bytes[1]) {
        case (0xFD, 0x01):
            guard let mode = HeadwindMode(rawValue: bytes[3]) else {
                throw HeadwindProtocolError.unknownMode(bytes[3])
            }
            return .state(mode: mode, manualSpeed: Int(bytes[2]))
        case (0xFE, 0x04):
            guard let mode = HeadwindMode(rawValue: bytes[3]) else {
                throw HeadwindProtocolError.unknownMode(bytes[3])
            }
            return .modeAcknowledged(mode, succeeded: bytes[2] == 0x01)
        case (0xFE, 0x02):
            return .speedAcknowledged(Int(bytes[3]), succeeded: bytes[2] == 0x01)
        default:
            throw HeadwindProtocolError.malformedMessage
        }
    }
}
