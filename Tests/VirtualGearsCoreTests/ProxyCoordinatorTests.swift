import Foundation
import XCTest
@testable import VirtualGearsCore

/// The ride, checked end to end against a stand-in trainer.
///
/// Everything here covers a bug that really happened. Two careful code reviews
/// read this logic and passed it; a rider found all three inside twenty
/// minutes. The reason is that none of it could be run without hardware, so
/// nothing ever did. These tests exist so that stays fixed.
@MainActor
final class ProxyCoordinatorTests: XCTestCase {
    private var trainer: FakeTrainer!
    private var ridingApp: FakeRidingAppLink!
    private var shifter: FakeShifter!
    private var screen: FakeScreen!
    private var defaults: UserDefaults!
    private var coordinator: ProxyCoordinator!
    private var suiteName: String!

    /// The wheel size the trainer is put back to, and the one the gears are
    /// built around unless a riding app says otherwise.
    private var neutral: Double {
        TrainerSafety.referenceCircumferenceMillimeters
    }

    override func setUp() async throws {
        makeCoordinator()
    }

    private func makeCoordinator() {
        trainer = FakeTrainer()
        ridingApp = FakeRidingAppLink()
        shifter = FakeShifter()
        screen = FakeScreen()
        suiteName = "VirtualGearsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        coordinator = ProxyCoordinator(
            kickr: trainer,
            click: shifter,
            peripheral: ridingApp,
            screen: screen,
            defaults: defaults
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeConfiguration(
        virtualGears: Bool = true
    ) -> AppConfiguration {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR", id: trainer.selectedID!)
        configuration.usesVirtualGears = virtualGears
        return configuration
    }

    /// Runs a ride up to the point where the riding app is connected.
    private func startRide(virtualGears: Bool = true) async throws {
        coordinator.startRide(
            configuration: makeConfiguration(virtualGears: virtualGears)
        )
        try await settle { self.coordinator.state == .active }
    }

    /// Lets the ride's own tasks run until a condition holds. The coordinator
    /// does its work in detached tasks, so the alternative is guessing at sleep
    /// lengths, which makes tests that pass for the wrong reason.
    private func settle(
        timeout: Duration = .seconds(5),
        until condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the ride to reach the expected state")
    }

    // MARK: - What the trainer is left on

    func testStoppingPutsTheTrainerBackOnTheSizeItStartedWith() async throws {
        try await startRide()
        coordinator.shift(.harder)
        try await settle { self.coordinator.confirmedGearIndex ?? 0 > 0 }

        await coordinator.stopRide()

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, neutral)
    }

    /// Stopping Virtual Gears no longer ends the riding app's ride. A wheel size
    /// set through the standard interface is therefore the neutral setting to
    /// leave in place; overwriting it would change a ride another app still owns.
    func testStoppingVirtualShiftingPreservesTheRidingAppsWheelSize() async throws {
        try await startRide(virtualGears: false)
        // What a riding app really sends: a 700x25c wheel, in tenths.
        let ridingAppWheelSize: Double = 2_105

        _ = await ridingApp.send(
            .setWheelCircumference(
                tenthsOfMillimeter: UInt16(ridingAppWheelSize * 10)
            )
        )
        try await settle {
            self.coordinator.sessionBaselineMillimeters == ridingAppWheelSize
        }

        XCTAssertEqual(coordinator.preGearBaselineMillimeters, neutral)

        await coordinator.stopRide()

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, ridingAppWheelSize)
    }

    /// A deliberate Stop leaves the still-running riding app's own setting in
    /// place. After an interruption, Virtual Gears resets to the saved baseline.
    func testNormalStopAndCrashRecoveryRespectWhoStillOwnsTheRide() async throws {
        try await startRide(virtualGears: false)
        _ = await ridingApp.send(
            .setWheelCircumference(tenthsOfMillimeter: 21_050)
        )
        try await settle {
            self.coordinator.sessionBaselineMillimeters == 2_105
        }
        await coordinator.stopRide()
        let afterNormalStop = trainer.currentWheelSizeMillimeters

        // A ride that never got to stop, finished at the next launch.
        makeCoordinator()
        defaults.set(neutral, forKey: "VirtualGears.unfinishedRideBaselineMillimeters")
        coordinator.resetInterruptedRideBaselineIfNeeded()
        try await settle { self.trainer.currentWheelSizeMillimeters != nil }
        let afterCrashRecovery = trainer.currentWheelSizeMillimeters

        XCTAssertEqual(afterNormalStop, 2_105)
        XCTAssertEqual(afterCrashRecovery, neutral)
        XCTAssertNotEqual(afterNormalStop, afterCrashRecovery)
    }

    func testAnUnfinishedRideIsForgottenOnceTheTrainerIsPutRight() async throws {
        try await startRide()
        XCTAssertNotNil(
            defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters")
        )

        await coordinator.stopRide()

        XCTAssertNil(
            defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters")
        )
    }

    // MARK: - Holding a button to keep shifting

    /// Holding used to fire on a 300 ms timer and silently drop any beat that
    /// arrived while the trainer was still confirming. On a real ride the
    /// trainer is nearly always busy, so almost every beat was dropped and
    /// holding did nothing. The sweep is now paced by the trainer instead.
    func testHoldingKeepsShiftingWhileTheTrainerIsSlow() async throws {
        trainer.wahooConfirmationDelay = .milliseconds(40)
        try await startRide()
        let startIndex = coordinator.confirmedGearIndex ?? 0

        coordinator.beginHold(.harder)
        try await settle {
            (self.coordinator.confirmedGearIndex ?? 0) >= startIndex + 3
        }
        coordinator.endHold()

        XCTAssertGreaterThanOrEqual(
            coordinator.confirmedGearIndex ?? 0,
            startIndex + 3,
            "Holding should keep shifting even when the trainer is slow to confirm"
        )
    }

    func testLettingGoStopsTheSweep() async throws {
        trainer.wahooConfirmationDelay = .milliseconds(20)
        try await startRide()

        coordinator.beginHold(.harder)
        try await settle { (self.coordinator.confirmedGearIndex ?? 0) >= 2 }
        coordinator.endHold()

        // One gear may already be in flight, so the sweep is allowed to land
        // one more. What it must not do is carry on.
        try await Task.sleep(for: .milliseconds(200))
        let settledIndex = coordinator.confirmedGearIndex
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(coordinator.confirmedGearIndex, settledIndex)
    }

    func testAFailedShiftEndsTheSweepRatherThanRunningOn() async throws {
        try await startRide()

        coordinator.beginHold(.harder)
        trainer.failNextWahooCommand = true
        try await Task.sleep(for: .milliseconds(300))
        let indexAfterFailure = coordinator.confirmedGearIndex
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(
            coordinator.confirmedGearIndex,
            indexAfterFailure,
            "A refused gear should stop the sweep, not let it run to the end"
        )
        coordinator.endHold()
    }

    func testHoldingStopsAtTheHardestGear() async throws {
        try await startRide()

        coordinator.beginHold(.harder)
        try await Task.sleep(for: .seconds(1))
        coordinator.endHold()

        XCTAssertEqual(
            coordinator.confirmedGearIndex,
            coordinator.gearSequence.count - 1
        )
    }

    // MARK: - Changing gears mid-ride

    /// Changing the drivetrain used to stop and restart the ride, and stopping
    /// removes the service the riding app is connected to. The rider lost their
    /// session and had to go back to the PC because they changed a setting.
    func testChangingGearsDoesNotDropTheRidingApp() async throws {
        try await startRide()
        XCTAssertEqual(ridingApp.advertisingStopCount, 0)

        var updated = makeConfiguration()
        updated.usesVirtualGears = false
        await coordinator.changeDrivetrain(updated)

        XCTAssertEqual(
            ridingApp.advertisingStopCount,
            0,
            "Changing gears must not pull the trainer out from under the riding app"
        )
        XCTAssertTrue(ridingApp.isAdvertising)
        XCTAssertEqual(coordinator.state, .active)
    }

    func testChangingGearsActuallyChangesTheGears() async throws {
        try await startRide()
        let before = coordinator.gearSequence

        var updated = makeConfiguration()
        updated.usesVirtualGears = false
        await coordinator.changeDrivetrain(updated)

        XCTAssertNotEqual(coordinator.gearSequence, before)
        XCTAssertFalse(coordinator.gearSequence.isEmpty)
    }

    /// A trainer that refuses the new gears must not cost the rider their ride.
    func testARefusedGearChangeKeepsTheRideAndTheOldGears() async throws {
        try await startRide()
        let before = coordinator.gearSequence

        var updated = makeConfiguration()
        updated.usesVirtualGears = false
        trainer.failNextWahooCommand = true
        await coordinator.changeDrivetrain(updated)

        XCTAssertEqual(coordinator.gearSequence, before)
        XCTAssertEqual(coordinator.state, .active)
        XCTAssertTrue(ridingApp.isAdvertising)
    }

    // MARK: - Starting and stopping

    func testTheRidingAppOnlyAppearsOnceTheTrainerIsConnected() async throws {
        trainer.isReady = false
        coordinator.startRide(configuration: makeConfiguration())
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(
            ridingApp.isAdvertising,
            "Nothing should be offered to the riding app before the trainer is in hand"
        )

        trainer.isReady = true
        try await settle { self.coordinator.state == .active }

        XCTAssertTrue(ridingApp.isAdvertising)
    }

    func testTheScreenIsKeptAwakeWhileRidingAndReleasedAfterwards() async throws {
        try await startRide()
        XCTAssertTrue(screen.keepAwake)

        await coordinator.stopRide()

        XCTAssertFalse(screen.keepAwake)
    }

    func testNormalStopKeepsEveryBluetoothLinkReady() async throws {
        try await startRide()
        ridingApp.subscribedAppCount = 1
        let data = Data([0x01, 0x02])

        await coordinator.stopRide()
        trainer.eventHandler?(.rawBikeData(data))

        XCTAssertFalse(ridingApp.didStopAcceptingCommands)
        XCTAssertTrue(ridingApp.acceptingCommands)
        XCTAssertTrue(ridingApp.isAdvertising)
        XCTAssertEqual(ridingApp.subscribedAppCount, 1)
        XCTAssertEqual(ridingApp.advertisingStopCount, 0)
        XCTAssertEqual(ridingApp.relayedBikeData, [data])
        XCTAssertFalse(trainer.didDisconnect)
        XCTAssertFalse(shifter.didDisconnect)
    }

    func testStartingAgainReusesTheRidingAppLink() async throws {
        try await startRide()
        let ridingAppID = UUID()

        await coordinator.stopRide()
        let whileStopped = await ridingApp.send(.startOrResume, from: ridingAppID)
        XCTAssertEqual(whileStopped?.result, .success)
        XCTAssertFalse(
            trainer.ftmsRequests.contains(.stopOrPause(.stop)),
            "Virtual Gears Stop must not stop the riding app's session"
        )

        coordinator.startRide(configuration: makeConfiguration())
        try await settle { self.coordinator.state == .active }
        let afterRestart = await ridingApp.send(.requestControl, from: ridingAppID)

        XCTAssertEqual(afterRestart?.result, .success)
        XCTAssertTrue(ridingApp.isAdvertising)
        XCTAssertEqual(ridingApp.advertisingStopCount, 0)
    }

    func testPCWheelSizeDuringRestartWaitsAndRebasesTheNewRide() async throws {
        try await startRide(virtualGears: false)
        await coordinator.stopRide()
        trainer.wahooConfirmationDelay = .milliseconds(50)

        coordinator.startRide(configuration: makeConfiguration(virtualGears: false))
        let command = Task {
            await self.ridingApp.send(
                .setWheelCircumference(tenthsOfMillimeter: 21_050)
            )
        }

        try await settle { self.coordinator.state == .active }
        let result = await command.value

        XCTAssertEqual(result?.result, .success)
        XCTAssertEqual(coordinator.sessionBaselineMillimeters, 2_105)
        await coordinator.stopRide()
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2_105)
    }

    func testRestartKeepsTheRidingAppsBaselineWithoutAskingItToResend() async throws {
        try await startRide(virtualGears: false)
        _ = await ridingApp.send(
            .setWheelCircumference(tenthsOfMillimeter: 21_050)
        )
        try await settle { self.coordinator.sessionBaselineMillimeters == 2_105 }
        await coordinator.stopRide()

        coordinator.startRide(configuration: makeConfiguration(virtualGears: false))
        try await settle { self.coordinator.state == .active }

        XCTAssertEqual(coordinator.sessionBaselineMillimeters, 2_105)
        XCTAssertTrue(coordinator.ridingAppSetWheelSize)
        await coordinator.stopRide()
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2_105)
    }

    func testStopWaitsForAnInFlightPCWheelSizeWithoutRejectingIt() async throws {
        try await startRide(virtualGears: false)
        trainer.wahooConfirmationDelay = .milliseconds(100)

        let command = Task {
            await self.ridingApp.send(
                .setWheelCircumference(tenthsOfMillimeter: 21_050)
            )
        }
        try await settle { self.trainer.wahooCommandCount == 2 }
        await coordinator.stopRide()

        let result = await command.value
        XCTAssertEqual(result?.result, .success)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2_105)
    }

    func testPCCommandArrivingDuringStopRunsAfterTheBaselineReset() async throws {
        try await startRide()
        trainer.wahooConfirmationDelay = .milliseconds(100)

        let stop = Task { await self.coordinator.stopRide() }
        try await settle { self.coordinator.state == .stopping }
        let command = Task {
            await self.ridingApp.send(
                .setWheelCircumference(tenthsOfMillimeter: 19_000)
            )
        }

        await stop.value
        let result = await command.value
        XCTAssertEqual(result?.result, .success)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 1_900)
    }

    func testQueuedCommandFromADisconnectedRidingAppNeverReachesTheTrainer() async throws {
        try await startRide()
        trainer.wahooConfirmationDelay = .milliseconds(100)
        let app = UUID()

        let stop = Task { await self.coordinator.stopRide() }
        try await settle { self.coordinator.state == .stopping }
        let command = Task {
            await self.ridingApp.send(
                .setWheelCircumference(tenthsOfMillimeter: 19_000),
                from: app
            )
        }
        await Task.yield()
        ridingApp.disconnect(app)
        ridingApp.subscribe(app)

        await stop.value
        let result = await command.value
        XCTAssertEqual(result?.result, .controlNotPermitted)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, neutral)
    }

    func testFailedStopRecoveryUsesTheLiveRidingAppBaseline() async throws {
        try await startRide(virtualGears: false)
        _ = await ridingApp.send(
            .setWheelCircumference(tenthsOfMillimeter: 21_050)
        )
        try await settle { self.coordinator.sessionBaselineMillimeters == 2_105 }
        trainer.failNextWahooCommand = true

        await coordinator.stopRide()
        guard case .failed = coordinator.state else {
            return XCTFail("The refused baseline reset must remain visible")
        }
        coordinator.resetInterruptedRideBaselineIfNeeded()
        try await settle {
            self.trainer.currentWheelSizeMillimeters == 2_105
                && self.defaults.object(
                    forKey: "VirtualGears.unfinishedRideBaselineMillimeters"
                ) == nil
        }

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2_105)
    }

    func testShutdownWaitsForAnExistingStopBeforeDisconnecting() async throws {
        try await startRide()
        trainer.wahooConfirmationDelay = .milliseconds(100)

        let stop = Task { await self.coordinator.stopRide() }
        try await settle { self.coordinator.state == .stopping }
        await coordinator.shutdown()
        await stop.value

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, neutral)
        XCTAssertTrue(trainer.didDisconnect)
        XCTAssertTrue(shifter.didDisconnect)
    }

    func testFullShutdownDisconnectsOwnedEquipmentButNotTheRidingApp() async throws {
        try await startRide()

        await coordinator.shutdown()

        XCTAssertTrue(ridingApp.isAdvertising)
        XCTAssertTrue(ridingApp.acceptingCommands)
        XCTAssertEqual(ridingApp.advertisingStopCount, 0)
        XCTAssertTrue(trainer.didDisconnect)
        XCTAssertTrue(shifter.didDisconnect)
    }

    /// A ride that cannot start must still put the trainer back, because the
    /// initial gear may already have been set by then. This is the third of the
    /// three ways a ride can end, and the one most easily forgotten.
    func testAFailedStartStillPutsTheTrainerBack() async throws {
        trainer.failNextWahooCommand = true
        coordinator.startRide(configuration: makeConfiguration())
        try await settle {
            if case .failed = self.coordinator.state { return true }
            return false
        }

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, neutral)
        XCTAssertNil(
            defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"),
            "A trainer that has been put right should leave nothing to recover"
        )
        XCTAssertEqual(coordinator.failure?.trainerNeedsBaselineReset, false)
        XCTAssertFalse(screen.keepAwake)
        XCTAssertFalse(trainer.didDisconnect)
    }

    /// Stop is reachable while the ride is still connecting, which is exactly
    /// when a rider uses it: the trainer is asleep, they give up and tap Stop,
    /// and the trainer wakes a moment later. If the start carries on it writes
    /// the first gear's wheel size after the stop has put the trainer back, and
    /// the record that would have fixed it at the next launch is already gone.
    /// Stopping while the start is already failing must not invent a problem.
    ///
    /// The failing start puts the trainer back itself. If the stop then runs its
    /// whole body against the dead session it ends by telling the rider the
    /// baseline could not be reset, when it just was.
    func testStoppingWhileTheStartIsFailingDoesNotInventAResetProblem() async throws {
        trainer.deniesFTMSControl = true
        trainer.wahooConfirmationDelay = .milliseconds(200)
        coordinator.startRide(configuration: makeConfiguration())

        // The window is narrow and exact. Stop has to land after the failing
        // start has committed to resetting the baseline - its reset write
        // is the one Wahoo command a denied start makes - but before it has
        // finished and torn the session down. Tapping any earlier and the
        // start's own catch stands down instead.
        try await settle { self.trainer.wahooCommandCount == 1 }
        await coordinator.stopRide()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(
            trainer.wheelSizeHistory.last,
            neutral,
            "The failing start put the trainer back, so it really is neutral"
        )
        guard case let .failed(message) = coordinator.state else {
            return XCTFail("The start was denied control, so it must say so")
        }
        XCTAssertFalse(
            message.contains("could not be reset"),
            "The baseline was reset. Recording another fault would be wrong: "
                + message
        )
        XCTAssertTrue(
            message.contains("denied FTMS control"),
            "The real reason the ride did not start must survive the stop, "
                + "not be overwritten by the stop's own noise: \(message)"
        )
    }

    /// A stop landing while the first gear is already on its way to the trainer.
    ///
    /// Worth knowing what this does and does not prove: it still passes if the
    /// stop's cancel-and-await is deleted, because the `startMayProceed` gates
    /// catch this case on their own. It is kept as a statement of the invariant,
    /// not as the guard on that line. The test below is the one that fails when
    /// the wait is removed.
    func testStoppingWhileTheFirstGearIsInFlightLeavesTheTrainerNeutral() async throws {
        trainer.wahooConfirmationDelay = .milliseconds(200)
        coordinator.startRide(configuration: makeConfiguration())
        // Stop the instant the first gear is on the wire, not before it.
        try await settle { self.trainer.wahooCommandCount == 1 }

        await coordinator.stopRide()

        XCTAssertEqual(
            trainer.wheelSizeHistory.last,
            neutral,
            "The last thing written to the trainer must be the neutral wheel "
                + "size, whatever was already in flight when the rider stopped"
        )
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(
            defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters")
        )
    }

    func testStoppingWhileStillConnectingDoesNotLeaveAGearOnTheTrainer() async throws {
        trainer.isReady = false
        trainer.wahooConfirmationDelay = .milliseconds(50)
        coordinator.startRide(configuration: makeConfiguration())
        try await settle { self.coordinator.state == .connecting }

        // The trainer wakes at the same moment the rider gives up.
        trainer.isReady = true
        await coordinator.stopRide()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(
            trainer.currentWheelSizeMillimeters,
            neutral,
            "A stop must win: the trainer cannot be left carrying a gear"
        )
        XCTAssertNil(
            defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters")
        )
    }

    /// Letting go of the button has to be obeyed unconditionally. It used to be
    /// turned away whenever the gears were being rebuilt, which is precisely
    /// when a riding app resets the wheel size mid-sweep, leaving the sweep
    /// running to the end of the cassette with nobody touching the button.
    func testLettingGoIsObeyedEvenWhileTheGearsAreBeingRebuilt() async throws {
        trainer.wahooConfirmationDelay = .milliseconds(30)
        try await startRide(virtualGears: false)

        coordinator.beginHold(.harder)
        try await settle { (self.coordinator.confirmedGearIndex ?? 0) >= 1 }

        // A riding app resets the wheel size while the sweep is running. The
        // rebuild waits for the sweep, so it is still in flight when the rider
        // lets go, which is the situation being tested.
        let rebuild = Task { [ridingApp] in
            await ridingApp?.send(
                .setWheelCircumference(tenthsOfMillimeter: 21_050)
            )
        }
        try await Task.sleep(for: .milliseconds(10))
        coordinator.endHold()
        _ = await rebuild.value

        let settledIndex = coordinator.confirmedGearIndex
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(
            coordinator.confirmedGearIndex,
            settledIndex,
            "The sweep must stop when the rider lets go, whatever else is happening"
        )
        XCTAssertNotEqual(
            coordinator.confirmedGearIndex,
            coordinator.gearSequence.count - 1,
            "A released button should not have swept to the hardest gear"
        )
    }
}
