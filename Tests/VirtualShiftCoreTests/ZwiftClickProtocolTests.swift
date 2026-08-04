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
}
