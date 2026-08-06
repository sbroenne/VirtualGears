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

    /// The safety promise of the whole app: whatever a rider picks in setup, the
    /// trainer is only ever asked for a wheel size that was staged on real
    /// hardware. Every catalog pairing is checked, not a chosen sample.
    func testEveryCatalogCombinationStaysInsideThePhysicallyProvenRange() throws {
        var built = 0
        var refused = 0

        for chainring in DrivetrainCatalog.chainrings {
            for cassette in DrivetrainCatalog.cassettes {
                let drivetrain: Drivetrain
                do {
                    drivetrain = try Drivetrain.build(
                        chainrings: chainring.teeth,
                        cassetteCogs: cassette.cogs
                    )
                } catch let error as DrivetrainError {
                    guard case .rangeTooWideForTrainer = error else {
                        return XCTFail(
                            "\(chainring.name) with \(cassette.name) failed "
                                + "for an unexpected reason: \(error)"
                        )
                    }
                    refused += 1
                    continue
                }

                built += 1
                _ = try ConfirmedGearEngine(
                    drivetrain: drivetrain,
                    baselineCircumferenceMillimeters:
                        TrainerSafety.referenceCircumferenceMillimeters
                )

                for gear in drivetrain.gears {
                    let circumference = try WheelCircumferenceScaler
                        .effectiveCircumference(
                            neutralCircumference:
                                TrainerSafety.referenceCircumferenceMillimeters,
                            referenceRatio: drivetrain.referenceGear.ratio,
                            selectedRatio: gear.ratio
                        )
                    let bytes = Array(
                        try WahooKickrCommand.setWheelCircumference(
                            millimeters: circumference
                        )
                    )
                    let encoded = Int(bytes[1]) | Int(bytes[2]) << 8
                    XCTAssertTrue(
                        (6_469...48_000).contains(encoded),
                        "\(chainring.name) with \(cassette.name), gear "
                            + "\(gear.chainring)x\(gear.cog) encodes \(encoded), "
                            + "outside the proven range"
                    )
                }
            }
        }

        XCTAssertEqual(
            built + refused,
            DrivetrainCatalog.chainrings.count * DrivetrainCatalog.cassettes.count
        )
        // A refused pairing is always explained in setup, so a handful of absurd
        // ones is fine, but most of the catalog must actually be usable.
        XCTAssertGreaterThan(built, refused * 5)
    }

    /// The default a rider gets before touching anything must always work.
    func testDefaultPartsBuildASafeDrivetrain() throws {
        let chainring = try XCTUnwrap(
            DrivetrainCatalog.chainring(id: DrivetrainCatalog.defaultChainringID)
        )
        let cassette = try XCTUnwrap(
            DrivetrainCatalog.cassette(id: DrivetrainCatalog.defaultCassetteID)
        )
        let drivetrain = try Drivetrain.build(
            chainrings: chainring.teeth,
            cassetteCogs: cassette.cogs
        )

        XCTAssertGreaterThanOrEqual(drivetrain.gears.count, 12)
        _ = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters:
                TrainerSafety.referenceCircumferenceMillimeters
        )
    }

    /// Cassettes are listed smallest cog first and chainrings largest ring
    /// first, because that is how the parts are named. The builder relies on it.
    func testCatalogEntriesAreOrderedAndUnique() {
        XCTAssertEqual(
            Set(DrivetrainCatalog.chainrings.map(\.id)).count,
            DrivetrainCatalog.chainrings.count
        )
        XCTAssertEqual(
            Set(DrivetrainCatalog.cassettes.map(\.id)).count,
            DrivetrainCatalog.cassettes.count
        )
        for chainring in DrivetrainCatalog.chainrings {
            XCTAssertEqual(
                chainring.teeth,
                chainring.teeth.sorted(by: >),
                "\(chainring.id) should list its largest ring first"
            )
        }
        for cassette in DrivetrainCatalog.cassettes {
            XCTAssertEqual(
                cassette.cogs,
                cassette.cogs.sorted(),
                "\(cassette.id) should list its smallest cog first"
            )
            XCTAssertEqual(
                cassette.name,
                "\(cassette.cogs.first!)-\(cassette.cogs.last!)"
            )
        }
    }

    /// Any riding app may set its own wheel size through FTMS, and VirtualShift
    /// rebuilds the gears around it. It must still refuse a size that would put
    /// any gear outside what the trainer was proven to accept.
    func testRebaseRefusesAWheelSizeTheGearsCannotFitAround() throws {
        let engine = try makeEngine()

        XCTAssertNoThrow(
            try engine.rebased(baselineCircumferenceMillimeters: 2_096)
        )
        XCTAssertThrowsError(
            try engine.rebased(baselineCircumferenceMillimeters: 4_600)
        ) { error in
            XCTAssertEqual(
                error as? VirtualGearError,
                .outsideProvenRange
            )
        }
        XCTAssertThrowsError(
            try engine.rebased(baselineCircumferenceMillimeters: 500)
        ) { error in
            XCTAssertEqual(
                error as? VirtualGearError,
                .outsideProvenRange
            )
        }
    }

    /// The rebuilt gears are the app's wheel size scaled by each ratio, so the
    /// gear the rider is in feels the same relative to whatever the app chose.
    func testRebaseScalesEveryGearFromTheAppsWheelSize() throws {
        let engine = try makeEngine()
        let rebased = try engine.rebased(
            baselineCircumferenceMillimeters: 2_096
        )
        let reference = rebased.drivetrain.referenceGear.ratio

        for gear in rebased.drivetrain.gears {
            let expected = 2_096 / reference * gear.ratio
            XCTAssertEqual(
                try WheelCircumferenceScaler.effectiveCircumference(
                    neutralCircumference: 2_096,
                    referenceRatio: reference,
                    selectedRatio: gear.ratio
                ),
                expected,
                accuracy: 0.0001
            )
        }
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

    // MARK: - Whether the trainer has caught up

    func testAFreshEngineIsSettled() throws {
        let engine = try ConfirmedGearEngine(
            drivetrain: try Drivetrain.virtualLadder(),
            baselineCircumferenceMillimeters: 2070
        )
        XCTAssertTrue(engine.isSettled)
    }

    /// Holding a shift button waits on this. Before the fix, repeats went out
    /// on a fixed timer that never asked whether the trainer had caught up, so
    /// a hold queued gears that carried on arriving after the rider let go.
    func testAnUnconfirmedShiftLeavesTheEngineUnsettled() throws {
        var engine = try ConfirmedGearEngine(
            drivetrain: try Drivetrain.virtualLadder(),
            baselineCircumferenceMillimeters: 2070
        )
        let change = try XCTUnwrap(engine.requestShift(by: 1))
        XCTAssertFalse(engine.isSettled)

        let response = WahooKickrResponse.wheelCircumference(
            result: 1,
            encodedTenthsOfMillimeter: UInt16(
                (change.circumferenceMillimeters * 10).rounded()
            )
        )
        engine.acknowledge(response)
        XCTAssertTrue(engine.isSettled)
    }

    func testCancellingPendingChangesSettlesTheEngine() throws {
        var engine = try ConfirmedGearEngine(
            drivetrain: try Drivetrain.virtualLadder(),
            baselineCircumferenceMillimeters: 2070
        )
        engine.requestShift(by: 1)
        XCTAssertFalse(engine.isSettled)
        engine.cancelPendingChanges()
        XCTAssertTrue(engine.isSettled)
    }
}
