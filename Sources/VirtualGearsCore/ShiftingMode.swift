import Foundation

public enum ShiftingMode: String, Codable, CaseIterable, Sendable {
    case independent
    case zwiftCompatible

    public var name: String {
        switch self {
        case .independent: "Shift with Virtual Gears"
        case .zwiftCompatible: "Shift with Zwift or a compatible app"
        }
    }

    public var explanation: String {
        switch self {
        case .independent:
            "Connect your Click here, or use the on-screen shift buttons."
        case .zwiftCompatible:
            "Connect your Click to that app. It controls the gears; Virtual Gears applies them to your KICKR."
        }
    }

    public static let zwiftRatioRange = 0.75...5.49

    public var advertisedTrainerServiceUUIDs: [String] {
        let services = [FTMSUUID.fitnessMachineService, CyclingPowerUUID.service]
        return self == .zwiftCompatible ? services + [ZwiftTrainerUUID.service] : services
    }
}

public struct AppRatioSetting: Equatable, Sendable {
    public let requestedRatio: Double
    public let appliedRatio: Double
    public let circumferenceMillimeters: Double
    public let command: Data
    public let wasClamped: Bool

    public init(
        ratio: Double,
        neutralMillimeters: Double,
        parkedRatio: Double
    ) throws {
        guard ratio.isFinite, ratio > 0,
              neutralMillimeters.isFinite,
              TrainerSafety.supportedRidingAppCircumferenceMillimeters
                .contains(neutralMillimeters),
              parkedRatio.isFinite, parkedRatio > 0 else {
            throw VirtualGearError.invalidCircumferenceInputs
        }
        let scale = TrainerSafety.supportedScaleRange
        let lower = neutralMillimeters * scale.lowerBound
        let upper = min(
            neutralMillimeters * scale.upperBound,
            WahooKickrCommand.maximumCircumferenceMillimeters
        )
        let requested = neutralMillimeters * (ratio / parkedRatio)
        let bounded = min(upper, max(lower, requested))
        // Match the command's tenth-millimetre precision before reporting status.
        let encoded = min(floor(upper * 10), max(ceil(lower * 10), (bounded * 10).rounded()))
        circumferenceMillimeters = encoded / 10
        appliedRatio = circumferenceMillimeters / neutralMillimeters * parkedRatio
        guard appliedRatio.isFinite, appliedRatio * 10_000 <= Double(UInt32.max) else {
            throw VirtualGearError.outsideSupportedRange
        }
        requestedRatio = ratio
        wasClamped = requested < lower || requested > upper
        command = try WahooKickrCommand.setWheelCircumference(
            millimeters: circumferenceMillimeters
        )
    }

    public var encodedRatio: UInt32 {
        UInt32((appliedRatio * 10_000).rounded())
    }
}
