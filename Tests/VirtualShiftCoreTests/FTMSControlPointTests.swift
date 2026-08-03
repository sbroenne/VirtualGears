import Foundation
import XCTest
@testable import VirtualShiftCore

final class FTMSControlPointTests: XCTestCase {
    private let simulation = IndoorBikeSimulationParameters(
        windSpeedThousandthsMetersPerSecond: -1_500,
        gradeHundredthsPercent: -725,
        rollingResistanceCoefficientTenThousandths: 40,
        windResistanceCoefficientHundredthsKilogramsPerMeter: 51
    )

    func testEveryRequestKnownBytesAndRoundTrip() throws {
        let cases: [(FitnessMachineControlPointRequest, [UInt8])] = [
            (.requestControl, [0x00]),
            (.reset, [0x01]),
            (.setTargetResistanceLevel(tenths: -10), [0x04, 0xF6, 0xFF]),
            (.setTargetPower(watts: -250), [0x05, 0x06, 0xFF]),
            (.startOrResume, [0x07]),
            (.stopOrPause(.stop), [0x08, 0x01]),
            (.stopOrPause(.pause), [0x08, 0x02]),
            (
                .setIndoorBikeSimulationParameters(simulation),
                [0x11, 0x24, 0xFA, 0x2B, 0xFD, 0x28, 0x33]
            ),
            (
                .setWheelCircumference(tenthsOfMillimeter: 20_700),
                [0x12, 0xDC, 0x50]
            ),
        ]

        for (request, bytes) in cases {
            XCTAssertEqual(try request.encode(), Data(bytes))
            XCTAssertEqual(
                try FitnessMachineControlPointRequest.decode(Data(bytes)),
                request
            )
        }
    }

    func testRequestsRejectInvalidLengthOpcodeAndParameters() {
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data())
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data([0, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data([0x99]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data([0x08, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data([0x11, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest.decode(Data([0x12, 0, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointRequest
                .setWheelCircumference(tenthsOfMillimeter: 0)
                .encode()
        )
    }

    func testResponseKnownBytesResultsAndValidation() throws {
        for result in [
            FTMSControlPointResult.success,
            .opcodeNotSupported,
            .invalidParameter,
            .operationFailed,
            .controlNotPermitted,
        ] {
            let response = FitnessMachineControlPointResponse(
                requestOpcode: 0x12,
                result: result
            )
            XCTAssertEqual(
                response.encode(),
                Data([0x80, 0x12, result.rawValue])
            )
            XCTAssertEqual(try .decode(response.encode()), response)
        }
        XCTAssertThrowsError(
            try FitnessMachineControlPointResponse.decode(Data([0x80, 0]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointResponse.decode(Data([0, 0, 1]))
        )
        XCTAssertThrowsError(
            try FitnessMachineControlPointResponse.decode(Data([0x80, 0, 0]))
        )
    }

    func testOwnershipRequiresSubscriptionAndControl() {
        var ownership = FTMSControlOwnership()
        XCTAssertEqual(
            ownership.handle(.requestControl).result,
            .controlNotPermitted
        )
        ownership.setControlPointSubscribed(true)
        XCTAssertEqual(
            ownership.handle(.setTargetPower(watts: 200)).result,
            .controlNotPermitted
        )
        XCTAssertEqual(ownership.handle(.requestControl).result, .success)
        XCTAssertTrue(ownership.hasControl)
        XCTAssertEqual(
            ownership.handle(.setTargetPower(watts: 200)).result,
            .success
        )
    }

    func testResetAndControlLossRelinquishControl() {
        var ownership = FTMSControlOwnership()
        ownership.setControlPointSubscribed(true)
        _ = ownership.handle(.requestControl)
        XCTAssertEqual(ownership.handle(.reset).result, .success)
        XCTAssertFalse(ownership.hasControl)
        XCTAssertEqual(
            ownership.handle(.startOrResume).result,
            .controlNotPermitted
        )

        _ = ownership.handle(.requestControl)
        XCTAssertEqual(ownership.loseControl(), .controlPermissionLost)
        XCTAssertNil(ownership.loseControl())
        _ = ownership.handle(.requestControl)
        ownership.setControlPointSubscribed(false)
        XCTAssertFalse(ownership.hasControl)
    }
}
