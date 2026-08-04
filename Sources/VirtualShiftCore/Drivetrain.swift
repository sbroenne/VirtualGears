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
    /// Builds the drivetrain a rider actually described: every chainring paired
    /// with every cog, ordered from easiest to hardest.
    ///
    /// Two combinations can produce the identical ratio (34/17 and 50/25 both
    /// give 2.0). On a real bike those are two positions that feel the same, and
    /// here they would be two gear numbers that do nothing, so only the first is
    /// kept. That is why a 2x12 is never 24 gears.
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
        for chainring in chainrings {
            for cog in cassetteCogs {
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
        referenceIndex: Int? = nil
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
            guard chainringSet.contains(gear.chainring) else {
                throw DrivetrainError.unknownChainring(gear)
            }
            guard cassetteSet.contains(gear.cog) else {
                throw DrivetrainError.unknownCassetteCog(gear)
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
