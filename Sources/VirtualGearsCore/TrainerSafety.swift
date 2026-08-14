import Foundation

/// The limits confirmed on real hardware, kept in one place so the setup screen,
/// the gear engine and the safety tests can never disagree about them.
public enum TrainerSafety {
    /// The wheel size the trainer is left sitting at, and the size every gear is
    /// scaled away from.
    public static let referenceCircumferenceMillimeters: Double = 2_070

    /// The range Virtual Gears will operate in. Staged on a physical KICKR V5
    /// across four runs — 647 mm to 4800 mm, 517.5 mm to 647 mm, 500 mm to
    /// 517.5 mm, and 4800 mm to 5000 mm in 25 mm steps — with every value
    /// acknowledged and the reference reset between each probe, so both ends of
    /// this range and the whole gear ladder between them are covered. The third
    /// run exists because the first two stopped at 517.5 mm while this range
    /// claimed 500 mm; the bottom is now measured rather than assumed.
    ///
    /// The fourth run raised the top from 4800 mm, and the reason is not more
    /// gear: the virtual ladder is centred inside this range, so the range's
    /// width is also the room a riding app has to set its own wheel size. At
    /// 4800 mm the ladder left a baseline window of 2000-2098 mm, which refused
    /// a 700x25c wheel at 2105 mm — an ordinary road wheel, and one the
    /// reference riding app really does send. The window is now 2000-2186 mm.
    ///
    /// Be aware that this one number does three jobs, so widening it for the
    /// third changed the other two. It gates what may be sent to the trainer,
    /// it is the budget the virtual ladder is centred in, and it is the room a
    /// riding app has. The virtual ladder itself did not move — its ratios are
    /// a fixed list, so the reference gear and all 24 wheel sizes are identical
    /// before and after — but three more custom drivetrain combinations now
    /// pass the safety check, 613 of 616 rather than 610. That is a real
    /// consequence of widening the range, not a separate decision.
    ///
    /// This intentionally remains much narrower than the command's encodable
    /// limits. Nothing here is a limit of the gears or the trainer; both would
    /// go further. It is a limit of what has been measured.
    public static let provenCircumferenceMillimeters: ClosedRange<Double> =
        500...5_000

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
