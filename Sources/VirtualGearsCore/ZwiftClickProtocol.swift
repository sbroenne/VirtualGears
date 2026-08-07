import Foundation

public enum ZwiftClickProtocol {
    public static let serviceUUID =
        "00000001-19CA-4651-86E5-FA29DCDD09D1"
    public static let asyncCharacteristicUUID =
        "00000002-19CA-4651-86E5-FA29DCDD09D1"
    public static let syncReceiveCharacteristicUUID =
        "00000003-19CA-4651-86E5-FA29DCDD09D1"
    public static let syncTransmitCharacteristicUUID =
        "00000004-19CA-4651-86E5-FA29DCDD09D1"
    public static let rideOn = Data("RideOn".utf8)
}

public enum ZwiftClickButton: Equatable, Sendable {
    case plus
    case minus
}

public enum ZwiftClickButtonEvent: Equatable, Sendable {
    case pressed(ZwiftClickButton)
    case released(ZwiftClickButton)
}

public enum ZwiftClickMessage: Equatable, Sendable {
    case buttons(plusPressed: Bool, minusPressed: Bool)
    case batteryLevel(percent: Int)
    case keepAlive
    case other(type: UInt8)
}

public enum ZwiftClickMessageError: Error, Equatable {
    case malformedData
}

public enum ZwiftClickMessageDecoder {
    public static func decode(_ data: Data) throws -> ZwiftClickMessage {
        let bytes = Array(data)
        guard let type = bytes.first else {
            throw ZwiftClickMessageError.malformedData
        }

        switch type {
        // Sent when the controller has nothing to report. Never seen from an
        // original Click, which uses the battery message below as its
        // heartbeat, but Zwift's other controllers do send it.
        case 0x15:
            return .keepAlive
        // The Click reports its battery here, roughly every five seconds, as
        // `19 10 64`: a percentage in field 2, so `0x64` is 100%. Two
        // independent projects that reverse-engineered these controllers,
        // qdomyos-zwift and ajchellew/zwiftplay, both name type 25 the battery
        // level message, which is why this is decoded rather than guessed at.
        // Recognising it also keeps a ride's diagnostics free of an unknown
        // message every five seconds, which would bury anything that matters.
        case 0x19:
            var index = 1
            var percent: UInt64?
            while index < bytes.count {
                let tag = try readVarint(bytes, index: &index)
                guard tag & 0x07 == 0 else {
                    throw ZwiftClickMessageError.malformedData
                }
                let value = try readVarint(bytes, index: &index)
                if tag >> 3 == 2 {
                    percent = value
                }
            }
            guard let percent, percent <= 100 else {
                throw ZwiftClickMessageError.malformedData
            }
            return .batteryLevel(percent: Int(percent))
        case 0x37:
            var index = 1
            var plusValue: UInt64?
            var minusValue: UInt64?

            while index < bytes.count {
                let tag = try readVarint(bytes, index: &index)
                guard tag & 0x07 == 0 else {
                    throw ZwiftClickMessageError.malformedData
                }
                let value = try readVarint(bytes, index: &index)
                switch tag >> 3 {
                case 1:
                    plusValue = value
                case 2:
                    minusValue = value
                default:
                    break
                }
            }

            guard let plusValue, let minusValue else {
                throw ZwiftClickMessageError.malformedData
            }
            return .buttons(
                plusPressed: plusValue == 0,
                minusPressed: minusValue == 0
            )
        default:
            return .other(type: type)
        }
    }

    private static func readVarint(
        _ bytes: [UInt8],
        index: inout Int
    ) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw ZwiftClickMessageError.malformedData
    }
}

public struct ZwiftClickEdgeTracker: Sendable {
    private var plusPressed = false
    private var minusPressed = false

    public init() {}

    public mutating func update(
        plus newPlusPressed: Bool,
        minus newMinusPressed: Bool
    ) -> [ZwiftClickButtonEvent] {
        var events: [ZwiftClickButtonEvent] = []

        if plusPressed != newPlusPressed {
            events.append(
                newPlusPressed ? .pressed(.plus) : .released(.plus)
            )
        }
        if minusPressed != newMinusPressed {
            events.append(
                newMinusPressed ? .pressed(.minus) : .released(.minus)
            )
        }

        plusPressed = newPlusPressed
        minusPressed = newMinusPressed
        return events
    }
}
