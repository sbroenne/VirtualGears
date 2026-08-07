import Foundation

public enum DrivetrainError: Error, Equatable {
    case emptyChainrings
    case emptyCassette
    case emptyAllowedCombinations
    case invalidChainring(Int)
    case invalidCassetteCog(Int)
    case duplicateChainring(Int)
    case duplicateCassetteCog(Int)
    case duplicateCombination(VirtualGear)
    case duplicateRatio(VirtualGear, VirtualGear)
    case unknownChainring(VirtualGear)
    case unknownCassetteCog(VirtualGear)
    case invalidReferenceIndex(Int)
    /// The easiest and hardest gear are too far apart for the trainer to cover,
    /// no matter which gear the ride starts in.
    case rangeTooWideForTrainer(span: Double, widest: Double)
}

public struct Drivetrain: Equatable, Sendable {
    /// An even ladder of twenty-four virtual ratios that belongs to no real
    /// bike. The lower half extends farther than the common 0.75-based ladder
    /// so first gear is genuinely easy without sacrificing the harder half.
    public static let virtualRatiosHundredths = [
        60, 68, 77, 88, 100, 113, 129, 146,
        165, 187, 212, 240, 261, 282, 303, 324,
        349, 374, 399, 424, 454, 484, 514, 549,
    ]

    /// Built as ratios out of one hundred rather than real teeth, because these
    /// gears are not parts anyone can buy.
    public static func virtualLadder(
        scaleRange: ClosedRange<Double> = TrainerSafety.provenScaleRange
    ) throws -> Drivetrain {
        let gears = try virtualRatiosHundredths
            .sorted()
            .map { try VirtualGear(chainring: $0, cog: 100) }
        guard let reference = centredReferenceIndex(
            of: gears,
            scaleRange: scaleRange
        ) else {
            throw DrivetrainError.rangeTooWideForTrainer(
                span: (gears.last?.ratio ?? 0) / (gears.first?.ratio ?? 1),
                widest: scaleRange.upperBound / scaleRange.lowerBound
            )
        }
        return try Drivetrain(
            chainrings: [100],
            cassetteCogs: [100],
            allowedCombinations: gears,
            referenceIndex: reference,
            validatesAgainstComponents: false
        )
    }

    /// Builds the drivetrain a rider actually described, using only the gears
    /// they would really ride.
    ///
    /// Pairing every chainring with every cog is wrong twice over. It invents
    /// badly cross-chained gears nobody uses, such as the small ring on the
    /// smallest cog, and it counts the same ratio twice: 34/17 and 50/25 both
    /// give 2.0, so on the handlebar they would be two gear numbers that feel
    /// identical. Cross-chained pairs are dropped and equal ratios are merged,
    /// which is why a 2x12 gives about sixteen gears rather than twenty-four.
    public static func build(
        chainrings: [Int],
        cassetteCogs: [Int],
        scaleRange: ClosedRange<Double> = TrainerSafety.provenScaleRange
    ) throws -> Drivetrain {
        guard !chainrings.isEmpty else {
            throw DrivetrainError.emptyChainrings
        }
        guard !cassetteCogs.isEmpty else {
            throw DrivetrainError.emptyCassette
        }
        try validateComponents(
            chainrings,
            invalid: DrivetrainError.invalidChainring,
            duplicate: DrivetrainError.duplicateChainring
        )
        try validateComponents(
            cassetteCogs,
            invalid: DrivetrainError.invalidCassetteCog,
            duplicate: DrivetrainError.duplicateCassetteCog
        )

        var combinations: [VirtualGear] = []
        let rings = chainrings.sorted()
        for (position, chainring) in rings.enumerated() {
            for cog in usableCogs(
                cassetteCogs,
                forRingAt: position,
                ringCount: rings.count
            ) {
                combinations.append(try VirtualGear(chainring: chainring, cog: cog))
            }
        }
        combinations.sort(by: gearOrder)

        var unique: [VirtualGear] = []
        for gear in combinations
        where !unique.contains(where: { hasEqualRatio($0, gear) }) {
            unique.append(gear)
        }

        guard let reference = centredReferenceIndex(
            of: unique,
            scaleRange: scaleRange
        ) else {
            throw DrivetrainError.rangeTooWideForTrainer(
                span: (unique.last?.ratio ?? 0) / (unique.first?.ratio ?? 1),
                widest: scaleRange.upperBound / scaleRange.lowerBound
            )
        }

        return try Drivetrain(
            chainrings: chainrings,
            cassetteCogs: cassetteCogs,
            allowedCombinations: unique,
            referenceIndex: reference
        )
    }

    /// The cogs a rider would really use with one chainring. The chain has to
    /// run at an angle to reach across the cassette, so a small ring is ridden
    /// on the larger cogs and a big ring on the smaller ones. Ignoring that is
    /// what produced gears like a 34 tooth ring on an 11 tooth cog, which no
    /// rider would ever choose and which made the handlebar readout describe a
    /// bike nobody owns.
    private static func usableCogs(
        _ cogs: [Int],
        forRingAt position: Int,
        ringCount: Int
    ) -> [Int] {
        guard ringCount > 1 else { return cogs }
        // Largest cog first, so index 0 is the easiest gear on the cassette.
        let ordered = cogs.sorted(by: >)
        let last = ordered.count - 1
        // The smallest ring sits at the easy end of the cassette and the
        // largest at the hard end, with any middle ring spread in between.
        let centre = Double(last)
            * Double(position) / Double(ringCount - 1)
        // Rings share the cassette, so each reaches over roughly the same span
        // regardless of how many there are; more rings simply means each covers
        // less of it and the whole drivetrain covers more ground.
        let reach = max(1.0, Double(ordered.count) * 1.2 / Double(ringCount))
        let lower = max(0, Int((centre - reach).rounded(.up)))
        let upper = min(last, Int((centre + reach).rounded(.down)))
        guard lower <= upper else { return [ordered[min(max(0, Int(centre)), last)]] }
        return Array(ordered[lower...upper])
    }

    /// The starting gear is the one the trainer's real wheel size maps onto, so
    /// every other gear is scaled away from it. The trainer accepts a limited
    /// range, and that range is lopsided: a gear can be made about 2.3 times
    /// harder than the reference but 3.2 times easier. Centring on the middle
    /// gear therefore wastes the margin, so the reference is placed where the
    /// tighter of the two ends has the most room left.
    private static func centredReferenceIndex(
        of gears: [VirtualGear],
        scaleRange: ClosedRange<Double>
    ) -> Int? {
        guard let easiest = gears.first?.ratio,
              let hardest = gears.last?.ratio,
              easiest > 0, hardest > 0
        else {
            return nil
        }
        let headroom = Foundation.log(scaleRange.upperBound)
        let legroom = -Foundation.log(scaleRange.lowerBound)
        guard headroom > 0, legroom > 0 else { return nil }

        // How much of the available room the worst end would use, as a fraction.
        // Anything above 1 does not fit.
        func worstUse(_ ratio: Double) -> Double {
            max(
                Foundation.log(hardest / ratio) / headroom,
                Foundation.log(ratio / easiest) / legroom
            )
        }

        guard let best = gears.indices.min(by: {
            worstUse(gears[$0].ratio) < worstUse(gears[$1].ratio)
        }) else {
            return nil
        }
        return worstUse(gears[best].ratio) <= 1 ? best : nil
    }

    public let chainrings: [Int]
    public let cassetteCogs: [Int]
    public let gears: [VirtualGear]
    public let referenceIndex: Int

    public init(
        chainrings: [Int],
        cassetteCogs: [Int],
        allowedCombinations: [VirtualGear],
        referenceIndex: Int? = nil,
        validatesAgainstComponents: Bool = true
    ) throws {
        guard !chainrings.isEmpty else {
            throw DrivetrainError.emptyChainrings
        }
        guard !cassetteCogs.isEmpty else {
            throw DrivetrainError.emptyCassette
        }
        guard !allowedCombinations.isEmpty else {
            throw DrivetrainError.emptyAllowedCombinations
        }

        try Self.validateComponents(
            chainrings,
            invalid: DrivetrainError.invalidChainring,
            duplicate: DrivetrainError.duplicateChainring
        )
        try Self.validateComponents(
            cassetteCogs,
            invalid: DrivetrainError.invalidCassetteCog,
            duplicate: DrivetrainError.duplicateCassetteCog
        )

        let chainringSet = Set(chainrings)
        let cassetteSet = Set(cassetteCogs)
        var combinationSet = Set<VirtualGear>()
        for (index, gear) in allowedCombinations.enumerated() {
            if validatesAgainstComponents {
                guard chainringSet.contains(gear.chainring) else {
                    throw DrivetrainError.unknownChainring(gear)
                }
                guard cassetteSet.contains(gear.cog) else {
                    throw DrivetrainError.unknownCassetteCog(gear)
                }
            }
            guard combinationSet.insert(gear).inserted else {
                throw DrivetrainError.duplicateCombination(gear)
            }
            if let duplicate = allowedCombinations[..<index].first(where: {
                Self.hasEqualRatio($0, gear)
            }) {
                throw DrivetrainError.duplicateRatio(duplicate, gear)
            }
        }
        self.chainrings = chainrings
        self.cassetteCogs = cassetteCogs
        gears = allowedCombinations.sorted(by: Self.gearOrder)
        let resolvedReference = referenceIndex ?? (gears.count - 1) / 2
        guard gears.indices.contains(resolvedReference) else {
            throw DrivetrainError.invalidReferenceIndex(resolvedReference)
        }
        self.referenceIndex = resolvedReference
    }

    public var referenceGear: VirtualGear {
        gears[referenceIndex]
    }

    private static func validateComponents(
        _ components: [Int],
        invalid: (Int) -> DrivetrainError,
        duplicate: (Int) -> DrivetrainError
    ) throws {
        var seen = Set<Int>()
        for component in components {
            guard component > 0 else {
                throw invalid(component)
            }
            guard seen.insert(component).inserted else {
                throw duplicate(component)
            }
        }
    }

    private static func gearOrder(
        _ lhs: VirtualGear,
        _ rhs: VirtualGear
    ) -> Bool {
        let lhsProduct = lhs.chainring.multipliedFullWidth(by: rhs.cog)
        let rhsProduct = rhs.chainring.multipliedFullWidth(by: lhs.cog)
        if lhsProduct.high != rhsProduct.high {
            return lhsProduct.high < rhsProduct.high
        }
        if lhsProduct.low != rhsProduct.low {
            return lhsProduct.low < rhsProduct.low
        }
        if lhs.chainring != rhs.chainring {
            return lhs.chainring < rhs.chainring
        }
        return lhs.cog < rhs.cog
    }

    private static func hasEqualRatio(
        _ lhs: VirtualGear,
        _ rhs: VirtualGear
    ) -> Bool {
        lhs.chainring.multipliedFullWidth(by: rhs.cog)
            == rhs.chainring.multipliedFullWidth(by: lhs.cog)
    }
}
