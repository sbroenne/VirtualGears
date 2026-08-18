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

/// The rider's own gear count and range, used when they want something other
/// than the one built-in ladder. Stored separately from `GearLadder` because it
/// is parameters a rider can edit, not a fixed table.
public struct CustomGearLadder: Codable, Equatable, Sendable {
    public var gearCount: Int
    public var easiestRatioHundredths: Int
    public var hardestRatioHundredths: Int

    public init(
        gearCount: Int,
        easiestRatioHundredths: Int,
        hardestRatioHundredths: Int
    ) {
        self.gearCount = gearCount
        self.easiestRatioHundredths = easiestRatioHundredths
        self.hardestRatioHundredths = hardestRatioHundredths
    }

    /// Starts from the same numbers as the built-in ladder, so switching to
    /// "Custom" for the first time changes nothing about how the bike rides
    /// until the rider actually edits something.
    public static let `default` = CustomGearLadder(
        gearCount: 24,
        easiestRatioHundredths: 75,
        hardestRatioHundredths: 549
    )

    /// How many gears a custom ladder may have. Below this a "ladder" stops
    /// meaning anything; above it the on-screen shift buttons would need more
    /// taps than any real derailleur has sprockets.
    public static let gearCountRange = 6...30

    /// The same figures `TrainerSafety.supportedScaleRange` allows a built-in
    /// ladder to reach, rounded to whole hundredths so a rider edits the same
    /// units the note text shows.
    public static var ratioHundredthsRange: ClosedRange<Int> {
        let scale = TrainerSafety.supportedScaleRange
        let lower = Int((scale.lowerBound * 100).rounded(.up))
        let upper = Int((scale.upperBound * 100).rounded(.down))
        return lower...upper
    }
}

public enum GearLadderCatalog {
    /// The twenty-four ratios published for the best-known virtual shifting
    /// system, reproduced exactly.
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

    /// The one built-in ladder. A rider who wants something else defines their
    /// own instead of choosing between several fixed tables that all belong to
    /// no bike they own.
    public static let ladders: [GearLadder] = [standardRange]

    public static let defaultLadderID = standardRange.id

    /// The id a saved configuration uses to mean "build the ladder from the
    /// rider's own `CustomGearLadder` parameters instead of a fixed table."
    public static let customLadderID = "custom"

    public static func ladder(id: String) -> GearLadder? {
        ladders.first { $0.id == id }
    }

    public static var defaultLadder: GearLadder {
        ladder(id: defaultLadderID) ?? standardRange
    }

    /// Builds evenly spaced ratios from a rider's own gear count and range, the
    /// same way every built-in ladder is shaped. The starting gear sits at the
    /// same fractional position `standardRange` starts at, so a custom ladder
    /// feels centred the same way rather than starting at one end.
    public static func custom(_ params: CustomGearLadder) -> GearLadder {
        let count = max(2, params.gearCount)
        let easiest = min(
            params.easiestRatioHundredths, params.hardestRatioHundredths
        )
        let hardest = max(
            params.easiestRatioHundredths, params.hardestRatioHundredths
        )
        let ratios: [Int] = (0..<count).map { index in
            guard count > 1 else { return hardest }
            let fraction = Double(index) / Double(count - 1)
            return Int(
                (Double(easiest) + fraction * Double(hardest - easiest))
                    .rounded()
            )
        }
        let startingFraction = Double(standardRange.startingIndex)
            / Double(standardRange.gearCount - 1)
        let startingIndex = min(
            count - 1,
            max(0, Int((startingFraction * Double(count - 1)).rounded()))
        )
        return GearLadder(
            id: customLadderID,
            name: "Custom \(count)",
            note: String(
                format: "%.2f to %.2f, your own range",
                Double(easiest) / 100, Double(hardest) / 100
            ),
            ratiosHundredths: ratios,
            startingIndex: startingIndex
        )
    }
}
