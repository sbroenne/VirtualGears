import XCTest
@testable import VirtualShiftCore

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

    func testCreatesNumberedVirtualDrivetrainWithLowerMiddleReference() throws {
        let drivetrain = try Drivetrain(
            virtualRatiosHundredths: [75, 87, 99, 111]
        )

        XCTAssertTrue(drivetrain.usesNumberedGears)
        XCTAssertEqual(drivetrain.gears.map(\.virtualNumber), [1, 2, 3, 4])
        XCTAssertEqual(drivetrain.gears.map(\.ratio), [0.75, 0.87, 0.99, 1.11])
        XCTAssertEqual(drivetrain.referenceIndex, 1)
        XCTAssertEqual(drivetrain.referenceGear.virtualNumber, 2)
        XCTAssertTrue(drivetrain.chainrings.isEmpty)
        XCTAssertTrue(drivetrain.cassetteCogs.isEmpty)
    }

    func testZwiftVirtual24UsesPublishedRatiosAndGear12Reference() {
        let drivetrain = Drivetrain.zwiftVirtual24

        XCTAssertEqual(drivetrain.gears.count, 24)
        XCTAssertEqual(
            drivetrain.gears.map { Int(($0.ratio * 100).rounded()) },
            Drivetrain.zwiftVirtual24RatiosHundredths
        )
        XCTAssertEqual(drivetrain.referenceIndex, 11)
        XCTAssertEqual(drivetrain.referenceGear.virtualNumber, 12)
        XCTAssertEqual(drivetrain.referenceGear.ratio, 2.40, accuracy: 0.000_001)
    }

    func testRejectsInvalidNumberedVirtualRatios() {
        XCTAssertThrowsError(
            try Drivetrain(virtualRatiosHundredths: [])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .emptyVirtualRatios)
        }
        XCTAssertThrowsError(
            try Drivetrain(virtualRatiosHundredths: [75, 0])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .invalidVirtualRatio(0))
        }
        XCTAssertThrowsError(
            try Drivetrain(virtualRatiosHundredths: [75, 87, 75])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .duplicateVirtualRatio(75))
        }
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
}
