import Foundation
import XCTest
@testable import VirtualShiftCore

final class ConfirmedGearEngineTests: XCTestCase {
    func testRebasePreservesConfirmedGearAndClearsUnconfirmedRequest() throws {
        var engine = try makeEngine()
        let first = try XCTUnwrap(engine.requestShift(by: 1))
        let response = try WahooKickrResponse.decode(Data([
            0x01, 0x48, 0x01, 0x00, first.command[1], first.command[2],
        ]))
        _ = engine.acknowledge(response)
        _ = engine.requestShift(by: 2)

        let rebased = try engine.rebased(
            baselineCircumferenceMillimeters: 2_100
        )

        XCTAssertEqual(rebased.confirmedGear, engine.confirmedGear)
        XCTAssertEqual(rebased.requestedGear, engine.confirmedGear)
        XCTAssertNil(rebased.pendingChange)
        XCTAssertEqual(rebased.baselineCircumferenceMillimeters, 2_100)
    }

    func testStartsAtReferenceWithNoPendingChange() throws {
        let drivetrain = try makeDrivetrain()
        let engine = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters: 2_100
        )

        XCTAssertEqual(engine.requestedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(engine.confirmedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(engine.requestedGear, drivetrain.referenceGear)
        XCTAssertEqual(engine.confirmedGear, drivetrain.referenceGear)
        XCTAssertNil(engine.pendingChange)
    }

    func testScalesEachChangeFromBaselineReferenceRatio() throws {
        var engine = try makeEngine()

        let easier = try XCTUnwrap(engine.requestShift(by: -1))
        XCTAssertEqual(
            easier.circumferenceMillimeters,
            1_400,
            accuracy: 0.000_001
        )
        _ = engine.acknowledge(acknowledgement(for: easier))
        let reference = try XCTUnwrap(engine.requestShift(by: 3))
        XCTAssertEqual(
            reference.circumferenceMillimeters,
            2_100,
            accuracy: 0.000_001
        )
        let harder = try XCTUnwrap(
            engine.acknowledge(acknowledgement(for: reference))
        )
        XCTAssertEqual(
            harder.circumferenceMillimeters,
            2_800,
            accuracy: 0.000_001
        )
    }

    func testConfirmedStateWaitsForExactAcknowledgement() throws {
        var engine = try makeEngine()
        let referenceIndex = engine.confirmedIndex
        let pending = try XCTUnwrap(engine.requestShift(by: 1))

        XCTAssertEqual(engine.requestedIndex, referenceIndex + 1)
        XCTAssertEqual(engine.confirmedIndex, referenceIndex)
        XCTAssertNil(
            engine.acknowledge(
                .wheelCircumference(
                    result: 1,
                    encodedTenthsOfMillimeter:
                        encodedValue(of: pending) + 1
                )
            )
        )
        XCTAssertEqual(engine.confirmedIndex, referenceIndex)
        XCTAssertEqual(engine.pendingChange, pending)

        XCTAssertNil(engine.acknowledge(.unlock(result: 2)))
        XCTAssertEqual(engine.confirmedIndex, referenceIndex)
        XCTAssertEqual(engine.pendingChange, pending)

        XCTAssertNil(
            engine.acknowledge(acknowledgement(for: pending))
        )
        XCTAssertEqual(engine.confirmedIndex, referenceIndex + 1)
        XCTAssertNil(engine.pendingChange)
    }

    func testRejectedResponseDoesNotConfirmGear() throws {
        var engine = try makeEngine()
        let start = engine.confirmedIndex
        let pending = try XCTUnwrap(engine.requestShift(by: 1))

        XCTAssertNil(
            engine.acknowledge(
                .wheelCircumference(
                    result: 0,
                    encodedTenthsOfMillimeter: encodedValue(of: pending)
                )
            )
        )
        XCTAssertEqual(engine.confirmedIndex, start)
        XCTAssertEqual(engine.pendingChange, pending)
    }

    func testEqualEncodedStepsDoNotSendDuplicateCommands() throws {
        let first = try VirtualGear(chainring: 100_000, cog: 50_000)
        let second = try VirtualGear(chainring: 100_001, cog: 50_000)
        let harder = try VirtualGear(chainring: 50, cog: 20)
        let drivetrain = try Drivetrain(
            chainrings: [100_000, 100_001, 50],
            cassetteCogs: [50_000, 20],
            allowedCombinations: [first, second, harder]
        )
        var engine = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters: 2_100
        )

        XCTAssertNil(engine.requestShift(by: -1))
        XCTAssertEqual(engine.confirmedGear, first)

        let pending = try XCTUnwrap(engine.requestShift(by: 2))
        XCTAssertEqual(pending.gear, harder)
        XCTAssertEqual(engine.confirmedGear, second)
    }

    func testMultiStepRequestAdvancesOneAcknowledgedGearAtATime() throws {
        var engine = try makeEngine()
        let start = engine.confirmedIndex
        let first = try XCTUnwrap(engine.requestShift(by: 2))

        XCTAssertEqual(engine.requestedIndex, start + 2)
        XCTAssertEqual(first.index, start + 1)
        XCTAssertEqual(engine.confirmedIndex, start)

        let second = try XCTUnwrap(
            engine.acknowledge(acknowledgement(for: first))
        )
        XCTAssertEqual(engine.confirmedIndex, start + 1)
        XCTAssertEqual(second.index, start + 2)

        XCTAssertNil(
            engine.acknowledge(acknowledgement(for: second))
        )
        XCTAssertEqual(engine.confirmedIndex, start + 2)
        XCTAssertEqual(engine.requestedIndex, start + 2)
    }

    func testAdditionalRequestsDoNotReplaceInflightChange() throws {
        var engine = try makeEngine()
        let first = try XCTUnwrap(engine.requestShift(by: 1))

        XCTAssertNil(engine.requestShift(by: 2))
        XCTAssertEqual(engine.pendingChange, first)
        XCTAssertEqual(engine.requestedIndex, 3)
        XCTAssertEqual(engine.confirmedIndex, 1)
    }

    func testDirectionChangeWaitsForInflightAcknowledgement() throws {
        var engine = try makeEngine()
        let upward = try XCTUnwrap(engine.requestShift(by: 2))
        XCTAssertNil(engine.requestShift(by: -3))
        XCTAssertEqual(engine.pendingChange, upward)
        XCTAssertEqual(engine.requestedIndex, 0)

        let downward = try XCTUnwrap(
            engine.acknowledge(acknowledgement(for: upward))
        )
        XCTAssertEqual(engine.confirmedIndex, 2)
        XCTAssertEqual(downward.index, 1)

        let final = try XCTUnwrap(
            engine.acknowledge(acknowledgement(for: downward))
        )
        XCTAssertEqual(final.index, 0)
    }

    func testRequestsClampAtBothBoundaries() throws {
        var engine = try makeEngine()
        var pending = try XCTUnwrap(engine.requestShift(by: .max))

        while engine.confirmedIndex != engine.requestedIndex {
            let next = engine.acknowledge(
                acknowledgement(for: pending)
            )
            if let next {
                pending = next
            }
        }
        XCTAssertEqual(engine.confirmedIndex, 3)
        XCTAssertNil(engine.requestShift(by: 1))

        pending = try XCTUnwrap(engine.requestShift(by: .min))
        while engine.confirmedIndex != engine.requestedIndex {
            let next = engine.acknowledge(
                acknowledgement(for: pending)
            )
            if let next {
                pending = next
            }
        }
        XCTAssertEqual(engine.confirmedIndex, 0)
        XCTAssertNil(engine.requestShift(by: -1))
    }

    func testRejectsBaselineThatMakesAnyGearUnsafe() throws {
        XCTAssertThrowsError(
            try ConfirmedGearEngine(
                drivetrain: makeDrivetrain(),
                baselineCircumferenceMillimeters:
                    WahooKickrCommand.maximumCircumferenceMillimeters
            )
        )
        XCTAssertThrowsError(
            try ConfirmedGearEngine(
                drivetrain: makeDrivetrain(),
                baselineCircumferenceMillimeters: .nan
            )
        )
    }

    private func makeEngine() throws -> ConfirmedGearEngine {
        try ConfirmedGearEngine(
            drivetrain: makeDrivetrain(),
            baselineCircumferenceMillimeters: 2_100
        )
    }

    private func makeDrivetrain() throws -> Drivetrain {
        let cogs = [30, 20, 15, 10]
        let gears = try cogs.map {
            try VirtualGear(chainring: 30, cog: $0)
        }
        return try Drivetrain(
            chainrings: [30],
            cassetteCogs: cogs,
            allowedCombinations: gears
        )
    }

    private func acknowledgement(
        for change: PendingGearChange
    ) -> WahooKickrResponse {
        .wheelCircumference(
            result: 1,
            encodedTenthsOfMillimeter: encodedValue(of: change)
        )
    }

    private func encodedValue(
        of change: PendingGearChange
    ) -> UInt16 {
        let bytes = Array(change.command)
        return UInt16(bytes[1]) | UInt16(bytes[2]) << 8
    }
}
