import XCTest
@testable import VirtualGearsCore

final class HeadwindProtocolTests: XCTestCase {
    func testEveryModeDescribesItsControlBehavior() {
        let expectations: [(HeadwindMode, String, Bool)] = [
            (.off, "Off", false),
            (.heartRate, "Heart-rate sensor", true),
            (.speed, "Speed sensor", true),
            (.manual, "Manual", false),
            (.sleep, "Sleeping", false),
        ]

        for (mode, label, isSensorControlled) in expectations {
            XCTAssertEqual(mode.label, label)
            XCTAssertEqual(mode.isSensorControlled, isSensorControlled)
        }
    }

    func testEncodesEveryModeCommand() throws {
        XCTAssertEqual(
            Array(try HeadwindCommand.setMode(.heartRate).encode()),
            [0x04, 0x02, 0x00, 0x00]
        )
        XCTAssertEqual(
            Array(try HeadwindCommand.setMode(.speed).encode()),
            [0x04, 0x03, 0x00, 0x00]
        )
        XCTAssertEqual(
            Array(try HeadwindCommand.setMode(.manual).encode()),
            [0x04, 0x04, 0x00, 0x00]
        )
    }

    func testEncodesTheCompleteManualSpeedRange() throws {
        XCTAssertEqual(
            Array(try HeadwindCommand.setManualSpeed(0).encode()),
            [0x02, 0x00, 0x00, 0x00]
        )
        XCTAssertEqual(
            Array(try HeadwindCommand.setManualSpeed(100).encode()),
            [0x02, 0x64, 0x00, 0x00]
        )
    }

    func testRejectsAnInvalidManualSpeed() {
        XCTAssertThrowsError(try HeadwindCommand.setManualSpeed(-1).encode()) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .invalidSpeed(-1))
        }
        XCTAssertThrowsError(try HeadwindCommand.setManualSpeed(101).encode()) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .invalidSpeed(101))
        }
    }

    func testDecodesStateAndAcknowledgements() throws {
        XCTAssertEqual(
            try HeadwindMessageDecoder.decode(Data([0xFD, 0x01, 75, 0x04])),
            .state(mode: .manual, manualSpeed: 75)
        )
        XCTAssertEqual(
            try HeadwindMessageDecoder.decode(Data([0xFE, 0x04, 0x01, 0x02])),
            .modeAcknowledged(.heartRate, succeeded: true)
        )
        XCTAssertEqual(
            try HeadwindMessageDecoder.decode(Data([0xFE, 0x02, 0x01, 50])),
            .speedAcknowledged(50, succeeded: true)
        )
    }

    func testRejectsUnknownAndTruncatedMessages() {
        XCTAssertThrowsError(
            try HeadwindMessageDecoder.decode(Data([0xFD, 0x01, 0x00]))
        ) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .malformedMessage)
        }
        XCTAssertThrowsError(
            try HeadwindMessageDecoder.decode(Data([0xFD, 0x01, 0x00, 0xFF]))
        ) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .unknownMode(0xFF))
        }
        XCTAssertThrowsError(
            try HeadwindMessageDecoder.decode(Data([0xFE, 0x04, 0x01, 0xFF]))
        ) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .unknownMode(0xFF))
        }
        XCTAssertThrowsError(
            try HeadwindMessageDecoder.decode(Data([0x00, 0x00, 0x00, 0x00]))
        ) {
            XCTAssertEqual($0 as? HeadwindProtocolError, .malformedMessage)
        }
    }
}
