public enum VirtualGearError: Error, Equatable {
    case invalidToothCount
    case invalidCircumferenceInputs
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

        return circumference
    }
}
