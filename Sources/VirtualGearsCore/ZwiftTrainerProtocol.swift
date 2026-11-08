import Foundation

public enum ZwiftTrainerUUID {
    public static let service = "00000001-19CA-4651-86E5-FA29DCDD09D1"
    public static let notify = "00000002-19CA-4651-86E5-FA29DCDD09D1"
    public static let write = "00000003-19CA-4651-86E5-FA29DCDD09D1"
    public static let indicate = "00000004-19CA-4651-86E5-FA29DCDD09D1"
}

public enum ZwiftTrainerCodecError: Error, Equatable {
    case malformedMessage
    case unsupportedMessage(UInt8)
    case invalidParameter(String)
}

// Only wire-format facts are shared with the public protocol research. This
// codec is independent of third-party implementations and their generated code.
struct ZwiftProtobuf {
    enum Value: Equatable {
        case integer(UInt64)
        case bytes(Data)
    }

    var fields: [Int: Value] = [:]

    init(_ data: Data = Data()) throws {
        let bytes = Array(data)
        guard bytes.count <= 512 else {
            throw ZwiftTrainerCodecError.malformedMessage
        }
        var offset = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else {
                    throw ZwiftTrainerCodecError.malformedMessage
                }
                let byte = bytes[offset]
                offset += 1
                guard index < 9 || byte <= 1 else {
                    throw ZwiftTrainerCodecError.malformedMessage
                }
                value |= UInt64(byte & 0x7F) << (index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw ZwiftTrainerCodecError.malformedMessage
        }
        func take(_ count: Int) throws -> Data {
            guard count <= bytes.count - offset else {
                throw ZwiftTrainerCodecError.malformedMessage
            }
            defer { offset += count }
            return Data(bytes[offset..<(offset + count)])
        }
        while offset < bytes.count {
            let tag = try varint()
            guard tag >> 3 > 0, tag >> 3 <= 0x1FFF_FFFF else {
                throw ZwiftTrainerCodecError.malformedMessage
            }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0: fields[field] = .integer(try varint())
            case 1: _ = try take(8)
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - offset) else {
                    throw ZwiftTrainerCodecError.malformedMessage
                }
                fields[field] = .bytes(try take(Int(length)))
            case 5: _ = try take(4)
            default: throw ZwiftTrainerCodecError.malformedMessage
            }
        }
    }

    func integer(_ field: Int) throws -> UInt32? {
        guard let value = fields[field] else { return nil }
        guard case let .integer(raw) = value, let result = UInt32(exactly: raw) else {
            throw ZwiftTrainerCodecError.malformedMessage
        }
        return result
    }

    func message(_ field: Int) throws -> ZwiftProtobuf? {
        guard let value = fields[field] else { return nil }
        guard case let .bytes(data) = value else {
            throw ZwiftTrainerCodecError.malformedMessage
        }
        return try ZwiftProtobuf(data)
    }

    static func varint(_ value: UInt64) -> Data {
        var remainder = value
        var data = Data()
        repeat {
            let byte = UInt8(remainder & 0x7F)
            remainder >>= 7
            data.append(byte | (remainder == 0 ? 0 : 0x80))
        } while remainder > 0
        return data
    }

    static func integer(_ field: Int, _ value: UInt32) -> Data {
        varint(UInt64(field << 3)) + varint(UInt64(value))
    }

    static func bytes(_ field: Int, _ value: Data) -> Data {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value
    }
}

public struct ZwiftSimulation: Equatable, Sendable {
    public var windHundredths: Int32?
    public var inclineHundredths: Int32?
    public var aerodynamicTenThousandths: UInt32?
    public var rollingHundredThousandths: UInt32?

    public init(
        windHundredths: Int32? = nil,
        inclineHundredths: Int32? = nil,
        aerodynamicTenThousandths: UInt32? = nil,
        rollingHundredThousandths: UInt32? = nil
    ) {
        self.windHundredths = windHundredths
        self.inclineHundredths = inclineHundredths
        self.aerodynamicTenThousandths = aerodynamicTenThousandths
        self.rollingHundredThousandths = rollingHundredThousandths
    }

    public func merging(_ newer: Self) -> Self {
        Self(
            windHundredths: newer.windHundredths ?? windHundredths,
            inclineHundredths: newer.inclineHundredths ?? inclineHundredths,
            aerodynamicTenThousandths: newer.aerodynamicTenThousandths ?? aerodynamicTenThousandths,
            rollingHundredThousandths: newer.rollingHundredThousandths ?? rollingHundredThousandths
        )
    }

    public func ftmsParameters() throws -> IndoorBikeSimulationParameters {
        guard let wind = Int16(exactly: Int64(windHundredths ?? 0) * 10),
              let grade = Int16(exactly: inclineHundredths ?? 0),
              let aero = UInt8(exactly: (UInt64(aerodynamicTenThousandths ?? 5100) + 50) / 100),
              let rolling = UInt8(exactly: (UInt64(rollingHundredThousandths ?? 400) + 5) / 10) else {
            throw ZwiftTrainerCodecError.invalidParameter("Simulation exceeds FTMS range")
        }
        return IndoorBikeSimulationParameters(
            windSpeedThousandthsMetersPerSecond: wind,
            gradeHundredthsPercent: grade,
            rollingResistanceCoefficientTenThousandths: rolling,
            windResistanceCoefficientHundredthsKilogramsPerMeter: aero
        )
    }
}

public struct ZwiftHubCommand: Equatable, Sendable {
    public var ratioX10000: UInt32?
    public var simulation: ZwiftSimulation?
    public var powerTarget: UInt32?

    public init(
        ratioX10000: UInt32? = nil,
        simulation: ZwiftSimulation? = nil,
        powerTarget: UInt32? = nil
    ) {
        self.ratioX10000 = ratioX10000
        self.simulation = simulation
        self.powerTarget = powerTarget
    }
}

public enum ZwiftTrainerRequest: Equatable, Sendable {
    case rideOn
    case deviceInformation
    case query(UInt32)
    case command(ZwiftHubCommand)

    public static func decode(_ data: Data) throws -> Self {
        let rideOn = Data("RideOn".utf8) + Data([2])
        // RealVelo appends 04 to this greeting. QZ matches the RideOn prefix.
        if data == rideOn || data == rideOn + Data([4]) { return .rideOn }
        guard let opcode = data.first else {
            throw ZwiftTrainerCodecError.malformedMessage
        }
        let message = try ZwiftProtobuf(Data(data.dropFirst()))
        switch opcode {
        case 0x41:
            guard try message.integer(1) == 5 else {
                throw ZwiftTrainerCodecError.invalidParameter("Device-information request")
            }
            return .deviceInformation
        case 0:
            return .query(try message.integer(1) ?? 0)
        case 4:
            let physical = try message.message(5)
            if physical?.fields[4] != nil || physical?.fields[5] != nil {
                ProductLogger.record(
                    "Zwift bike/rider weight fields are not forwarded; the KICKR keeps its configured weight",
                    source: "Zwift Protocol", level: .warning
                )
            }
            let ratio = try physical?.integer(2)
            if ratio == 0 {
                throw ZwiftTrainerCodecError.invalidParameter("Gear ratio must be positive")
            }
            let simulation: ZwiftSimulation?
            if let sim = try message.message(4) {
                func signed(_ field: Int) throws -> Int32? {
                    try sim.integer(field).map {
                        Int32(bitPattern: ($0 >> 1) ^ (0 &- ($0 & 1)))
                    }
                }
                simulation = try ZwiftSimulation(
                    windHundredths: signed(1),
                    inclineHundredths: signed(2),
                    aerodynamicTenThousandths: sim.integer(3),
                    rollingHundredThousandths: sim.integer(4)
                )
            } else {
                simulation = nil
            }
            let power = try message.integer(3)
            guard ratio != nil || simulation != nil || power != nil else {
                throw ZwiftTrainerCodecError.invalidParameter("No supported trainer command")
            }
            return .command(.init(
                ratioX10000: ratio,
                simulation: simulation,
                powerTarget: power
            ))
        default: throw ZwiftTrainerCodecError.unsupportedMessage(opcode)
        }
    }

    public func encode() -> Data {
        switch self {
        case .rideOn: return Data("RideOn".utf8) + Data([2])
        case .deviceInformation: return Data([0x41]) + ZwiftProtobuf.integer(1, 5)
        case let .query(id): return Data([0]) + ZwiftProtobuf.integer(1, id)
        case let .command(command):
            var data = Data([4])
            if let power = command.powerTarget {
                data += ZwiftProtobuf.integer(3, power)
            }
            if let sim = command.simulation {
                var payload = Data()
                func signed(_ field: Int, _ value: Int32?) {
                    guard let value else { return }
                    let encoded = UInt32(bitPattern: (value << 1) ^ (value >> 31))
                    payload += ZwiftProtobuf.integer(field, encoded)
                }
                signed(1, sim.windHundredths)
                signed(2, sim.inclineHundredths)
                if let value = sim.aerodynamicTenThousandths {
                    payload += ZwiftProtobuf.integer(3, value)
                }
                if let value = sim.rollingHundredThousandths {
                    payload += ZwiftProtobuf.integer(4, value)
                }
                data += ZwiftProtobuf.bytes(4, payload)
            }
            if let ratio = command.ratioX10000 {
                data += ZwiftProtobuf.bytes(5, ZwiftProtobuf.integer(2, ratio))
            }
            return data
        }
    }
}

public struct ZwiftTrainerResponse: Equatable, Sendable {
    public enum Channel: Equatable, Sendable { case notify, indicate }
    public let channel: Channel
    public let data: Data

    public init(channel: Channel = .indicate, data: Data) {
        self.channel = channel
        self.data = data
    }

    public static let rideOn = Self(data: Data("RideOn".utf8) + Data([2, 0]))

    public static func information() -> Self {
        let content = ZwiftProtobuf.integer(1, 512)
            + ZwiftProtobuf.bytes(2, Data([1, 0, 0, 1]))
            + ZwiftProtobuf.bytes(3, Data("Virtual Gears".utf8))
            + ZwiftProtobuf.bytes(7, Data("1".utf8))
            // Observed trainer-information field in QZ's Hub handshake. Its
            // meaning is undocumented; it is not a trainer name or serial.
            + ZwiftProtobuf.bytes(8, Data([0x08, 0x01, 0x10, 0x14]))
        return Self(data: Data([0x3C])
            + ZwiftProtobuf.integer(1, 0)
            + ZwiftProtobuf.bytes(2, ZwiftProtobuf.bytes(1, content)))
    }

    public static func ratio(_ ratioX10000: UInt32) -> Self {
        Self(data: Data([0x3C])
            + ZwiftProtobuf.integer(1, 520)
            + ZwiftProtobuf.bytes(2, ZwiftProtobuf.bytes(
                1, ZwiftProtobuf.integer(8, ratioX10000)
            )))
    }

    public static func ridingData(_ bike: IndoorBikeData) -> Data {
        var data = Data([3])
        if let power = bike.instantaneousPowerWatts {
            data += ZwiftProtobuf.integer(1, UInt32(max(0, power)))
        }
        if let cadence = bike.instantaneousCadenceHalfRPM {
            data += ZwiftProtobuf.integer(2, UInt32(cadence / 2))
        }
        if let speed = bike.instantaneousSpeedHundredths {
            data += ZwiftProtobuf.integer(3, UInt32(speed))
        }
        if let heartRate = bike.heartRateBPM {
            data += ZwiftProtobuf.integer(4, UInt32(heartRate))
        }
        return data
    }
}
