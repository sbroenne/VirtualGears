import XCTest
@testable import VirtualGearsCore

/// The bug these were written for was invisible, which is why it needed
/// finding by measurement rather than by riding.
///
/// The bike never shifts. It is parked in one gear, and what the rider's legs
/// feel is that parked ratio times the wheel size the app sets. The app only
/// controlled the second half and assumed the first, so the step sizes were
/// always right and the whole ladder was in the wrong place. A rider parked in
/// the big ring on the smallest cog was riding a ladder ninety per cent harder
/// than the one on the screen and would only ever have reported that the app
/// "has no easy gears".
final class ParkedGearTests: XCTestCase {
    private let compact = PhysicalSetup(
        chainringTeeth: [50, 34],
        cogTeeth: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
    )

    private func ladder() throws -> Drivetrain {
        try GearLadderCatalog.standardRange.drivetrain()
    }

    // MARK: - The maths

    func testRejectsImpossibleToothCounts() {
        XCTAssertNil(ParkedGear(chainringTeeth: 0, cogTeeth: 15))
        XCTAssertNil(ParkedGear(chainringTeeth: 34, cogTeeth: 0))
        XCTAssertNil(ParkedGear(chainringTeeth: -34, cogTeeth: 15))
    }

    func testAParkedGearIsNamedTheWayARiderSaysIt() throws {
        let gear = try XCTUnwrap(ParkedGear(chainringTeeth: 34, cogTeeth: 15))
        XCTAssertEqual(gear.name, "34/15")
        XCTAssertEqual(gear.ratio, 34.0 / 15.0, accuracy: 0.0001)
    }

    /// The whole point: the wheel size sent for a gear is scaled by the gear
    /// the bike is actually in, not by the gear the app started in.
    func testTheWheelSizeSentIsScaledByTheParkedGear() throws {
        let drivetrain = try ladder()
        let parked = try XCTUnwrap(
            ParkedGear(chainringTeeth: 34, cogTeeth: 15)
        )
        let engine = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            wheelSizeMillimeters: 2_105,
            parkedGear: parked
        )

        for change in drivetrain.gears.indices.map({
            try? engineChange(engine, at: $0)
        }) {
            let change = try XCTUnwrap(change)
            XCTAssertEqual(
                change.circumferenceMillimeters,
                2_105 * change.gear.ratio / parked.ratio,
                accuracy: 0.001
            )
        }
    }

    /// A rider whose bike happens to be parked in the starting gear sees
    /// exactly what the app did before any of this existed.
    func testParkingInTheStartingGearChangesNothing() throws {
        let drivetrain = try ladder()
        let assumed = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            wheelSizeMillimeters: 2_105
        )
        XCTAssertEqual(
            assumed.parkedRatio,
            drivetrain.referenceGear.ratio,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            assumed.confirmedSetting.circumferenceMillimeters,
            2_105,
            accuracy: 0.001
        )
    }

    /// Parked in a harder gear than assumed, every gear on the screen is really
    /// harder than it says. A rider left in 50/11 is riding gear 1 as a 1.14,
    /// which is why the easy half of the ladder appears not to exist.
    func testParkingInTheBigRingMakesEveryGearHarderThanItLooks() throws {
        let drivetrain = try ladder()
        let bigRing = try XCTUnwrap(
            ParkedGear(chainringTeeth: 50, cogTeeth: 15)
        )
        let assumed = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            wheelSizeMillimeters: 2_105
        )
        let corrected = try ConfirmedGearEngine(
            drivetrain: drivetrain,
            wheelSizeMillimeters: 2_105,
            parkedGear: bigRing
        )

        // Correcting for it asks the trainer for a smaller wheel, which is what
        // cancels the harder gear out.
        XCTAssertLessThan(
            corrected.confirmedSetting.circumferenceMillimeters,
            assumed.confirmedSetting.circumferenceMillimeters
        )
    }

    /// Only the position of the ladder was ever wrong. Every step between gears
    /// stays exactly the same, which is precisely why nobody would have
    /// reported this as a bug.
    func testTheStepBetweenGearsDoesNotDependOnTheParkedGear() throws {
        let drivetrain = try ladder()
        let quiet = try XCTUnwrap(ParkedGear(chainringTeeth: 34, cogTeeth: 15))
        let engines = [
            try ConfirmedGearEngine(
                drivetrain: drivetrain,
                wheelSizeMillimeters: 2_105
            ),
            try ConfirmedGearEngine(
                drivetrain: drivetrain,
                wheelSizeMillimeters: 2_105,
                parkedGear: quiet
            ),
        ]
        let ratios = try engines.map { engine -> [Double] in
            let sizes = try drivetrain.gears.indices.map {
                try engineChange(engine, at: $0).circumferenceMillimeters
            }
            return zip(sizes, sizes.dropFirst()).map { $1 / $0 }
        }
        for (assumed, corrected) in zip(ratios[0], ratios[1]) {
            XCTAssertEqual(assumed, corrected, accuracy: 0.0001)
        }
    }

    /// Changing wheel size mid-ride must not quietly forget which gear the bike
    /// is sitting in.
    func testRebasingKeepsTheParkedGear() throws {
        let parked = try XCTUnwrap(ParkedGear(chainringTeeth: 34, cogTeeth: 15))
        let engine = try ConfirmedGearEngine(
            drivetrain: try ladder(),
            wheelSizeMillimeters: 2_105,
            parkedGear: parked
        )
        XCTAssertEqual(try engine.rebased(wheelSizeMillimeters: 2_326).parkedGear, parked)
    }

    // MARK: - The floor

    /// The hard limit, and the reason "small ring, middle cog" cannot be a
    /// fixed sentence. The command tops out at 6553.5 mm, so at a 2400 mm wheel
    /// a full 5.49 ladder needs a parked ratio of at least 2.011.
    func testTheFullLadderNeedsAParkedRatioOfAtLeastTwoPointZeroOne() throws {
        let range = try XCTUnwrap(
            ParkedGearAdvice.workableRatios(for: try ladder())
        )
        XCTAssertEqual(range.lowerBound, 2.0105, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 3.125, accuracy: 0.001)
    }

    /// Literal middle-cog advice puts a 105 on 34/17 = 2.00, under the floor,
    /// and the top of the ladder would silently stop working.
    func testTheLiteralMiddleCogWouldBreakTheTopOfTheLadder() throws {
        let drivetrain = try ladder()
        let literal = try XCTUnwrap(ParkedGear(chainringTeeth: 34, cogTeeth: 17))
        XCTAssertFalse(
            ParkedGearAdvice.isWorkable(literal, simulating: drivetrain)
        )
        let suggested = try XCTUnwrap(
            ParkedGearAdvice.suggestion(for: compact, simulating: drivetrain)
        )
        XCTAssertTrue(
            ParkedGearAdvice.isWorkable(suggested, simulating: drivetrain)
        )
    }

    /// A real groupset asks less of the trainer than a full virtual ladder, so
    /// its floor is lower and there is more choice of where to park.
    func testARealDrivetrainHasAWiderChoiceOfParkedGears() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: compact.chainringTeeth,
            cassetteCogs: compact.cogTeeth
        )
        let range = try XCTUnwrap(
            ParkedGearAdvice.workableRatios(for: drivetrain)
        )
        XCTAssertLessThan(range.lowerBound, 2.0)
        XCTAssertGreaterThan(range.upperBound, 4.0)
    }

    // MARK: - What to recommend

    /// Quietest that still works. On a 105 the cassette has no 16, so 34/17 is
    /// under the floor and the answer is 34/15.
    func testTheSuggestionForACompactIsThirtyFourFifteen() throws {
        let suggestion = try XCTUnwrap(
            ParkedGearAdvice.suggestion(for: compact, simulating: try ladder())
        )
        XCTAssertEqual(suggestion.name, "34/15")
    }

    /// A Zwift Cog has one sprocket, so only the chainring is worth asking
    /// about, and 31/14 lands in the same quiet band as everything else.
    func testASingleSprocketIsRecommendedAsItself() throws {
        let cog = PhysicalSetup(chainringTeeth: [31], cogTeeth: [14])
        XCTAssertTrue(cog.isSingleSprocket)
        let suggestion = try XCTUnwrap(
            ParkedGearAdvice.suggestion(for: cog, simulating: try ladder())
        )
        XCTAssertEqual(suggestion.name, "31/14")
        XCTAssertEqual(suggestion.ratio, 31.0 / 14.0, accuracy: 0.0001)
    }

    /// Indoors the trainer is the loudest thing in the room and its flywheel
    /// speed follows the parked ratio, so the recommendation should always be
    /// far quieter than the worst case a rider might otherwise leave it in.
    func testTheSuggestionIsMuchQuieterThanTheBigRingOnTheSmallestCog() throws {
        let suggestion = try XCTUnwrap(
            ParkedGearAdvice.suggestion(for: compact, simulating: try ladder())
        )
        XCTAssertLessThan(suggestion.ratio, (50.0 / 11.0) * 0.6)
    }

    /// The suggestion has to come from the rider's own parts, not from a table.
    func testTheSuggestionIsAlwaysAGearTheRiderActuallyHas() throws {
        let drivetrain = try ladder()
        for groupset in GroupsetCatalog.groupsets {
            for chainring in groupset.chainrings {
                for cassette in groupset.cassettes {
                    let setup = PhysicalSetup(
                        chainringTeeth: chainring.teeth,
                        cogTeeth: cassette.cogs
                    )
                    guard let suggestion = ParkedGearAdvice.suggestion(
                        for: setup,
                        simulating: drivetrain
                    ) else { continue }
                    XCTAssertTrue(
                        chainring.teeth.contains(suggestion.chainringTeeth),
                        "\(groupset.name) \(chainring.name)"
                    )
                    XCTAssertTrue(
                        cassette.cogs.contains(suggestion.cogTeeth),
                        "\(groupset.name) \(cassette.name)"
                    )
                }
            }
        }
    }

    /// The corners a rider is told never to use are not somewhere to leave the
    /// bike parked for an hour either.
    func testTheSuggestionIsNeverACrossChainedCorner() throws {
        let drivetrain = try ladder()
        let suggestion = try XCTUnwrap(
            ParkedGearAdvice.suggestion(for: compact, simulating: drivetrain)
        )
        XCTAssertNotEqual(suggestion.cogTeeth, compact.cogTeeth.min())
        XCTAssertNotEqual(suggestion.cogTeeth, compact.cogTeeth.max())
    }

    // MARK: - Setup will not finish without it

    func testSetupIsNotFinishedUntilTheParkedGearIsConfirmed() {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        XCTAssertNil(configuration.parkedGear)
        XCTAssertFalse(configuration.canFinishSetup)

        configuration.parkInSuggestion()

        XCTAssertNotNil(configuration.parkedGear)
        XCTAssertTrue(configuration.canFinishSetup)
    }

    func testConfirmingTheSuggestionIsASingleTap() throws {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        let suggestion = try XCTUnwrap(configuration.suggestedParkedGear)
        configuration.parkInSuggestion()
        XCTAssertEqual(configuration.parkedGear, suggestion)
        XCTAssertFalse(configuration.parkedGearPutsGearsOutOfReach)
        XCTAssertNil(configuration.parkedGearWarning)
    }

    /// Do not just compute the consequence — say it. A rider who confirms
    /// something far from the recommendation is told what it costs.
    func testAnUnworkableParkedGearIsExplainedRatherThanRefused() throws {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        configuration.park(
            in: try XCTUnwrap(ParkedGear(chainringTeeth: 50, cogTeeth: 11))
        )

        XCTAssertTrue(configuration.parkedGearPutsGearsOutOfReach)
        let warning = try XCTUnwrap(configuration.parkedGearWarning)
        XCTAssertTrue(warning.contains("cannot reach"))
        XCTAssertFalse(configuration.hasSafeCircumference)
        XCTAssertFalse(configuration.canFinishSetup)
    }

    /// The advice names a gear rather than asking an open question, and says
    /// the bike stays in it.
    func testTheAdviceNamesTheGearAndSaysTheBikeStaysThere() {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        let advice = configuration.parkedGearAdviceText
        XCTAssertTrue(advice.contains("34"))
        XCTAssertTrue(advice.contains("15"))
        XCTAssertTrue(advice.contains("straight chain line"))
        XCTAssertTrue(advice.contains("whole ride"))
    }

    func testTheAdviceCallsASingleSprocketASprocket() {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        configuration.physical = PhysicalSetup(
            chainringTeeth: [31],
            cogTeeth: [14]
        )
        XCTAssertTrue(
            configuration.parkedGearAdviceText.contains("sprocket")
        )
    }

    /// A saved setup has to remember the parked gear, or the rider is asked
    /// again every launch and the gears move if they answer differently.
    func testTheParkedGearSurvivesBeingReloaded() throws {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        configuration.parkInSuggestion()
        let restored = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(restored.parkedGear, configuration.parkedGear)
        XCTAssertEqual(restored, configuration)
    }

    // MARK: - Helper

    private func engineChange(
        _ engine: ConfirmedGearEngine,
        at index: Int
    ) throws -> PendingGearChange {
        var moving = engine
        moving.requestShift(by: index - engine.confirmedIndex)
        var change = moving.pendingChange
        while let pending = moving.pendingChange {
            change = pending
            let bytes = Array(pending.command)
            moving.acknowledge(
                .wheelCircumference(
                    result: 1,
                    encodedTenthsOfMillimeter:
                        UInt16(bytes[1]) | UInt16(bytes[2]) << 8
                )
            )
        }
        return try XCTUnwrap(change ?? engine.confirmedSetting)
    }
}
