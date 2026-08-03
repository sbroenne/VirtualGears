import Foundation
import XCTest
@testable import VirtualShiftCore

final class CyclingPowerMeasurementTests: XCTestCase {
    func testDecodesPowerAndCrankData() throws {
        let measurement = try CyclingPowerMeasurement.decode(
            Data([0x20, 0x00, 0xC8, 0x00, 0x64, 0x00, 0x00, 0x04])
        )

        XCTAssertEqual(measurement.powerWatts, 200)
        XCTAssertEqual(measurement.cumulativeCrankRevolutions, 100)
        XCTAssertEqual(measurement.lastCrankEventTime, 1024)
    }

    func testCadenceUsesSuccessiveCrankEvents() throws {
        var tracker = CrankCadenceTracker()
        let first = try CyclingPowerMeasurement.decode(
            Data([0x20, 0x00, 0xC8, 0x00, 0x64, 0x00, 0x00, 0x04])
        )
        let second = try CyclingPowerMeasurement.decode(
            Data([0x20, 0x00, 0xDC, 0x00, 0x65, 0x00, 0x00, 0x06])
        )

        XCTAssertNil(tracker.update(with: first))
        XCTAssertEqual(tracker.update(with: second)!, 120, accuracy: 0.001)
    }

    func testCadenceHandlesCounterWraparound() throws {
        var tracker = CrankCadenceTracker()
        let first = try CyclingPowerMeasurement.decode(
            Data([0x20, 0x00, 0x64, 0x00, 0xFF, 0xFF, 0x00, 0xFF])
        )
        let second = try CyclingPowerMeasurement.decode(
            Data([0x20, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x01])
        )

        XCTAssertNil(tracker.update(with: first))
        XCTAssertEqual(tracker.update(with: second)!, 120, accuracy: 0.001)
    }

    func testRejectsTruncatedMeasurement() {
        XCTAssertThrowsError(
            try CyclingPowerMeasurement.decode(Data([0x20, 0x00, 0xC8]))
        )
    }
}
