import Foundation

public enum WahooKickrCommandError: Error, Equatable {
    case invalidWheelCircumference(Double)
}

public enum WahooKickrCommand {
    public static let unlock = Data([0x20, 0xEE, 0xFC])

    public static func setWheelCircumference(
        millimeters: Double
    ) throws -> Data {
        guard millimeters.isFinite,
              millimeters >= 0,
              millimeters <= Double(UInt16.max) / 10
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

