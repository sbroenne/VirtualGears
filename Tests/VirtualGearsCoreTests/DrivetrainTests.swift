import XCTest
@testable import VirtualGearsCore

final class DrivetrainTests: XCTestCase {
    func testUsesOnlyAllowedCombinationsAndSortsByRatio() throws {
        let easiest = try VirtualGear(chainring: 34, cog: 28)
        let middle = try VirtualGear(chainring: 34, cog: 17)
        let hardest = try VirtualGear(chainring: 50, cog: 24)
        let drivetrain = try Drivetrain(
            chainrings: [34, 50],
            cassetteCogs: [28, 24, 17],
            allowedCombinations: [
                hardest,
                easiest,
                middle,
            ]
        )

        XCTAssertEqual(drivetrain.gears, [easiest, middle, hardest])
        XCTAssertFalse(
            drivetrain.gears.contains(
                try VirtualGear(chainring: 50, cog: 28)
            )
        )
    }

    func testEqualRatiosAreRejected() throws {
        let first = try VirtualGear(chainring: 30, cog: 15)
        let second = try VirtualGear(chainring: 40, cog: 20)
        let third = try VirtualGear(chainring: 50, cog: 25)
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [50, 30, 40],
                cassetteCogs: [25, 15, 20],
                allowedCombinations: [third, second, first]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateRatio(third, second)
            )
        }
    }

    func testReferenceUsesMiddleForOddCount() throws {
        let drivetrain = try makeDrivetrain(cogs: [30, 20, 10])

        XCTAssertEqual(drivetrain.referenceIndex, 1)
        XCTAssertEqual(drivetrain.referenceGear.cog, 20)
    }

    func testReferenceUsesLowerMiddleForEvenCount() throws {
        let drivetrain = try makeDrivetrain(cogs: [30, 20, 15, 10])

        XCTAssertEqual(drivetrain.referenceIndex, 1)
        XCTAssertEqual(drivetrain.referenceGear.cog, 20)
    }

    /// The small ring belongs on the larger cogs and the big ring on the
    /// smaller ones. Pairing everything with everything invents gears such as a
    /// 34 tooth ring on an 11 tooth cog that no rider would use.
    func testBuildSkipsCrossChainedCombinations() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: [11, 17, 28]
        )

        XCTAssertEqual(
            drivetrain.gears.map { "\($0.chainring)x\($0.cog)" },
            ["34x28", "34x17", "50x17", "50x11"]
        )
        XCTAssertEqual(drivetrain.chainrings, [50, 34])
        XCTAssertEqual(drivetrain.cassetteCogs, [11, 17, 28])
    }

    /// A rider works up the cassette on the small ring, moves to the big ring,
    /// and carries on. The chainring never gets smaller as the gear gets
    /// harder, so the handlebar readout never jumps backwards between rings.
    func testBuildNeverReturnsToASmallerChainringAsGearsGetHarder() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
        )

        let rings = drivetrain.gears.map(\.chainring)
        XCTAssertEqual(rings, rings.sorted())
        XCTAssertEqual(drivetrain.gears.first.map { "\($0.chainring)x\($0.cog)" }, "34x34")
        XCTAssertEqual(drivetrain.gears.last.map { "\($0.chainring)x\($0.cog)" }, "50x11")
    }

    /// One chainring reaches the whole cassette, so nothing is dropped.
    func testBuildKeepsEveryCogOnASingleChainring() throws {
        let cogs = [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 52]
        let drivetrain = try Drivetrain.build(chainrings: [42], cassetteCogs: cogs)

        XCTAssertEqual(drivetrain.gears.count, cogs.count)
        XCTAssertEqual(drivetrain.gears.map(\.cog), cogs.sorted(by: >))
    }

    /// Two combinations can land on the identical ratio, and two gear numbers
    /// that feel the same would be two shifts that do nothing.
    func testBuildKeepsOnlyOneGearPerDistinctRatio() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 25],
            cassetteCogs: [10, 20]
        )

        XCTAssertEqual(
            drivetrain.gears.map { "\($0.chainring)x\($0.cog)" },
            ["25x20", "25x10", "50x10"]
        )
    }

    /// The trainer can be pushed about 2.3x harder than the starting gear but
    /// about 4.1x easier. There is more room downwards, so on a wide mountain setup
    /// the starting gear sits above the middle of the range, not on it.
    func testBuildPlacesStartingGearWhereBothEndsFit() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [32],
            cassetteCogs: [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51]
        )

        let reference = drivetrain.referenceGear.ratio
        let hardest = drivetrain.gears.last!.ratio
        let easiest = drivetrain.gears.first!.ratio
        XCTAssertLessThanOrEqual(
            hardest / reference,
            TrainerSafety.provenScaleRange.upperBound
        )
        XCTAssertGreaterThanOrEqual(
            easiest / reference,
            TrainerSafety.provenScaleRange.lowerBound
        )
        XCTAssertGreaterThan(
            drivetrain.referenceIndex,
            (drivetrain.gears.count - 1) / 2
        )
    }

    func testBuildRefusesARangeTheTrainerCannotCover() {
        XCTAssertThrowsError(
            try Drivetrain.build(
                chainrings: [50, 34],
                cassetteCogs: [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 52],
                scaleRange: 0.5...2
            )
        ) {
            guard case .rangeTooWideForTrainer = $0 as? DrivetrainError else {
                return XCTFail("expected a too-wide failure, got \($0)")
            }
        }
    }

    func testBuildRejectsEmptyOrRepeatedParts() {
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [], cassetteCogs: [11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .emptyChainrings)
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50], cassetteCogs: [])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .emptyCassette)
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50, 50], cassetteCogs: [11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .duplicateChainring(50))
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50], cassetteCogs: [11, 11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .duplicateCassetteCog(11))
        }
    }

    func testSupportsExplicitReferenceGear() throws {
        let drivetrain = try Drivetrain(
            chainrings: [40],
            cassetteCogs: [11, 17, 28],
            allowedCombinations: [
                try VirtualGear(chainring: 40, cog: 11),
                try VirtualGear(chainring: 40, cog: 17),
                try VirtualGear(chainring: 40, cog: 28),
            ],
            referenceIndex: 2
        )

        XCTAssertEqual(drivetrain.referenceIndex, 2)
        XCTAssertEqual(drivetrain.referenceGear.cog, 11)
    }

    func testRejectsEmptyComponentAndCombinationLists() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .emptyChainrings) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .emptyCassette) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: []
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .emptyAllowedCombinations
            )
        }
    }

    func testRejectsNonPositiveComponents() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30, 0],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .invalidChainring(0)) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20, -1],
                allowedCombinations: [gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .invalidCassetteCog(-1)
            )
        }
    }

    func testRejectsDuplicateComponentsAndCombinations() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30, 30],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .duplicateChainring(30)) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20, 20],
                allowedCombinations: [gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateCassetteCog(20)
            )
        }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [gear, gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateCombination(gear)
            )
        }
    }

    func testRejectsCombinationsAbsentFromComponents() throws {
        let unknownChainring = try VirtualGear(chainring: 40, cog: 20)
        let unknownCog = try VirtualGear(chainring: 30, cog: 10)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [unknownChainring]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .unknownChainring(unknownChainring)
            )
        }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [unknownCog]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .unknownCassetteCog(unknownCog)
            )
        }
    }

    private func makeDrivetrain(cogs: [Int]) throws -> Drivetrain {
        let gears = try cogs.map {
            try VirtualGear(chainring: 30, cog: $0)
        }
        return try Drivetrain(
            chainrings: [30],
            cassetteCogs: cogs,
            allowedCombinations: gears
        )
    }
    /// The gears a rider gets before describing any bike at all.
    func testVirtualLadderIsTwentyFourGearsInsideTheProvenRange() throws {
        let drivetrain = try Drivetrain.virtualLadder()

        XCTAssertEqual(drivetrain.gears.count, 24)
        XCTAssertEqual(drivetrain.referenceIndex, 11)
        // Judged on the value the trainer is actually sent, which is what any
        // claim about proven hardware limits can honestly cover.
        let reference = drivetrain.referenceGear.ratio
        XCTAssertEqual(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference:
                    TrainerSafety.referenceCircumferenceMillimeters,
                referenceRatio: reference,
                selectedRatio: drivetrain.gears.first!.ratio
            ),
            517.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference:
                    TrainerSafety.referenceCircumferenceMillimeters,
                referenceRatio: reference,
                selectedRatio: drivetrain.gears.last!.ratio
            ),
            4_735.125,
            accuracy: 0.001
        )
        for gear in drivetrain.gears {
            let circumference = try WheelCircumferenceScaler
                .effectiveCircumference(
                    neutralCircumference:
                        TrainerSafety.referenceCircumferenceMillimeters,
                    referenceRatio: reference,
                    selectedRatio: gear.ratio
                )
            XCTAssertTrue(
                TrainerSafety.provenCircumferenceMillimeters.contains(
                    TrainerSafety.circumferenceAsSent(circumference)
                ),
                "Virtual gear \(gear.chainring)/\(gear.cog) would ask for "
                    + "\(circumference) mm, outside the proven range"
            )
        }
        let ratios = drivetrain.gears.map(\.ratio)
        XCTAssertEqual(ratios, ratios.sorted())
    }

}
