import Foundation

/// The limits that decide what Virtual Gears may ask a trainer to do, kept in
/// one place so the setup screen, the gear engine and the safety tests can
/// never disagree about them.
///
/// There is only one hard limit here, and it is not the trainer. A physical
/// KICKR V5 was probed across its whole encodable span and acknowledged every
/// value it was given, from 0.1 mm to 6553.5 mm, plus sixty-four staged values
/// in between across six later runs without a single refusal. 6553.5 mm is
/// simply the largest number the command can express. So the trainer accepted
/// everything the protocol can say to it, and no upper or lower wheel-size
/// limit of the trainer has ever been found.
///
/// Virtual Gears used to carry a narrower "proven range" and treat it as a
/// trainer limit. It was not one. It was a record of which values had been
/// probed, and because the gear ladder is centred inside it, it silently
/// doubled as the room a riding app had to set its own wheel size. That is why
/// the app kept discovering it was too narrow one riding app at a time — most
/// recently refusing a wheel size a rider had set in FulGaz, which meant the
/// two could not work together at all. A riding app sends whatever wheel size
/// its rider configured, so there is no single value to design around and a
/// declared window is the only honest answer. It is declared below and tested,
/// instead of emerging by accident from an unrelated number.
public enum TrainerSafety {
    /// The wheel size the trainer is left sitting at, and the size every gear is
    /// scaled away from.
    public static let referenceCircumferenceMillimeters: Double = 2_070

    /// The wheel sizes a riding app may set, and the promise the tests enforce:
    /// every gear must build at every size in here.
    ///
    /// This covers every wheel a trainer is realistically asked about — a 650b
    /// at 1900 mm, a 700x25c at 2105 mm, a 29er at 2326 mm — with room either
    /// side, because riders type these numbers into their riding app by hand. It is a product decision about real
    /// bicycle wheels, not a measurement, because there is nothing left to
    /// measure: the trainer takes anything.
    ///
    /// The width is bounded by one real thing. At the largest size here the
    /// hardest gear must still fit in the command, and 2400 mm reaches 5490 mm
    /// against a ceiling of 6553.5 mm. Widening this range past roughly
    /// 2865 mm would put the top gear beyond what the command can encode, so
    /// `testEveryGearEncodesAtEverySupportedWheelSize` is what stops that going
    /// unnoticed.
    public static let supportedRidingAppCircumferenceMillimeters:
        ClosedRange<Double> = 1_800...2_400

    /// The trainer is told a wheel size in tenths of a millimetre, so what it
    /// receives is always rounded to the nearest tenth.
    public static let commandStepMillimeters: Double = 0.1

    /// The value the trainer actually receives for a request.
    public static func circumferenceAsSent(_ millimeters: Double) -> Double {
        (millimeters / commandStepMillimeters).rounded() * commandStepMillimeters
    }

    /// How far either side of its starting gear a drivetrain may reach.
    ///
    /// The top is a genuine limit, and the only one in this file: at the largest
    /// wheel size supported above, the hardest gear still has to fit in the
    /// command.
    ///
    /// The bottom is a choice rather than a limit. The trainer acknowledged
    /// 0.1 mm quite happily, but a gear that small makes it report almost no
    /// speed, which a riding app would draw as a rider who has stopped. This
    /// keeps the easiest gear near the easiest one shipped and actually ridden.
    public static var supportedScaleRange: ClosedRange<Double> {
        let hardest = WahooKickrCommand.maximumCircumferenceMillimeters
            / supportedRidingAppCircumferenceMillimeters.upperBound
        return 0.24...hardest
    }

    /// The widest easiest-to-hardest span any drivetrain can have and still fit,
    /// even when its starting gear is placed perfectly.
    public static var widestSupportedSpan: Double {
        supportedScaleRange.upperBound / supportedScaleRange.lowerBound
    }
}
