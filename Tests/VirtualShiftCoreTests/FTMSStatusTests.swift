import Foundation
import XCTest
@testable import VirtualShiftCore

final class FTMSStatusTests: XCTestCase {
    func testEveryStatusKnownBytesAndRoundTrip() throws {
        let simulation = IndoorBikeSimulationParameters(
            windSpeedThousandthsMetersPerSecond: -1,
            gradeHundredthsPercent: 500,
            rollingResistanceCoefficientTenThousandths: 30,
            windResistanceCoefficientHundredthsKilogramsPerMeter: 40
        )
        let cases: [(FitnessMachineStatus, [UInt8])] = [
            (.reset, [0x01]),
            (.stoppedOrPaused(.stop), [0x02, 0x01]),
            (.stoppedOrPaused(.pause), [0x02, 0x02]),
            (.startedOrResumed, [0x04]),
            (.targetPowerChanged(watts: -200), [0x08, 0x38, 0xFF]),
            (
                .targetResistanceLevelChanged(tenths: -15),
                [0x07, 0xF1, 0xFF]
            ),
            (
                .indoorBikeSimulationParametersChanged(simulation),
                [0x12, 0xFF, 0xFF, 0xF4, 0x01, 0x1E, 0x28]
            ),
            (.controlPermissionLost, [0xFF]),
        ]

        for (status, bytes) in cases {
            XCTAssertEqual(status.encode(), Data(bytes))
            XCTAssertEqual(
                try FitnessMachineStatus.decode(Data(bytes)),
                status
            )
        }
    }

    func testStatusRejectsMalformedUnknownAndInvalidAction() {
        XCTAssertThrowsError(try FitnessMachineStatus.decode(Data()))
        XCTAssertThrowsError(
            try FitnessMachineStatus.decode(Data([0x01, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineStatus.decode(Data([0x02, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineStatus.decode(Data([0x12, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineStatus.decode(Data([0x99]))
        )
    }
}
