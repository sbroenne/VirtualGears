public enum VirtualGearError: Error, Equatable {
    case invalidToothCount
    case invalidCircumferenceInputs
    /// The gear would ask the trainer for a wheel size never confirmed on real
    /// hardware. Usually because a riding app moved the starting wheel size far
    /// enough that the gears no longer fit around it.
    case outsideSupportedRange
}

public struct VirtualGear: Equatable, Hashable, Sendable {
    public let chainring: Int
    public let cog: Int

    public init(chainring: Int, cog: Int) throws {
        guard chainring > 0, cog > 0 else {
            throw VirtualGearError.invalidToothCount
        }

        self.chainring = chainring
        self.cog = cog
    }

    public var ratio: Double {
        Double(chainring) / Double(cog)
    }
}

public enum WheelCircumferenceScaler {
    public static func effectiveCircumference(
        neutralCircumference: Double,
        referenceRatio: Double,
        selectedRatio: Double
    ) throws -> Double {
        guard neutralCircumference.isFinite,
              neutralCircumference > 0,
              referenceRatio.isFinite,
              referenceRatio > 0,
              selectedRatio.isFinite,
              selectedRatio > 0
        else {
            throw VirtualGearError.invalidCircumferenceInputs
        }

        let circumference =
            neutralCircumference / referenceRatio * selectedRatio
        // The one gate every gear passes through, and the only real limit
        // involved: what the command can express. No trainer limit has ever
        // been found — a physical KICKR V5 acknowledged every value from
        // 0.1 mm to 6553.5 mm, which is the whole encodable span. The wheel
        // sizes a riding app may ask for are bounded separately, and on
        // purpose, by TrainerSafety.supportedRidingAppCircumferenceMillimeters.
        guard circumference.isFinite,
              circumference > 0,
              circumference
                <= WahooKickrCommand.maximumCircumferenceMillimeters
        else {
            throw VirtualGearError.outsideSupportedRange
        }

        return circumference
    }
}
