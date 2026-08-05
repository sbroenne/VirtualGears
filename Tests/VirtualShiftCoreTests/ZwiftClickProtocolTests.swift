import Foundation
import XCTest
@testable import VirtualShiftCore

final class ZwiftClickProtocolTests: XCTestCase {
    func testDecodesPlusPressAndRelease() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(
                Data([0x37, 0x08, 0x00, 0x10, 0x01])
            ),
            .buttons(plusPressed: true, minusPressed: false)
        )
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(
                Data([0x37, 0x08, 0x01, 0x10, 0x01])
            ),
            .buttons(plusPressed: false, minusPressed: false)
        )
    }

    func testDecodesMinusPressWithReorderedFields() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(
                Data([0x37, 0x10, 0x00, 0x08, 0x01])
            ),
            .buttons(plusPressed: false, minusPressed: true)
        )
    }

    func testEdgeTrackerIgnoresDuplicatePackets() {
        var tracker = ZwiftClickEdgeTracker()

        XCTAssertEqual(
            tracker.update(plus: true, minus: false),
            [.pressed(.plus)]
        )
        XCTAssertEqual(tracker.update(plus: true, minus: false), [])
        XCTAssertEqual(
            tracker.update(plus: false, minus: false),
            [.released(.plus)]
        )
    }

    func testDecodesKeepAliveAndRejectsIncompleteButtons() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(Data([0x15])),
            .keepAlive
        )
        XCTAssertThrowsError(
            try ZwiftClickMessageDecoder.decode(Data([0x37, 0x08, 0x00]))
        )
    }

    /// Recorded from an original Zwift Click, which sends this roughly every
    /// five seconds. The trace was taken with a fully charged Click, and the
    /// standard Bluetooth battery characteristic read 100% at the same moment.
    func testDecodesTheBatteryMessageAnOriginalClickReallySends() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(Data([0x19, 0x10, 0x64])),
            .batteryLevel(percent: 100)
        )
    }

    /// A part-charged Click was never available to record, so this covers the
    /// case the recording could not: the percentage has to be read from the
    /// packet rather than assumed to be full.
    func testDecodesABatteryLevelBelowFull() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(Data([0x19, 0x10, 0x32])),
            .batteryLevel(percent: 50)
        )
    }

    /// A percentage above 100 is not a battery level, so it is rejected rather
    /// than shown to the rider as nonsense.
    func testRejectsAnImpossibleBatteryLevel() throws {
        XCTAssertThrowsError(
            try ZwiftClickMessageDecoder.decode(Data([0x19, 0x10, 0x7F]))
        )
    }

    /// Taken from the same recording: one press and one release, with the
    /// buttons reported as zero when pressed.
    func testDecodesARealPressAndRelease() throws {
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(
                Data([0x37, 0x08, 0x00, 0x10, 0x01])
            ),
            .buttons(plusPressed: true, minusPressed: false)
        )
        XCTAssertEqual(
            try ZwiftClickMessageDecoder.decode(
                Data([0x37, 0x08, 0x01, 0x10, 0x01])
            ),
            .buttons(plusPressed: false, minusPressed: false)
        )
    }
}
