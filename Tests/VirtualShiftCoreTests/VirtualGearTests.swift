import XCTest
@testable import VirtualShiftCore

final class VirtualGearTests: XCTestCase {
    func testGearRatioUsesChainringDividedByCog() throws {
        let gear = try VirtualGear(chainring: 31, cog: 17)

        XCTAssertEqual(gear.ratio, 31.0 / 17.0, accuracy: 0.000_001)
    }

    func testReferenceGearKeepsNeutralCircumference() throws {
        let reference = try VirtualGear(chainring: 31, cog: 17)
        let circumference = try WheelCircumferenceScaler.effectiveCircumference(
            neutralCircumference: 2070,
            referenceRatio: reference.ratio,
            selectedRatio: reference.ratio
        )

        XCTAssertEqual(circumference, 2070, accuracy: 0.000_001)
    }

    func testHigherRatioProducesLargerCircumference() throws {
        let reference = try VirtualGear(chainring: 31, cog: 17)
        let harder = try VirtualGear(chainring: 48, cog: 17)
        let circumference = try WheelCircumferenceScaler.effectiveCircumference(
            neutralCircumference: 2070,
            referenceRatio: reference.ratio,
            selectedRatio: harder.ratio
        )

        XCTAssertGreaterThan(circumference, 2070)
    }

    func testInvalidGearIsRejected() {
        XCTAssertThrowsError(try VirtualGear(chainring: 0, cog: 17))
    }

    func testNumberedGearUsesPublishedRatio() throws {
        let drivetrain = try Drivetrain(
            virtualRatiosHundredths: [75, 240, 549]
        )

        XCTAssertEqual(drivetrain.gears[0].virtualNumber, 1)
        XCTAssertEqual(drivetrain.gears[0].ratio, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(drivetrain.gears[1].virtualNumber, 2)
        XCTAssertEqual(drivetrain.gears[1].ratio, 2.40, accuracy: 0.000_001)
        XCTAssertEqual(drivetrain.gears[2].virtualNumber, 3)
        XCTAssertEqual(drivetrain.gears[2].ratio, 5.49, accuracy: 0.000_001)
    }

    func testScalerRejectsCircumferenceOutsideWahooBounds() {
        XCTAssertThrowsError(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference:
                    WahooKickrCommand.maximumCircumferenceMillimeters,
                referenceRatio: 1,
                selectedRatio: 2
            )
        )
        XCTAssertThrowsError(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference: .leastNonzeroMagnitude,
                referenceRatio: .greatestFiniteMagnitude,
                selectedRatio: .leastNonzeroMagnitude
            )
        )
    }
}
