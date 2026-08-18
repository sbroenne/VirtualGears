import Foundation

/// A ladder of virtual ratios that belongs to no real bike.
///
/// These are for riders who do not want to copy a groupset at all — a Zwift Cog
/// on the trainer and a made-up set of evenly spaced gears is a perfectly good
/// way to ride indoors, and it needs no knowledge of what is bolted to the bike.
public struct GearLadder: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let note: String
    /// Ratios out of one hundred, easiest first, because these are not parts
    /// anyone can buy and whole-number maths keeps the ordering exact.
    public let ratiosHundredths: [Int]
    /// The gear every ride starts in. Stated per ladder, never calculated, so
    /// editing an unrelated safety number cannot move it.
    public let startingIndex: Int

    public init(
        id: String,
        name: String,
        note: String,
        ratiosHundredths: [Int],
        startingIndex: Int
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.ratiosHundredths = ratiosHundredths
        self.startingIndex = startingIndex
    }

    public var gearCount: Int { ratiosHundredths.count }

    public var startingRatio: Double {
        Double(ratiosHundredths[startingIndex]) / 100
    }

    public func drivetrain(
        scaleRange: ClosedRange<Double> = TrainerSafety.supportedScaleRange
    ) throws -> Drivetrain {
        try Drivetrain.virtualLadder(ratiosHundredths: ratiosHundredths,
                                     startingIndex: startingIndex,
                                     scaleRange: scaleRange)
    }
}

public enum GearLadderCatalog {
    /// Twenty-four evenly spaced ratios whose upper half is the widely used
    /// table and whose lower half reaches further down, so first gear is
    /// genuinely easy for indoor climbing without giving up anything at the top.
    public static let extendedRange = GearLadder(
        id: "virtual-gears-24",
        name: "Virtual Gears 24",
        note: "0.60 to 5.49, with an extra-low climbing range",
        ratiosHundredths: [
            60, 68, 77, 88, 100, 113, 129, 146,
            165, 187, 212, 240, 261, 282, 303, 324,
            349, 374, 399, 424, 454, 484, 514, 549,
        ],
        startingIndex: 11
    )

    /// The twenty-four ratios published for the best-known virtual shifting
    /// system, reproduced exactly. Our own ladder already shares its upper half
    /// and its starting gear; the difference is only the easy end.
    ///
    /// Named descriptively rather than after the product. Virtual Gears is not
    /// affiliated with, endorsed by, or connected to Zwift, Wahoo, Shimano,
    /// SRAM or Campagnolo; those names appear only to say what the gearing
    /// copies.
    public static let standardRange = GearLadder(
        id: "standard-24",
        name: "Standard 24",
        note: "0.75 to 5.49, the common virtual ladder",
        ratiosHundredths: [
            75, 87, 99, 111, 123, 138, 153, 168,
            186, 204, 222, 240, 261, 282, 303, 324,
            349, 374, 399, 424, 454, 484, 514, 549,
        ],
        startingIndex: 11
    )

    public static let ladders: [GearLadder] = [extendedRange, standardRange]

    /// The easier bottom end is the better default indoors, where the gradient
    /// a riding app hands out is not limited by what a rider could climb
    /// outside. Chosen on merit: the app has no riders yet, so there is no
    /// previous behaviour to preserve.
    public static let defaultLadderID = extendedRange.id

    public static func ladder(id: String) -> GearLadder? {
        ladders.first { $0.id == id }
    }

    public static var defaultLadder: GearLadder {
        ladder(id: defaultLadderID) ?? extendedRange
    }
}
