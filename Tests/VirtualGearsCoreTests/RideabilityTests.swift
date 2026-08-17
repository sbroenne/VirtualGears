import XCTest
@testable import VirtualGearsCore

/// The tests that ask whether the gears are any good to ride, rather than
/// whether they are well formed.
///
/// The old tests checked structure — ordering, no duplicates, that
/// cross-chaining happened — and every one of them passed while the app was
/// handing riders shifts too small to feel and holes wide enough to stall in.
/// These run over every groupset the app ships, so a regression shows up on a
/// real bike rather than a made-up one.
final class RideabilityTests: XCTestCase {
    /// Every chainring and cassette pairing of every shipped groupset: the
    /// seventy-odd builds a rider could actually select.
    private struct Build {
        let name: String
        let chainrings: [Int]
        let cogs: [Int]
    }

    private var shippedBuilds: [Build] {
        GroupsetCatalog.groupsets.flatMap { groupset in
            groupset.chainrings.flatMap { chainring in
                groupset.cassettes.map { cassette in
                    Build(
                        name: "\(groupset.qualifiedName) "
                            + "\(chainring.name) \(cassette.name)",
                        chainrings: chainring.teeth,
                        cogs: cassette.cogs
                    )
                }
            }
        }
    }

    private func steps(_ drivetrain: Drivetrain) -> [Double] {
        let ratios = drivetrain.gears.map(\.ratio)
        return zip(ratios, ratios.dropFirst()).map { $1 / $0 - 1 }
    }

    func testEveryShippedGroupsetBuilds() throws {
        let builds = shippedBuilds
        XCTAssertGreaterThan(builds.count, 60)
        for build in builds {
            XCTAssertNoThrow(
                try Drivetrain.build(
                    chainrings: build.chainrings,
                    cassetteCogs: build.cogs
                ),
                build.name
            )
        }
    }

    /// A shift the rider cannot feel is not a gear. The old algorithm merged
    /// only *exactly* equal ratios, so near-identical ones survived: the
    /// smallest step it produced anywhere was 0.4%, on twelve of these builds.
    func testNoShiftIsTooSmallToFeel() throws {
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            for step in steps(drivetrain) {
                XCTAssertGreaterThanOrEqual(
                    step,
                    Drivetrain.perceptibleStepFraction,
                    "\(build.name) has a step of "
                        + String(format: "%.1f%%", step * 100)
                )
            }
        }
    }

    /// Big jumps that come from the cassette itself are real and must survive —
    /// an 11-34 genuinely steps 30 to 34. What must not survive is a hole *we*
    /// made by deleting the cogs that bridge the two chainrings, which the old
    /// proportional pruning did on five of these builds, once by 37%.
    func testNoGapIsWiderThanTheCassetteAlreadyMakes() throws {
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let cogs = build.cogs.sorted(by: >)
            let cassetteWorst = zip(cogs, cogs.dropFirst())
                .map { Double($0) / Double($1) - 1 }
                .max() ?? 0
            let allowed = max(cassetteWorst, 0.25)
            for step in steps(drivetrain) {
                XCTAssertLessThanOrEqual(
                    step,
                    allowed + 0.001,
                    "\(build.name) has a gap of "
                        + String(format: "%.0f%%", step * 100)
                )
            }
        }
    }

    /// The easiest gear a rider owns is the one they need on the steepest
    /// climb, and the hardest is what they sprint in. Neither may be quietly
    /// dropped in the name of tidying the ladder up.
    func testTheEasiestAndHardestGearAreAlwaysKept() throws {
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            XCTAssertEqual(
                drivetrain.gears.first?.chainring,
                build.chainrings.min(),
                build.name
            )
            XCTAssertEqual(
                drivetrain.gears.first?.cog,
                build.cogs.max(),
                build.name
            )
            XCTAssertEqual(
                drivetrain.gears.last?.chainring,
                build.chainrings.max(),
                build.name
            )
            XCTAssertEqual(
                drivetrain.gears.last?.cog,
                build.cogs.min(),
                build.name
            )
        }
    }

    /// A real electronic groupset in sequential mode gives a rider three to six
    /// more gears than the cassette has cogs — a 2x11 lands on fourteen to
    /// sixteen, which is exactly what Shimano quotes for Synchronized Shift.
    /// Pinning the band stops the cross-chain limit drifting and quietly
    /// handing riders a twenty-two speed bike.
    func testGearCountsMatchWhatAnElectronicGroupsetGives() throws {
        for build in shippedBuilds where build.chainrings.count > 1 {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let extra = drivetrain.gears.count - build.cogs.count
            XCTAssertGreaterThanOrEqual(extra, 3, build.name)
            XCTAssertLessThanOrEqual(extra, 6, build.name)
        }
    }

    /// A single chainring reaches the whole cassette, so the gears are the cogs
    /// and nothing else.
    func testASingleChainringGivesExactlyTheCassette() throws {
        for build in shippedBuilds where build.chainrings.count == 1 {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            XCTAssertEqual(drivetrain.gears.count, build.cogs.count, build.name)
        }
    }

    /// The chainring never gets smaller as the gear gets harder, and the gear
    /// always does. This is what makes a two-button controller make sense.
    func testEveryPressGivesAHarderGearOnTheSameOrABiggerRing() throws {
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let rings = drivetrain.gears.map(\.chainring)
            XCTAssertEqual(rings, rings.sorted(), build.name)
            let ratios = drivetrain.gears.map(\.ratio)
            XCTAssertEqual(ratios, ratios.sorted(), build.name)
        }
    }

    /// Big-big and small-small are the two corners a rider is told never to
    /// use, and the two the old cross-product invented on every drivetrain.
    func testTheCrossChainedCornersAreNeverOffered() throws {
        for build in shippedBuilds where build.chainrings.count > 1 {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let smallest = build.chainrings.min()
            let biggest = build.chainrings.max()
            for gear in drivetrain.gears {
                if gear.chainring == smallest {
                    XCTAssertNotEqual(gear.cog, build.cogs.min(), build.name)
                }
                if gear.chainring == biggest {
                    XCTAssertNotEqual(gear.cog, build.cogs.max(), build.name)
                }
            }
        }
    }

    // MARK: - The starting gear stays where it was put

    /// The regression this pins. The starting gear used to be worked out from
    /// `TrainerSafety`, so editing the wheel-size window moved the gear every
    /// rider begins in — a compact twelve-speed shifted ten per cent harder the
    /// last time that window was widened, and nobody noticed. It is declared
    /// now, so widening the window has to leave it alone.
    func testWideningTheWheelSizeWindowDoesNotMoveTheStartingGear() throws {
        let cogs = [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
        let normal = try Drivetrain.build(chainrings: [50, 34], cassetteCogs: cogs)
        let wider = try Drivetrain.build(
            chainrings: [50, 34],
            cassetteCogs: cogs,
            scaleRange: 0.2...(WahooKickrCommand.maximumCircumferenceMillimeters
                / 2_600)
        )

        XCTAssertEqual(normal.referenceGear, wider.referenceGear)
        XCTAssertEqual(normal.referenceIndex, wider.referenceIndex)
    }

    /// The default setup, pinned to the gear itself rather than an index, so a
    /// catalogue edit that moves it shows up as a failure and not a shrug.
    func testTheDefaultSetupStartsIn34By14() throws {
        var configuration = AppConfiguration()
        configuration.usesVirtualGears = false
        let drivetrain = try XCTUnwrap(configuration.drivetrain)

        XCTAssertEqual(drivetrain.gears.count, 16)
        XCTAssertEqual(drivetrain.referenceGear.chainring, 34)
        XCTAssertEqual(drivetrain.referenceGear.cog, 14)
        // 2.4286, the neutral ratio other virtual shifting systems settle on.
        XCTAssertEqual(drivetrain.referenceGear.ratio, 34.0 / 14.0, accuracy: 0.0001)
    }

    /// Every shipped build starts within a quarter of the declared 2.40, or the
    /// gear a rider begins in would depend on which bike they own.
    func testEveryShippedBuildStartsNearTheDeclaredRatio() throws {
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let ratio = drivetrain.referenceGear.ratio
            XCTAssertGreaterThan(ratio, Drivetrain.startingRatio * 0.8, build.name)
            XCTAssertLessThan(ratio, Drivetrain.startingRatio * 1.25, build.name)
        }
    }

    // MARK: - Every gear still reaches the trainer

    /// The old version of this checked one assumed parked gear. A rider parked
    /// somewhere else got gears that encoded fine in setup and then ran out of
    /// command range mid-ride, which is the failure this now covers.
    func testEveryGearEncodesFromEveryRecommendedParkedGear() throws {
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        for build in shippedBuilds {
            let drivetrain = try Drivetrain.build(
                chainrings: build.chainrings,
                cassetteCogs: build.cogs
            )
            let setup = PhysicalSetup(
                chainringTeeth: build.chainrings,
                cogTeeth: build.cogs
            )
            let parked = try XCTUnwrap(
                ParkedGearAdvice.suggestion(for: setup, simulating: drivetrain),
                build.name
            )
            for wheelSize in [window.lowerBound, window.upperBound] {
                XCTAssertNoThrow(
                    try ConfirmedGearEngine(
                        drivetrain: drivetrain,
                        wheelSizeMillimeters: wheelSize,
                        parkedGear: parked
                    ),
                    "\(build.name) parked in \(parked.name) at \(wheelSize) mm"
                )
            }
        }
    }

    /// Both shipped virtual ladders, from every parked gear the app would
    /// recommend for a real bike.
    func testEveryLadderEncodesFromTheRecommendedParkedGear() throws {
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        for ladder in GearLadderCatalog.ladders {
            let drivetrain = try ladder.drivetrain()
            for build in shippedBuilds {
                let setup = PhysicalSetup(
                    chainringTeeth: build.chainrings,
                    cogTeeth: build.cogs
                )
                guard let parked = ParkedGearAdvice.suggestion(
                    for: setup,
                    simulating: drivetrain
                ) else { continue }
                for wheelSize in [window.lowerBound, window.upperBound] {
                    XCTAssertNoThrow(
                        try ConfirmedGearEngine(
                            drivetrain: drivetrain,
                            wheelSizeMillimeters: wheelSize,
                            parkedGear: parked
                        ),
                        "\(ladder.name) on \(build.name) parked in \(parked.name)"
                    )
                }
            }
        }
    }
}
