import Foundation

/// The limits confirmed on real hardware, kept in one place so the setup screen,
/// the gear engine and the safety tests can never disagree about them.
public enum TrainerSafety {
    /// The wheel size the trainer is left sitting at, and the size every gear is
    /// scaled away from.
    public static let referenceCircumferenceMillimeters: Double = 2_070

    /// The range Virtual Gears will operate in. Staged on a physical KICKR V5
    /// across five runs — 647 mm to 4800 mm, 517.5 mm to 647 mm, 500 mm to
    /// 517.5 mm, 4800 mm to 5000 mm, and 5000 mm to 5350 mm in 25 mm steps —
    /// with every value acknowledged and the reference reset between each
    /// probe, so both ends of this range and the whole gear ladder between them
    /// are covered. The third run exists because the first two stopped at
    /// 517.5 mm while this range claimed 500 mm; the bottom is now measured
    /// rather than assumed.
    ///
    /// The fourth and fifth runs raised the top from 4800 mm, and the reason is
    /// not more gear: the virtual ladder is centred inside this range, so the
    /// range's width is also the room a riding app has to set its own wheel
    /// size. At 4800 mm the ladder left a baseline window of 2000-2098 mm,
    /// which refused a 700x25c wheel at 2105 mm. The fifth run was prompted by
    /// watching a real riding app: FulGaz asks for 2200 mm, which a 5000 mm
    /// ceiling also refused, so Virtual Gears and FulGaz could not have worked
    /// together. The window is now 1999.9-2338.8 mm, which additionally covers
    /// a 29er at 2326 mm. See docs/fulgaz-app-tap-run.log for the capture and
    /// docs/kickr-wheel-size-sweep-fulgaz.log for the hardware run.
    ///
    /// Be aware that this one number does three jobs, so widening it for the
    /// third changed the other two. It gates what may be sent to the trainer,
    /// it is the budget the virtual ladder is centred in, and it is the room a
    /// riding app has. The virtual ladder itself does not move — its ratios are
    /// a fixed list, and the reference gear stays at index 11 and ratio 2.40
    /// with a top of 5.49 at every ceiling from 5000 mm to 5400 mm — but a
    /// wider range does let more custom drivetrain combinations past the safety
    /// check. That is a real consequence of widening the range, not a separate
    /// decision.
    ///
    /// The bottom is untouched, so a 650b wheel at 1900 mm is still refused: it
    /// would need 475 mm at the easiest gear and only 500 mm has been measured.
    /// Raising the ceiling cannot help that one.
    ///
    /// This intentionally remains much narrower than the command's encodable
    /// limits. Nothing here is a limit of the gears or the trainer; both would
    /// go further. It is a limit of what has been measured.
    public static let provenCircumferenceMillimeters: ClosedRange<Double> =
        500...5_350

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
