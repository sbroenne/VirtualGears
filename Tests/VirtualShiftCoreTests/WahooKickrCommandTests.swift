import XCTest
@testable import VirtualShiftCore

final class WahooKickrCommandTests: XCTestCase {
    func testUnlockCommandMatchesWahooProtocol() {
        XCTAssertEqual(
            Array(WahooKickrCommand.unlock),
            [0x20, 0xEE, 0xFC]
        )
    }

    func testUnlockResponseVerifiesUnlockCommand() throws {
        let response = try WahooKickrResponse.decode(
            Data([0x01, 0x20, 0x02])
        )

        XCTAssertEqual(response, .unlock(result: 0x02))
        XCTAssertTrue(response.verifies(command: WahooKickrCommand.unlock))
    }

    func testCircumferenceResponseVerifiesExactValue() throws {
        let response = try WahooKickrResponse.decode(
            Data([0x01, 0x48, 0x01, 0x00, 0x54, 0x3D])
        )
        let matching = try WahooKickrCommand.setWheelCircumference(
            millimeters: 1570
        )
        let different = try WahooKickrCommand.setWheelCircumference(
            millimeters: 2070
        )

        XCTAssertEqual(
            response,
            .wheelCircumference(
                result: 0x0001,
                encodedTenthsOfMillimeter: 15700
            )
        )
        XCTAssertTrue(response.verifies(command: matching))
        XCTAssertFalse(response.verifies(command: different))
    }

    func testResponsesRequireSuccessfulResult() throws {
        XCTAssertTrue(
            WahooKickrResponse.unlock(result: 2)
                .confirmsSuccess(for: WahooKickrCommand.unlock)
        )
        XCTAssertFalse(
            WahooKickrResponse.unlock(result: 1)
                .confirmsSuccess(for: WahooKickrCommand.unlock)
        )
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: 2_070
        )
        XCTAssertTrue(
            WahooKickrResponse.wheelCircumference(
                result: 1,
                encodedTenthsOfMillimeter: 20_700
            ).confirmsSuccess(for: command)
        )
        XCTAssertFalse(
            WahooKickrResponse.wheelCircumference(
                result: 0,
                encodedTenthsOfMillimeter: 20_700
            ).confirmsSuccess(for: command)
        )
    }

    func testResponseRejectsMalformedOrUnknownData() {
        XCTAssertThrowsError(
            try WahooKickrResponse.decode(Data([0x01, 0x48, 0x01]))
        )
        XCTAssertThrowsError(
            try WahooKickrResponse.decode(Data([0x01, 0x99, 0x00]))
        )
    }

    func testNeutralCircumferenceEncoding() throws {
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: 2070
        )

        XCTAssertEqual(Array(command), [0x48, 0xDC, 0x50])
    }

    func testDefaultProofValuesHaveExpectedEncoding() throws {
        let values = try WahooKickrProofValues(
            baseline: WahooKickrProofValues.defaultBaseline
        )
        let expected: [WahooKickrProofSelection: [UInt8]] = [
            .easier: [0x48, 0x54, 0x3D],
            .baseline: [0x48, 0xDC, 0x50],
            .harder: [0x48, 0x64, 0x64],
        ]

        for selection in WahooKickrProofSelection.allCases {
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: values[selection]
            )
            XCTAssertEqual(Array(command), expected[selection])
        }
    }

    func testProofValuesAreDerivedFromConfirmedBaseline() throws {
        let values = try WahooKickrProofValues(baseline: 2000)

        XCTAssertEqual(values.easier, 1500)
        XCTAssertEqual(values.baseline, 2000)
        XCTAssertEqual(values.harder, 2500)
    }

    func testProofValuesRejectUnsafeBaseline() {
        XCTAssertThrowsError(try WahooKickrProofValues(baseline: 500))
        XCTAssertThrowsError(try WahooKickrProofValues(baseline: 6100))
        XCTAssertThrowsError(try WahooKickrProofValues(baseline: .nan))
    }

    func testCircumferenceAcceptsEncoderBoundaries() throws {
        XCTAssertNoThrow(
            try WahooKickrCommand.setWheelCircumference(millimeters: 0)
        )
        XCTAssertNoThrow(
            try WahooKickrCommand.setWheelCircumference(
                millimeters: Double(UInt16.max) / 10
            )
        )
    }

    func testCircumferenceRejectsOutOfRangeValue() {
        for value in [-1, 7000, .infinity, .nan] {
            XCTAssertThrowsError(
                try WahooKickrCommand.setWheelCircumference(
                    millimeters: value
                )
            )
        }
    }
}
