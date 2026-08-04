public enum VirtualGearError: Error, Equatable {
    case invalidToothCount
    case invalidCircumferenceInputs
    /// The gear would ask the trainer for a wheel size never confirmed on real
    /// hardware. Usually because a riding app moved the starting wheel size far
    /// enough that the gears no longer fit around it.
    case outsideProvenRange
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
        guard circumference.isFinite,
              circumference > 0,
              circumference
                <= WahooKickrCommand.maximumCircumferenceMillimeters
        else {
            throw VirtualGearError.invalidCircumferenceInputs
        }
        // The one gate every gear passes through, wherever the starting wheel
        // size came from. A riding app is free to set its own, but not to push
        // the gears built around it past what the trainer was proven to accept.
        guard TrainerSafety.provenCircumferenceMillimeters.contains(
            TrainerSafety.circumferenceAsSent(circumference)
        ) else {
            throw VirtualGearError.outsideProvenRange
        }

        return circumference
    }
}
