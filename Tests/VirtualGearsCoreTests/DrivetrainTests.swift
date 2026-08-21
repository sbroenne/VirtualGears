import XCTest
@testable import VirtualGearsCore

final class DrivetrainTests: XCTestCase {
    func testUsesOnlyAllowedCombinationsAndSortsByRatio() throws {
        let easiest = try VirtualGear(chainring: 34, cog: 28)
        let middle = try VirtualGear(chainring: 34, cog: 17)
        let hardest = try VirtualGear(chainring: 50, cog: 24)
        let drivetrain = try Drivetrain(
            chainrings: [34, 50],
            cassetteCogs: [28, 24, 17],
            allowedCombinations: [
                hardest,
                easiest,
                middle,
            ]
        )

        XCTAssertEqual(drivetrain.gears, [easiest, middle, hardest])
        XCTAssertFalse(
            drivetrain.gears.contains(
                try VirtualGear(chainring: 50, cog: 28)
            )
        )
    }

    func testEqualRatiosAreRejected() throws {
        let first = try VirtualGear(chainring: 30, cog: 15)
        let second = try VirtualGear(chainring: 40, cog: 20)
        let third = try VirtualGear(chainring: 50, cog: 25)
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [50, 30, 40],
                cassetteCogs: [25, 15, 20],
                allowedCombinations: [third, second, first]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateRatio(third, second)
            )
        }
    }

    func testReferenceUsesMiddleForOddCount() throws {
        let drivetrain = try makeDrivetrain(cogs: [30, 20, 10])

        XCTAssertEqual(drivetrain.referenceIndex, 1)
        XCTAssertEqual(drivetrain.referenceGear.cog, 20)
    }

    func testReferenceUsesLowerMiddleForEvenCount() throws {
        let drivetrain = try makeDrivetrain(cogs: [30, 20, 15, 10])

        XCTAssertEqual(drivetrain.referenceIndex, 1)
        XCTAssertEqual(drivetrain.referenceGear.cog, 20)
    }

    /// The small ring belongs on the larger cogs and the big ring on the
    /// smaller ones. Pairing everything with everything invents gears such as a
    /// 34 tooth ring on an 11 tooth cog that no rider would use.
    func testBuildSkipsCrossChainedCombinations() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: [11, 17, 28]
        )

        XCTAssertEqual(
            drivetrain.gears.map { "\($0.chainring)x\($0.cog)" },
            ["34x28", "34x17", "50x17", "50x11"]
        )
        XCTAssertEqual(drivetrain.chainrings, [50, 34])
        XCTAssertEqual(drivetrain.cassetteCogs, [11, 17, 28])
    }

    /// A rider works up the cassette on the small ring, moves to the big ring,
    /// and carries on. The chainring never gets smaller as the gear gets
    /// harder, so the handlebar readout never jumps backwards between rings.
    func testBuildNeverReturnsToASmallerChainringAsGearsGetHarder() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
        )

        let rings = drivetrain.gears.map(\.chainring)
        XCTAssertEqual(rings, rings.sorted())
        XCTAssertEqual(drivetrain.gears.first.map { "\($0.chainring)x\($0.cog)" }, "34x34")
        XCTAssertEqual(drivetrain.gears.last.map { "\($0.chainring)x\($0.cog)" }, "50x11")
    }

    /// One chainring reaches the whole cassette, so nothing is dropped.
    func testBuildKeepsEveryCogOnASingleChainring() throws {
        let cogs = [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 52]
        let drivetrain = try Drivetrain.build(chainrings: [42], cassetteCogs: cogs)

        XCTAssertEqual(drivetrain.gears.count, cogs.count)
        XCTAssertEqual(drivetrain.gears.map(\.cog), cogs.sorted(by: >))
    }

    /// Two combinations can land on the identical ratio, and two gear numbers
    /// that feel the same would be two shifts that do nothing. Walking the
    /// drivetrain cannot produce one: every step is strictly harder than the
    /// last, by more than a rider can feel.
    func testBuildKeepsOnlyOneGearPerDistinctRatio() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
        )

        let ratios = drivetrain.gears.map(\.ratio)
        XCTAssertEqual(Set(ratios).count, ratios.count)
        for (previous, next) in zip(ratios, ratios.dropFirst()) {
            XCTAssertGreaterThan(next, previous)
        }
    }

    /// The starting gear is the one nearest the declared 2.40, not wherever the
    /// range happened to leave room. On a wide mountain setup that puts it above
    /// the middle of the ladder rather than on it.
    func testBuildPlacesStartingGearWhereBothEndsFit() throws {
        let drivetrain = try Drivetrain.build(
            chainrings: [32],
            cassetteCogs: [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51]
        )

        let reference = drivetrain.referenceGear.ratio
        let hardest = drivetrain.gears.last!.ratio
        let easiest = drivetrain.gears.first!.ratio
        XCTAssertLessThanOrEqual(
            hardest / reference,
            TrainerSafety.supportedScaleRange.upperBound
        )
        XCTAssertGreaterThanOrEqual(
            easiest / reference,
            TrainerSafety.supportedScaleRange.lowerBound
        )
        XCTAssertGreaterThan(
            drivetrain.referenceIndex,
            (drivetrain.gears.count - 1) / 2
        )
    }

    func testBuildRefusesARangeTheTrainerCannotCover() {
        XCTAssertThrowsError(
            try Drivetrain.build(
                chainrings: [50, 34],
                cassetteCogs: [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 52],
                scaleRange: 0.5...2
            )
        ) {
            guard case .rangeTooWideForTrainer = $0 as? DrivetrainError else {
                return XCTFail("expected a too-wide failure, got \($0)")
            }
        }
    }

    func testBuildRejectsEmptyOrRepeatedParts() {
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [], cassetteCogs: [11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .emptyChainrings)
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50], cassetteCogs: [])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .emptyCassette)
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50, 50], cassetteCogs: [11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .duplicateChainring(50))
        }
        XCTAssertThrowsError(
            try Drivetrain.build(chainrings: [50], cassetteCogs: [11, 11])
        ) {
            XCTAssertEqual($0 as? DrivetrainError, .duplicateCassetteCog(11))
        }
    }

    func testSupportsExplicitReferenceGear() throws {
        let drivetrain = try Drivetrain(
            chainrings: [40],
            cassetteCogs: [11, 17, 28],
            allowedCombinations: [
                try VirtualGear(chainring: 40, cog: 11),
                try VirtualGear(chainring: 40, cog: 17),
                try VirtualGear(chainring: 40, cog: 28),
            ],
            referenceIndex: 2
        )

        XCTAssertEqual(drivetrain.referenceIndex, 2)
        XCTAssertEqual(drivetrain.referenceGear.cog, 11)
    }

    func testRejectsEmptyComponentAndCombinationLists() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .emptyChainrings) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .emptyCassette) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: []
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .emptyAllowedCombinations
            )
        }
    }

    func testRejectsNonPositiveComponents() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30, 0],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .invalidChainring(0)) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20, -1],
                allowedCombinations: [gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .invalidCassetteCog(-1)
            )
        }
    }

    func testRejectsDuplicateComponentsAndCombinations() throws {
        let gear = try VirtualGear(chainring: 30, cog: 20)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30, 30],
                cassetteCogs: [20],
                allowedCombinations: [gear]
            )
        ) { XCTAssertEqual($0 as? DrivetrainError, .duplicateChainring(30)) }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20, 20],
                allowedCombinations: [gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateCassetteCog(20)
            )
        }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [gear, gear]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .duplicateCombination(gear)
            )
        }
    }

    func testRejectsCombinationsAbsentFromComponents() throws {
        let unknownChainring = try VirtualGear(chainring: 40, cog: 20)
        let unknownCog = try VirtualGear(chainring: 30, cog: 10)

        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [unknownChainring]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .unknownChainring(unknownChainring)
            )
        }
        XCTAssertThrowsError(
            try Drivetrain(
                chainrings: [30],
                cassetteCogs: [20],
                allowedCombinations: [unknownCog]
            )
        ) {
            XCTAssertEqual(
                $0 as? DrivetrainError,
                .unknownCassetteCog(unknownCog)
            )
        }
    }

    private func makeDrivetrain(cogs: [Int]) throws -> Drivetrain {
        let gears = try cogs.map {
            try VirtualGear(chainring: 30, cog: $0)
        }
        return try Drivetrain(
            chainrings: [30],
            cassetteCogs: cogs,
            allowedCombinations: gears
        )
    }
    /// The gears a rider gets before describing any bike at all.
    func testVirtualLadderIsTwentyFourGearsEveryOneEncodable() throws {
        let drivetrain = try Drivetrain.virtualLadder()

        XCTAssertEqual(drivetrain.gears.count, 24)
        XCTAssertEqual(drivetrain.referenceIndex, 11)
        // Judged on the value the trainer is actually sent, which is what any
        // claim about proven hardware limits can honestly cover.
        let reference = drivetrain.referenceGear.ratio
        XCTAssertEqual(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference:
                    TrainerSafety.referenceCircumferenceMillimeters,
                referenceRatio: reference,
                selectedRatio: drivetrain.gears.first!.ratio
            ),
            657.8125,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try WheelCircumferenceScaler.effectiveCircumference(
                neutralCircumference:
                    TrainerSafety.referenceCircumferenceMillimeters,
                referenceRatio: reference,
                selectedRatio: drivetrain.gears.last!.ratio
            ),
            4_815.1875,
            accuracy: 0.001
        )
        for gear in drivetrain.gears {
            let circumference = try WheelCircumferenceScaler
                .effectiveCircumference(
                    neutralCircumference:
                        TrainerSafety.referenceCircumferenceMillimeters,
                    referenceRatio: reference,
                    selectedRatio: gear.ratio
                )
            XCTAssertLessThanOrEqual(
                circumference,
                WahooKickrCommand.maximumCircumferenceMillimeters,
                "Virtual gear \(gear.chainring)/\(gear.cog) would ask for "
                    + "\(circumference) mm, which the command cannot express"
            )
        }
        let ratios = drivetrain.gears.map(\.ratio)
        XCTAssertEqual(ratios, ratios.sorted())
    }

    /// A riding app may set its own wheel size, and the reference app does. The
    /// ladder is rebuilt around whatever it asks for, so the proven range has to
    /// hold the ladder shifted as well as the ladder itself. This once left a
    /// window of 2000-2098 mm, which refused a 700x25c wheel at 2105 mm.
    func testVirtualLadderRebuildsForOrdinaryRoadWheelSizes() throws {
        // 700x23c, 700x25c and 700x28c, the sizes a riding app really sends.
        for millimeters in [2096.0, 2105.0, 2136.0] {
            let drivetrain = try Drivetrain.virtualLadder()
            XCTAssertNoThrow(
                try ConfirmedGearEngine(
                    drivetrain: drivetrain,
                    wheelSizeMillimeters: millimeters
                ),
                "A riding app asking for a \(Int(millimeters)) mm wheel must not "
                    + "be refused: the ladder has to leave room for it"
            )
        }
    }

    /// 2200 mm is not a guess. FulGaz was watched sending exactly this, twice,
    /// as part of starting a ride; the capture is docs/fulgaz-app-tap-run.log.
    /// It was refused at the time, which meant Virtual Gears and FulGaz could
    /// not work together at all.
    ///
    /// It is a rider's setting rather than anything FulGaz chose — the default
    /// is 2098 mm — which is the whole reason a range is needed here instead of
    /// a list of values seen in the wild.
    func testAWheelSizeARiderTypedIntoTheirRidingAppIsAccepted() throws {
        let drivetrain = try Drivetrain.virtualLadder()
        XCTAssertNoThrow(
            try ConfirmedGearEngine(
                drivetrain: drivetrain,
                wheelSizeMillimeters: 2_200
            ),
            "A rider set this in FulGaz and it was sent at ride start. "
                + "Refusing it leaves them with no gears at all"
        )
    }

    /// A 650b wheel at 1900 mm used to be refused, because the old range
    /// stopped at 500 mm and the easiest gear needs 475 mm. Nothing about the
    /// trainer required that: it acknowledged 425 mm and, in an earlier probe,
    /// 0.1 mm. The limit was our own record-keeping, and this is the wheel it
    /// cost.
    func testA650bWheelIsAccepted() throws {
        let drivetrain = try Drivetrain.virtualLadder()
        XCTAssertNoThrow(
            try ConfirmedGearEngine(
                drivetrain: drivetrain,
                wheelSizeMillimeters: 1_900
            )
        )
    }

    /// The guard that stops this whole class of bug coming back.
    ///
    /// Virtual Gears kept discovering it was too narrow one riding app at a
    /// time — a 700x25c wheel, then one a rider set in FulGaz — because the
    /// wheel sizes it accepted were never declared anywhere. They fell out of
    /// where the gear ladder happened to sit inside an unrelated range, so
    /// nothing failed until a real app asked.
    ///
    /// This walks every wheel size Virtual Gears claims to support, in tenths
    /// of a millimetre, and insists all twenty-four gears build and encode at
    /// each one. Widening the gears or narrowing the window now breaks the
    /// build instead of a ride.
    func testEveryGearEncodesAtEverySupportedWheelSize() throws {
        let drivetrain = try Drivetrain.virtualLadder()
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        let steps = Int(
            ((window.upperBound - window.lowerBound)
                / TrainerSafety.commandStepMillimeters).rounded()
        )
        for step in 0...steps {
            let wheelSize = window.lowerBound
                + Double(step) * TrainerSafety.commandStepMillimeters
            XCTAssertNoThrow(
                try ConfirmedGearEngine(
                    drivetrain: drivetrain,
                    wheelSizeMillimeters: wheelSize
                ),
                "Virtual Gears says it supports a \(wheelSize) mm wheel, but "
                    + "cannot build its gears around one"
            )
        }
    }

    /// The window is a decision, so it has to stay a decision someone can
    /// defend. These are the wheels it exists for.
    func testTheSupportedWindowCoversEveryRealBicycleWheel() {
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        for (wheel, millimeters) in [
            ("650b", 1_900.0),
            ("700x25c", 2_105.0),
            ("a size seen set by hand in a riding app", 2_200.0),
            ("29er", 2_326.0)
        ] {
            XCTAssertTrue(
                window.contains(millimeters),
                "A rider on \(wheel) at \(millimeters) mm would be refused"
            )
        }
    }

}
