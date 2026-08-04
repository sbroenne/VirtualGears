import Foundation

/// The limits confirmed on real hardware, kept in one place so the setup screen,
/// the gear engine and the safety tests can never disagree about them.
public enum TrainerSafety {
    /// The wheel size the trainer is left sitting at, and the size every gear is
    /// scaled away from.
    public static let referenceCircumferenceMillimeters: Double = 2_070

    /// Staged on a physical KICKR V5, every value acknowledged, with the
    /// reference restored between each probe. Values outside this were never
    /// confirmed, so VirtualShift never asks for them.
    public static let provenCircumferenceMillimeters: ClosedRange<Double> =
        646.9...4_800

    /// The proven range expressed as a multiple of the reference: how much
    /// easier or harder than the starting gear the trainer can be asked to feel.
    public static var provenScaleRange: ClosedRange<Double> {
        provenCircumferenceMillimeters.lowerBound
            / referenceCircumferenceMillimeters
            ... provenCircumferenceMillimeters.upperBound
            / referenceCircumferenceMillimeters
    }

    /// The widest easiest-to-hardest span any drivetrain can have and still fit,
    /// even when its starting gear is placed perfectly.
    public static var widestSupportedSpan: Double {
        provenScaleRange.upperBound / provenScaleRange.lowerBound
    }
}
