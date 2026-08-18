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
    /// bike. See ``GearLadderCatalog`` for the ladders on offer.
    public static let virtualReferenceIndex = GearLadderCatalog
        .standardRange.startingIndex

    public static let virtualRatiosHundredths = GearLadderCatalog
        .standardRange.ratiosHundredths

    /// Built as ratios out of one hundred rather than real teeth, because these
    /// gears are not parts anyone can buy.
    public static func virtualLadder(
        ratiosHundredths: [Int] = GearLadderCatalog.standardRange
            .ratiosHundredths,
        startingIndex: Int = GearLadderCatalog.standardRange.startingIndex,
        scaleRange: ClosedRange<Double> = TrainerSafety.supportedScaleRange
    ) throws -> Drivetrain {
        let gears = try ratiosHundredths
            .sorted()
            .map { try VirtualGear(chainring: $0, cog: 100) }
        guard gears.indices.contains(startingIndex) else {
            throw DrivetrainError.invalidReferenceIndex(startingIndex)
        }
        let reference = startingIndex
        let referenceRatio = gears[reference].ratio
        let easiest = gears[0].ratio / referenceRatio
        let hardest = gears[gears.count - 1].ratio / referenceRatio
        guard scaleRange.contains(easiest), scaleRange.contains(hardest) else {
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

    /// The gear ratio every ride starts in.
    ///
    /// Stated, not calculated. It used to be derived: the gears were positioned
    /// wherever they best fitted inside the range the trainer was believed to
    /// accept, which meant editing an unrelated safety number moved the gear
    /// every rider starts in. Widening the riding-app wheel range from 2400 to
    /// 2600 mm shifted a compact twelve-speed rider a full ten per cent harder,
    /// silently. That range has already been changed once, to make FulGaz work.
    ///
    /// 2.40 is gear 12 of the virtual ladder and is what a 34 tooth ring on a
    /// 14 tooth cog gives — the neutral gear other virtual shifting systems
    /// settle on too. The range now only has to be wide enough to hold the
    /// gears around it.
    public static let startingRatio = 2.40

    /// How many cogs at each end of the cassette a chainring cannot reach.
    ///
    /// This is a physical answer, not a proportion of the cassette. The chain
    /// can only run at so much of an angle before it rubs, and that angle is
    /// roughly the same whether the cassette has eight cogs or thirteen. The
    /// old rule removed a fixed *fraction* of the cassette instead, so on a
    /// small cassette it deleted the very cogs that bridge the two chainrings
    /// and left a hole in the middle of the gears.
    public static let crossChainCogLimit = 2

    /// The smallest ratio change a rider can feel. Below roughly five per cent
    /// the gear number on the screen moves, a command goes out to the trainer,
    /// and the bike does nothing.
    public static let perceptibleStepFraction = 0.05

    /// Builds the gears the way an electronic groupset shifts them.
    ///
    /// A Zwift Click has exactly two buttons, so a whole two-chainring
    /// drivetrain has to collapse into one sequence. Shimano and SRAM already
    /// solved that problem — Synchronized Shift and AXS Sequential — and this
    /// copies their answer rather than inventing one: start on the small ring
    /// and the largest cog, move one cog per press, and at the shift point
    /// change chainring *and* jump the cassette by a compensating amount so the
    /// change feels like a normal cassette step.
    ///
    /// The previous approach paired every chainring with every cog, sorted the
    /// pile by ratio, pruned the cross-chained pairs and dropped exact
    /// duplicates. Measured across the seventy-two builds of the groupsets this
    /// app ships, that produced a shift too small to feel on twelve of them —
    /// the smallest was 0.4% — and a hole wider than a quarter on five. Walking
    /// the drivetrain instead removes both causes rather than patching them: a
    /// walk cannot invent a hole, and it cannot take a step smaller than the
    /// transition rule allows.
    public static func build(
        chainrings: [Int],
        cassetteCogs: [Int],
        scaleRange: ClosedRange<Double> = TrainerSafety.supportedScaleRange
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
        for pair in synchronisedSequence(
            rings: chainrings.sorted(),
            cogs: cassetteCogs.sorted(by: >)
        ) {
            combinations.append(
                try VirtualGear(chainring: pair.chainring, cog: pair.cog)
            )
        }

        guard let reference = startingGearIndex(
            of: combinations,
            scaleRange: scaleRange
        ) else {
            throw DrivetrainError.rangeTooWideForTrainer(
                span: (combinations.last?.ratio ?? 0)
                    / (combinations.first?.ratio ?? 1),
                widest: scaleRange.upperBound / scaleRange.lowerBound
            )
        }

        return try Drivetrain(
            chainrings: chainrings,
            cassetteCogs: cassetteCogs,
            allowedCombinations: combinations,
            referenceIndex: reference
        )
    }

    /// One press of the shift button, one step along here.
    ///
    /// Chainrings arrive smallest first and cogs largest first, so the walk
    /// starts at the easiest gear anyone would ride and finishes at the hardest.
    /// Every step is strictly harder than the one before, which is what makes a
    /// two-button controller make sense.
    static func synchronisedSequence(
        rings: [Int],
        cogs: [Int]
    ) -> [(chainring: Int, cog: Int)] {
        guard let firstRing = rings.first, !cogs.isEmpty else { return [] }
        guard rings.count > 1 else {
            return cogs.map { (chainring: firstRing, cog: $0) }
        }

        let last = cogs.count - 1
        // Never ban so much of a small cassette that a chainring loses the cogs
        // that bridge it to the next one — that is the mistake the old
        // proportional rule made, only inverted.
        let limit = min(min(crossChainCogLimit, max(1, cogs.count / 4)), last)

        // Which part of the cassette each chainring is allowed to reach. The
        // smallest ring keeps the easy end, the largest keeps the hard end, and
        // neither is allowed near the other's corner — that is what stops
        // small-small and big-big appearing.
        func window(forRingAt position: Int) -> ClosedRange<Int> {
            let lower = position == 0 ? 0 : limit
            let upper = position == rings.count - 1 ? last : last - limit
            return lower...max(lower, upper)
        }

        func ratio(_ position: Int, _ cogIndex: Int) -> Double {
            Double(rings[position]) / Double(cogs[cogIndex])
        }

        var sequence: [(ring: Int, cog: Int)] = [(0, 0)]
        var ring = 0
        var cog = 0

        while true {
            // Still cogs left on this chainring: take one.
            if cog + 1 <= window(forRingAt: ring).upperBound {
                cog += 1
                sequence.append((ring, cog))
                continue
            }

            // Out of cassette. Change chainring, and land on the cog that makes
            // the change feel like the cassette step just taken. This is the
            // compensating rear shift a real electronic groupset pairs with
            // every front change.
            let current = ratio(ring, cog)
            let wanted = cog > 0 ? current / ratio(ring, cog - 1) : 1.10
            var moved = false

            for next in (ring + 1)..<rings.count {
                var landing: Int?
                var closest = Double.infinity
                for candidate in window(forRingAt: next) {
                    let step = ratio(next, candidate) / current
                    // A step nobody can feel is not a gear.
                    guard step >= 1 + perceptibleStepFraction else { continue }
                    let error = abs(Foundation.log(step / wanted))
                    if error < closest {
                        closest = error
                        landing = candidate
                    }
                }
                guard let landing else { continue }
                ring = next
                cog = landing
                sequence.append((ring, cog))
                moved = true
                break
            }

            if !moved { break }
        }

        return sequence.map { (chainring: rings[$0.ring], cog: cogs[$0.cog]) }
    }

    /// The gear the ride starts in: the one nearest ``startingRatio`` whose
    /// whole ladder the trainer can still cover. Declared rather than derived,
    /// so editing an unrelated safety number cannot move it.
    static func startingGearIndex(
        of gears: [VirtualGear],
        scaleRange: ClosedRange<Double>
    ) -> Int? {
        guard let easiest = gears.first?.ratio,
              let hardest = gears.last?.ratio,
              easiest > 0, hardest > 0
        else {
            return nil
        }

        func fits(_ ratio: Double) -> Bool {
            scaleRange.contains(easiest / ratio)
                && scaleRange.contains(hardest / ratio)
        }

        func distance(_ ratio: Double) -> Double {
            abs(Foundation.log(ratio / startingRatio))
        }

        return gears.indices
            .filter { fits(gears[$0].ratio) }
            .min { distance(gears[$0].ratio) < distance(gears[$1].ratio) }
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
