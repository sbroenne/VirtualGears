import XCTest
@testable import VirtualShiftCore

final class DrivetrainTests: XCTestCase {
    func testUsesOnlyAllowedCombinationsAndSortsByRatio() throws {
        let easiest = try VirtualGear(chainring: 34, cog: 28)
        let equalRatioFirst = try VirtualGear(chainring: 34, cog: 17)
        let equalRatioSecond = try VirtualGear(chainring: 50, cog: 25)
        let drivetrain = try Drivetrain(
            chainrings: [34, 50],
            cassetteCogs: [28, 25, 17],
            allowedCombinations: [
                equalRatioSecond,
                easiest,
                equalRatioFirst,
            ]
        )

        XCTAssertEqual(
            drivetrain.gears,
            [easiest, equalRatioFirst, equalRatioSecond]
        )
        XCTAssertFalse(
            drivetrain.gears.contains(
                try VirtualGear(chainring: 50, cog: 28)
            )
        )
    }

    func testEqualRatiosAreRetainedWithDeterministicTieBreak() throws {
        let first = try VirtualGear(chainring: 30, cog: 15)
        let second = try VirtualGear(chainring: 40, cog: 20)
        let third = try VirtualGear(chainring: 50, cog: 25)
        let drivetrain = try Drivetrain(
            chainrings: [50, 30, 40],
            cassetteCogs: [25, 15, 20],
            allowedCombinations: [third, second, first]
        )

        XCTAssertEqual(drivetrain.gears, [first, second, third])
        XCTAssertEqual(drivetrain.gears.count, 3)
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
        try Drivetrain(
            chainrings: [30],
            cassetteCogs: cogs,
            allowedCombinations: cogs.map {
                try VirtualGear(chainring: 30, cog: $0)
            }
        )
    }
}
