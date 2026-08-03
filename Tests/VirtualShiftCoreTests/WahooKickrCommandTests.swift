import XCTest
@testable import VirtualShiftCore

final class WahooKickrCommandTests: XCTestCase {
    func testUnlockCommandMatchesWahooProtocol() {
        XCTAssertEqual(
            Array(WahooKickrCommand.unlock),
            [0x20, 0xEE, 0xFC]
        )
    }

    func testNeutralCircumferenceEncoding() throws {
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: 2070
        )

        XCTAssertEqual(Array(command), [0x48, 0xDC, 0x50])
    }

    func testCircumferenceRejectsOutOfRangeValue() {
        XCTAssertThrowsError(
            try WahooKickrCommand.setWheelCircumference(
                millimeters: 7000
            )
        )
    }
}

