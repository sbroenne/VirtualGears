import Foundation
import XCTest
@testable import VirtualGearsCore

final class FTMSIndoorBikeDataTests: XCTestCase {
    func testKnownFieldsAndSignedValuesRoundTrip() throws {
        let value = IndoorBikeData(
            instantaneousSpeedHundredths: 3_250,
            instantaneousCadenceHalfRPM: 181,
            resistanceLevel: -15,
            instantaneousPowerWatts: -250,
            heartRateBPM: 155,
            elapsedTimeSeconds: 3_600
        )
        let bytes: [UInt8] = [
            0x64, 0x0A, 0xB2, 0x0C, 0xB5, 0x00, 0xF1, 0xFF,
            0x06, 0xFF, 0x9B, 0x10, 0x0E,
        ]

        XCTAssertEqual(Array(value.encode()), bytes)
        let decoded = try IndoorBikeData.decode(Data(bytes))
        XCTAssertEqual(decoded.instantaneousSpeedHundredths, 3_250)
        XCTAssertEqual(decoded.instantaneousSpeedKilometersPerHour, 32.5)
        XCTAssertEqual(decoded.instantaneousCadenceHalfRPM, 181)
        XCTAssertEqual(decoded.instantaneousCadenceRPM, 90.5)
        XCTAssertEqual(decoded.resistanceLevel, -15)
        XCTAssertEqual(decoded.instantaneousPowerWatts, -250)
        XCTAssertEqual(decoded.heartRateBPM, 155)
        XCTAssertEqual(decoded.elapsedTimeSeconds, 3_600)
        XCTAssertEqual(decoded.encode(), Data(bytes))
    }

    func testMoreDataBitMeansSpeedIsAbsent() throws {
        let decoded = try IndoorBikeData.decode(Data([0x01, 0x00]))
        XCTAssertNil(decoded.instantaneousSpeedHundredths)
        XCTAssertEqual(decoded.encode(), Data([0x01, 0x00]))
    }

    func testPreservesEveryStandardOptionalField() throws {
        let bytes: [UInt8] = [
            0xFF, 0x1F,
            1, 0, 2, 0, 3, 0, 4, 0,
            0, 5, 0, 6, 0, 7, 0,
            8, 0, 9, 0, 10,
            11, 12, 13, 0, 14, 0,
        ]
        let decoded = try IndoorBikeData.decode(Data(bytes))
        XCTAssertEqual(decoded.instantaneousCadenceHalfRPM, 2)
        XCTAssertEqual(decoded.resistanceLevel, 5)
        XCTAssertEqual(decoded.instantaneousPowerWatts, 6)
        XCTAssertEqual(decoded.heartRateBPM, 11)
        XCTAssertEqual(decoded.elapsedTimeSeconds, 13)
        XCTAssertEqual(decoded.encode(), Data(bytes))
    }

    func testRejectsMissingFlagsSpeedAndOptionalFields() {
        XCTAssertThrowsError(try IndoorBikeData.decode(Data()))
        XCTAssertThrowsError(try IndoorBikeData.decode(Data([0, 0, 1])))
        XCTAssertThrowsError(
            try IndoorBikeData.decode(Data([0x05, 0x00, 0x20]))
        )
        XCTAssertThrowsError(
            try IndoorBikeData.decode(Data([0x01, 0x02]))
        )
    }
}
