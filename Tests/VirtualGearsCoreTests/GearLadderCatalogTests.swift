import XCTest
@testable import VirtualGearsCore

/// `GearLadderCatalog.custom(_:)` is what turns a rider's own gear count and
/// range into the same evenly-spaced-ratio shape as the one built-in ladder,
/// so these tests exist to pin down the maths a rider cannot see: the count,
/// the ordering, the endpoints and where the ride starts.
final class GearLadderCatalogTests: XCTestCase {
    func testCustomBuildsTheRequestedGearCount() {
        let ladder = GearLadderCatalog.custom(
            CustomGearLadder(
                gearCount: 10,
                easiestRatioHundredths: 100,
                hardestRatioHundredths: 200
            )
        )
        XCTAssertEqual(ladder.gearCount, 10)
        XCTAssertEqual(ladder.ratiosHundredths.count, 10)
    }

    func testCustomRatiosAreEvenlySpacedFromEasiestToHardest() {
        let ladder = GearLadderCatalog.custom(
            CustomGearLadder(
                gearCount: 5,
                easiestRatioHundredths: 100,
                hardestRatioHundredths: 500
            )
        )
        XCTAssertEqual(ladder.ratiosHundredths, [100, 200, 300, 400, 500])
    }

    /// A rider could type the easiest and hardest numbers the wrong way
    /// round. The ladder should still come out easiest-first rather than
    /// building a descending, unrideable list.
    func testCustomSortsEasiestAndHardestRegardlessOfInputOrder() {
        let ladder = GearLadderCatalog.custom(
            CustomGearLadder(
                gearCount: 5,
                easiestRatioHundredths: 500,
                hardestRatioHundredths: 100
            )
        )
        XCTAssertEqual(ladder.ratiosHundredths, [100, 200, 300, 400, 500])
    }

    /// The starting gear should sit at the same fractional position the
    /// built-in ladder starts at (roughly the middle, slightly toward the
    /// easy side), not always at one fixed index regardless of gear count.
    func testCustomStartingIndexScalesWithGearCount() {
        let twelve = GearLadderCatalog.custom(
            CustomGearLadder(
                gearCount: 12,
                easiestRatioHundredths: 100,
                hardestRatioHundredths: 300
            )
        )
        let twentyFour = GearLadderCatalog.custom(
            CustomGearLadder(
                gearCount: 24,
                easiestRatioHundredths: 100,
                hardestRatioHundredths: 300
            )
        )
        XCTAssertEqual(twentyFour.startingIndex, GearLadderCatalog.standardRange.startingIndex)
        XCTAssertLessThan(twelve.startingIndex, twelve.gearCount)
        XCTAssertGreaterThanOrEqual(twelve.startingIndex, 0)
        // Roughly proportional: the fraction should be close between sizes.
        let fractionTwelve = Double(twelve.startingIndex) / Double(twelve.gearCount - 1)
        let fractionTwentyFour = Double(twentyFour.startingIndex) / Double(twentyFour.gearCount - 1)
        XCTAssertEqual(fractionTwelve, fractionTwentyFour, accuracy: 0.1)
    }

    /// A drivetrain still has to be buildable from the generated ratios — the
    /// same guarantee every built-in ladder gives.
    func testCustomLadderBuildsARideableDrivetrain() throws {
        let ladder = GearLadderCatalog.custom(.default)
        let drivetrain = try ladder.drivetrain()
        XCTAssertEqual(drivetrain.gears.count, 24)
    }

    func testCustomLadderIDIsReservedAndNeverMatchesABuiltInLadder() {
        XCTAssertFalse(
            GearLadderCatalog.ladders.contains {
                $0.id == GearLadderCatalog.customLadderID
            }
        )
    }
}
