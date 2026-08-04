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
    case emptyVirtualRatios
    case invalidVirtualRatio(Int)
    case duplicateVirtualRatio(Int)
}

public struct Drivetrain: Equatable, Sendable {
    public static let zwiftVirtual24RatiosHundredths = [
        75, 87, 99, 111, 123, 138, 153, 168,
        186, 204, 222, 240, 261, 282, 303, 324,
        349, 374, 399, 424, 454, 484, 514, 549,
    ]

    public static var zwiftVirtual24: Drivetrain {
        try! Drivetrain(
            virtualRatiosHundredths: zwiftVirtual24RatiosHundredths
        )
    }

    public let chainrings: [Int]
    public let cassetteCogs: [Int]
    public let gears: [VirtualGear]

    public init(
        chainrings: [Int],
        cassetteCogs: [Int],
        allowedCombinations: [VirtualGear]
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
    }

    public init(virtualRatiosHundredths: [Int]) throws {
        guard !virtualRatiosHundredths.isEmpty else {
            throw DrivetrainError.emptyVirtualRatios
        }

        var seen = Set<Int>()
        for ratio in virtualRatiosHundredths {
            guard ratio > 0 else {
                throw DrivetrainError.invalidVirtualRatio(ratio)
            }
            guard seen.insert(ratio).inserted else {
                throw DrivetrainError.duplicateVirtualRatio(ratio)
            }
        }

        chainrings = []
        cassetteCogs = []
        gears = try virtualRatiosHundredths.enumerated().map {
            try VirtualGear(
                virtualNumber: $0.offset + 1,
                ratioHundredths: $0.element
            )
        }
    }

    public var usesNumberedGears: Bool {
        gears.first?.virtualNumber != nil
    }

    public var referenceIndex: Int {
        (gears.count - 1) / 2
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
