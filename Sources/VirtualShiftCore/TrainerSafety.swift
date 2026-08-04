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

    /// The trainer is told a wheel size in tenths of a millimetre, so what it
    /// receives is always rounded to the nearest tenth.
    public static let commandStepMillimeters: Double = 0.1

    /// The value the trainer actually receives for a request.
    public static func circumferenceAsSent(_ millimeters: Double) -> Double {
        (millimeters / commandStepMillimeters).rounded() * commandStepMillimeters
    }

    /// The proven range expressed as a multiple of the reference: how much
    /// easier or harder than the starting gear the trainer can be asked to feel.
    ///
    /// The bounds are widened by half a step because a request half a tenth of a
    /// millimetre outside them is sent as a value squarely inside them. Judging
    /// anything else would reject gears the trainer never actually sees.
    public static var provenScaleRange: ClosedRange<Double> {
        let margin = commandStepMillimeters / 2
        return (provenCircumferenceMillimeters.lowerBound - margin)
            / referenceCircumferenceMillimeters
            ... (provenCircumferenceMillimeters.upperBound + margin)
            / referenceCircumferenceMillimeters
    }

    /// The widest easiest-to-hardest span any drivetrain can have and still fit,
    /// even when its starting gear is placed perfectly.
    public static var widestSupportedSpan: Double {
        provenScaleRange.upperBound / provenScaleRange.lowerBound
    }
}
