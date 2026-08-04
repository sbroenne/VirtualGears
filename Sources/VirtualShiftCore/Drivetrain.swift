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
    case invalidReferenceIndex(Int)
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

    public static var shimanoRoad2x12: Drivetrain {
        let cassette = [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
        return try! Drivetrain(
            chainrings: [34, 50],
            cassetteCogs: cassette,
            allowedCombinations:
                makeGears(chainring: 34, cogs: [15, 17, 19, 21, 24, 27, 30, 34])
                + makeGears(chainring: 50, cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24])
        )
    }

    public static var sramRoadAxs2x12: Drivetrain {
        let cassette = [10, 11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 33]
        return try! Drivetrain(
            chainrings: [33, 46],
            cassetteCogs: cassette,
            allowedCombinations:
                makeGears(chainring: 33, cogs: [15, 17, 19, 21, 24, 28, 33])
                + makeGears(chainring: 46, cogs: [10, 11, 12, 13, 14, 15, 17, 19, 21])
        )
    }

    public static var shimanoGrx2x12: Drivetrain {
        let cassette = [11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 32, 36]
        return try! Drivetrain(
            chainrings: [31, 48],
            cassetteCogs: cassette,
            allowedCombinations:
                makeGears(chainring: 31, cogs: [15, 17, 19, 21, 24, 28, 32, 36])
                + makeGears(chainring: 48, cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24])
        )
    }

    public static var sramXplr1x12: Drivetrain {
        makeOneBy(
            chainring: 40,
            cassette: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 35, 44]
        )
    }

    public static var sramXplr1x13: Drivetrain {
        makeOneBy(
            chainring: 44,
            cassette: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 32, 38, 46]
        )
    }

    public static var campagnoloEkar1x13: Drivetrain {
        makeOneBy(
            chainring: 40,
            cassette: [9, 10, 11, 12, 13, 14, 16, 18, 20, 23, 27, 34, 42]
        )
    }

    public static var campagnoloRoad2x12: Drivetrain {
        let cassette = [10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 24, 27]
        return try! Drivetrain(
            chainrings: [29, 45],
            cassetteCogs: cassette,
            allowedCombinations:
                makeGears(chainring: 29, cogs: [14, 15, 16, 17, 19, 21, 24, 27])
                + makeGears(chainring: 45, cogs: [10, 11, 12, 13, 14, 15, 16, 17])
        )
    }

    public static var shimanoRoad2x11: Drivetrain {
        let cassette = [11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 32]
        return try! Drivetrain(
            chainrings: [34, 50],
            cassetteCogs: cassette,
            allowedCombinations:
                makeGears(chainring: 34, cogs: [15, 17, 19, 21, 24, 28, 32])
                + makeGears(chainring: 50, cogs: [11, 12, 13, 14, 15, 17, 19, 21])
        )
    }

    public static var mountain1x11: Drivetrain {
        makeOneBy(
            chainring: 32,
            cassette: [11, 13, 15, 17, 19, 21, 24, 28, 32, 37, 46]
        )
    }

    public static var mountain1x12: Drivetrain {
        makeOneBy(
            chainring: 32,
            cassette: [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51],
            referenceIndex: 6
        )
    }

    public static var classic1x10: Drivetrain {
        makeOneBy(
            chainring: 42,
            cassette: [11, 13, 15, 18, 21, 24, 28, 32, 36, 42]
        )
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

    public init(
        virtualRatiosHundredths: [Int],
        referenceIndex: Int? = nil
    ) throws {
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
        let resolvedReference = referenceIndex ?? (gears.count - 1) / 2
        guard gears.indices.contains(resolvedReference) else {
            throw DrivetrainError.invalidReferenceIndex(resolvedReference)
        }
        self.referenceIndex = resolvedReference
    }

    public var usesNumberedGears: Bool {
        gears.first?.virtualNumber != nil
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

    private static func makeOneBy(
        chainring: Int,
        cassette: [Int],
        referenceIndex: Int? = nil
    ) -> Drivetrain {
        try! Drivetrain(
            chainrings: [chainring],
            cassetteCogs: cassette,
            allowedCombinations: makeGears(
                chainring: chainring,
                cogs: cassette
            ),
            referenceIndex: referenceIndex
        )
    }

    private static func makeGears(
        chainring: Int,
        cogs: [Int]
    ) -> [VirtualGear] {
        cogs.map { try! VirtualGear(chainring: chainring, cog: $0) }
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
