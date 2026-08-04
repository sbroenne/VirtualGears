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
    case unknownReferenceGear(VirtualGear)
}

public struct Drivetrain: Equatable, Sendable {
    public let chainrings: [Int]
    public let cassetteCogs: [Int]
    public let gears: [VirtualGear]
    public let referenceIndex: Int

    public init(
        chainrings: [Int],
        cassetteCogs: [Int],
        allowedCombinations: [VirtualGear],
        referenceGear: VirtualGear
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
        guard combinationSet.contains(referenceGear) else {
            throw DrivetrainError.unknownReferenceGear(referenceGear)
        }

        self.chainrings = chainrings
        self.cassetteCogs = cassetteCogs
        gears = allowedCombinations.sorted(by: Self.gearOrder)
        referenceIndex = gears.firstIndex(of: referenceGear)!
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
