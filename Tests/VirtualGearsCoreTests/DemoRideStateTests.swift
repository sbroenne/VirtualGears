import XCTest
@testable import VirtualGearsCore

final class DemoRideStateTests: XCTestCase {
    func testDemoStartsOnTheConfiguredReferenceGear() throws {
        let configuration = AppConfiguration.demo
        let drivetrain = try XCTUnwrap(configuration.drivetrain)

        let state = DemoRideState(configuration: configuration)

        XCTAssertEqual(state.gearSequence, drivetrain.gears)
        XCTAssertEqual(state.selectedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(state.displayedGear, drivetrain.referenceGear)
    }

    func testDemoShiftsWithoutLeavingTheGearLadder() {
        var state = DemoRideState(configuration: .demo)

        for _ in 0..<100 {
            state.shift(.easier)
        }
        state.settle()
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertFalse(state.canShiftEasier)

        for _ in 0..<100 {
            state.shift(.harder)
        }
        state.settle()
        XCTAssertEqual(state.selectedIndex, state.gearSequence.count - 1)
        XCTAssertFalse(state.canShiftHarder)
    }

    func testChangingGearTypeRebuildsTheLocalDemoOnly() throws {
        var state = DemoRideState(configuration: .demo)
        var realBike = AppConfiguration.demo
        realBike.usesVirtualGears = false
        let drivetrain = try XCTUnwrap(realBike.drivetrain)

        state.use(realBike)

        XCTAssertEqual(state.gearSequence, drivetrain.gears)
        XCTAssertEqual(state.selectedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(state.displayedGear, drivetrain.referenceGear)
    }

    /// The demo must obey the same rule as a real ride: nothing is shown until
    /// the trainer has said yes.
    func testTheDemoOnlyShowsAGearTheTrainerHasConfirmed() {
        var state = DemoRideState(configuration: .demo)
        let start = state.selectedIndex

        state.shift(.harder)

        XCTAssertEqual(state.requestedIndex, start + 1)
        XCTAssertEqual(state.selectedIndex, start, "shown gear must not move yet")
        XCTAssertTrue(state.isAwaitingTrainer)
        XCTAssertFalse(state.isSettled)

        XCTAssertTrue(state.confirmPendingChange())

        XCTAssertEqual(state.selectedIndex, start + 1)
        XCTAssertFalse(state.isAwaitingTrainer)
        XCTAssertTrue(state.isSettled)
    }

    /// The wheel sizes the demo shows are the real ones, not illustrative
    /// numbers, so they must match the shipping scaler exactly.
    func testTheDemoReportsTheRealWheelSizeForTheGear() throws {
        var state = DemoRideState(configuration: .demo)
        let drivetrain = try XCTUnwrap(AppConfiguration.demo.drivetrain)
        // Gears are scaled from the gear the bike is actually parked in, not
        // from the ladder's own starting gear. On the demo bike those differ,
        // which is exactly the case that used to be silently wrong.
        let reference = try XCTUnwrap(AppConfiguration.demo.parkedGear).ratio

        XCTAssertEqual(
            state.wheelSizeMillimeters,
            TrainerSafety.referenceCircumferenceMillimeters
        )

        for _ in 0..<3 {
            state.shift(.harder)
        }
        state.settle()

        let expected = try WheelCircumferenceScaler.effectiveCircumference(
            neutralCircumference: TrainerSafety
                .referenceCircumferenceMillimeters,
            referenceRatio: reference,
            selectedRatio: drivetrain.gears[state.selectedIndex].ratio
        )
        XCTAssertEqual(
            try XCTUnwrap(state.circumferenceMillimeters),
            expected,
            accuracy: 0.001
        )
    }

    /// A harder gear must mean a larger wheel size, because that is the whole
    /// mechanism the demo exists to show.
    func testHarderGearsAskForALargerWheel() throws {
        var state = DemoRideState(configuration: .demo)
        let easy = try XCTUnwrap(state.circumferenceMillimeters)

        state.shift(.harder)
        state.settle()
        let harder = try XCTUnwrap(state.circumferenceMillimeters)
        XCTAssertGreaterThan(harder, easy)

        state.shift(.easier)
        state.shift(.easier)
        state.settle()
        let easier = try XCTUnwrap(state.circumferenceMillimeters)
        XCTAssertLessThan(easier, easy)
    }

    /// The bytes on screen must be the bytes the app would really send.
    func testTheDemoShowsTheRealCommandBytes() throws {
        var state = DemoRideState(configuration: .demo)
        state.shift(.harder)
        state.settle()

        let circumference = try XCTUnwrap(state.circumferenceMillimeters)
        let expected = try WahooKickrCommand.setWheelCircumference(
            millimeters: circumference
        )
        let text = Array(expected)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")

        XCTAssertEqual(state.commandDescription, text)
        XCTAssertTrue(try XCTUnwrap(state.commandDescription).hasPrefix("48 "))
    }

    /// The simulated riding app owns the terrain and the rider owns the gears.
    /// Moving one must never move the other.
    func testTheRidingAppTerrainAndTheGearsDoNotDisturbEachOther() {
        var state = DemoRideState(configuration: .demo)
        let gearBefore = state.selectedIndex

        for _ in 0..<5 {
            state.advanceRoute()
        }
        XCTAssertEqual(state.selectedIndex, gearBefore)
        XCTAssertNotEqual(state.route.step, 0)

        let terrainBefore = state.route.gradePercent
        state.shift(.harder)
        state.settle()
        XCTAssertEqual(state.route.gradePercent, terrainBefore)
        XCTAssertNotEqual(state.selectedIndex, gearBefore)
    }

    func testTheRouteLoopsAndAlwaysDescribesItself() {
        var route = DemoRoute()
        var seen = Set<String>()
        for _ in 0..<DemoRoute.gradesPercent.count {
            seen.insert(route.terrainDescription)
            route.advance()
        }

        XCTAssertEqual(route.step, DemoRoute.gradesPercent.count)
        XCTAssertEqual(route.gradePercent, DemoRoute.gradesPercent[0])
        XCTAssertTrue(seen.contains("Flat"))
        XCTAssertTrue(seen.contains(where: { $0.hasPrefix("Climbing") }))
        XCTAssertTrue(seen.contains(where: { $0.hasPrefix("Descending") }))
    }

    /// Changing the gear choice keeps the rider where they are on the route.
    func testChangingGearsKeepsTheRouteRunning() {
        var state = DemoRideState(configuration: .demo)
        for _ in 0..<4 {
            state.advanceRoute()
        }
        var realBike = AppConfiguration.demo
        realBike.usesVirtualGears = false

        state.use(realBike)

        XCTAssertEqual(state.route.step, 4)
    }

    /// The simulated trainer must speak the trainer's real language, or the
    /// demo proves nothing about the shipping code.
    func testTheSimulatedTrainerRepliesInTheRealWireFormat() throws {
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: 2415
        )
        let reply = try XCTUnwrap(DemoTrainer.reply(to: command))
        let response = try WahooKickrResponse.decode(reply)

        XCTAssertTrue(response.verifies(command: command))
        XCTAssertTrue(response.confirmsSuccess(for: command))
    }

    func testTheSimulatedTrainerIgnoresAnythingItWasNotAsked() {
        XCTAssertNil(DemoTrainer.reply(to: WahooKickrCommand.unlock))
        XCTAssertNil(DemoTrainer.reply(to: Data()))
    }
}
