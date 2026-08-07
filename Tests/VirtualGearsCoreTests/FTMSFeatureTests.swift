import Foundation
import XCTest
@testable import VirtualGearsCore

final class FTMSFeatureTests: XCTestCase {
    func testUUIDs() {
        XCTAssertEqual(FTMSUUID.fitnessMachineService, "1826")
        XCTAssertEqual(FTMSUUID.fitnessMachineFeature, "2ACC")
        XCTAssertEqual(FTMSUUID.indoorBikeData, "2AD2")
        XCTAssertEqual(FTMSUUID.supportedResistanceLevelRange, "2AD6")
        XCTAssertEqual(FTMSUUID.supportedPowerRange, "2AD8")
        XCTAssertEqual(FTMSUUID.fitnessMachineControlPoint, "2AD9")
        XCTAssertEqual(FTMSUUID.fitnessMachineStatus, "2ADA")
    }

    func testFeatureKnownBytesAndRoundTrip() throws {
        let feature = FitnessMachineFeature(
            machineFeatures: [
                .cadence, .resistanceLevel, .powerMeasurement,
            ],
            targetSettingFeatures: [
                .resistanceLevel, .power,
                .indoorBikeSimulationParameters, .wheelCircumference,
            ]
        )

        XCTAssertEqual(
            Array(feature.encode()),
            [0x82, 0x40, 0x00, 0x00, 0x0C, 0x60, 0x00, 0x00]
        )
        XCTAssertEqual(
            try FitnessMachineFeature.decode(feature.encode()),
            feature
        )
    }

    func testFeaturePreservesUnknownFlagsAndRejectsWrongLength() throws {
        let data = Data([0, 0, 0, 0x80, 0, 0, 0, 0x80])
        XCTAssertEqual(
            try FitnessMachineFeature.decode(data).encode(),
            data
        )
        XCTAssertThrowsError(
            try FitnessMachineFeature.decode(Data(repeating: 0, count: 7))
        )
    }

    /// A riding app must be able to classify Virtual Gears as a controllable
    /// trainer, which means declaring the standard trainer capabilities, while
    /// still refusing an actual power target because gears are the rider's job.
    func testVirtualTrainerProfileLooksLikeATrainerButRefusesERG() {
        XCTAssertEqual(
            Array(VirtualTrainerFTMSProfile.feature.encode()),
            [0x82, 0x50, 0x00, 0x00, 0x0C, 0x60, 0x00, 0x00]
        )
        XCTAssertTrue(
            VirtualTrainerFTMSProfile.feature.targetSettingFeatures.contains(.power)
        )
        XCTAssertTrue(
            VirtualTrainerFTMSProfile.feature.targetSettingFeatures
                .contains(.indoorBikeSimulationParameters)
        )
        XCTAssertEqual(
            Array(VirtualTrainerFTMSProfile.powerRange.encode()),
            [0x00, 0x00, 0xD0, 0x07, 0x01, 0x00]
        )
        XCTAssertFalse(
            VirtualTrainerFTMSProfile.supports(.setTargetPower(watts: 250))
        )
        XCTAssertTrue(
            VirtualTrainerFTMSProfile.supports(
                .setIndoorBikeSimulationParameters(.init(
                    windSpeedThousandthsMetersPerSecond: 0,
                    gradeHundredthsPercent: 500,
                    rollingResistanceCoefficientTenThousandths: 33,
                    windResistanceCoefficientHundredthsKilogramsPerMeter: 35
                ))
            )
        )
    }

    func testPowerRangeSignedRoundTripAndValidation() throws {
        let range = try SupportedPowerRange(
            minimumWatts: -100,
            maximumWatts: 2_000,
            incrementWatts: 5
        )
        XCTAssertEqual(
            Array(range.encode()),
            [0x9C, 0xFF, 0xD0, 0x07, 0x05, 0x00]
        )
        XCTAssertEqual(try .decode(range.encode()), range)
        XCTAssertThrowsError(
            try SupportedPowerRange(
                minimumWatts: 10,
                maximumWatts: 0,
                incrementWatts: 1
            )
        )
        XCTAssertThrowsError(
            try SupportedPowerRange(
                minimumWatts: 0,
                maximumWatts: 10,
                incrementWatts: 0
            )
        )
    }

    func testResistanceRangeSignedRoundTripAndValidation() throws {
        let range = try SupportedResistanceLevelRange(
            minimumTenths: -50,
            maximumTenths: 1_000,
            incrementTenths: 5
        )
        XCTAssertEqual(range.minimum, -5)
        XCTAssertEqual(range.maximum, 100)
        XCTAssertEqual(Array(range.encode()), [0xCE, 0xFF, 0xE8, 3, 5, 0])
        XCTAssertEqual(try .decode(range.encode()), range)
        XCTAssertThrowsError(
            try SupportedResistanceLevelRange(
                minimumTenths: 1,
                maximumTenths: 0,
                incrementTenths: 1
            )
        )
        XCTAssertThrowsError(
            try SupportedResistanceLevelRange(
                minimumTenths: 0,
                maximumTenths: 1,
                incrementTenths: 0
            )
        )
    }

    func testByteCodecReportsExactFailureLocation() {
        var reader = FTMSByteReader(Data([0x01]))
        XCTAssertThrowsError(try reader.readUInt16()) { error in
            XCTAssertEqual(
                error as? FTMSCodecError,
                .insufficientBytes(offset: 0, expected: 2, available: 1)
            )
        }
        var writer = FTMSByteWriter()
        XCTAssertThrowsError(try writer.writeUInt24(0x0100_0000))
    }
}
