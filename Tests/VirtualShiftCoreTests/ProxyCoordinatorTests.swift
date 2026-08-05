import Foundation
import XCTest
@testable import VirtualShiftCore

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
        suiteName = "VirtualShiftTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        coordinator = ProxyCoordinator(
            kickr: trainer,
            click: shifter,
            peripheral: ridingApp,
            screen: screen,
            diagnostics: ProductDiagnosticsStore(),
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

    /// The bug that started this. FulGaz sends its own wheel size mid-ride,
    /// which changes what the gears are scaled around but not what the trainer
    /// is owed back. The app used to confuse the two and leave the trainer on
    /// the riding app's number, quietly distorting every later ride.
    func testARidingAppsOwnWheelSizeDoesNotChangeWhatTheTrainerIsOwed() async throws {
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

        XCTAssertEqual(coordinator.borrowedNeutralMillimeters, neutral)

        await coordinator.stopRide()

        XCTAssertEqual(trainer.currentWheelSizeMillimeters, neutral)
        XCTAssertNotEqual(trainer.currentWheelSizeMillimeters, ridingAppWheelSize)
    }

    /// The three ways a ride can end used to disagree about the number to hand
    /// back, which is how the bug hid: whichever path you read looked sensible
    /// on its own. They are checked together here for that reason.
    func testEveryWayARideCanEndHandsBackTheSameSize() async throws {
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
        defaults.set(neutral, forKey: "VirtualShift.unfinishedRideBaselineMillimeters")
        coordinator.restoreInterruptedRideIfNeeded()
        try await settle { self.trainer.currentWheelSizeMillimeters != nil }
        let afterCrashRecovery = trainer.currentWheelSizeMillimeters

        XCTAssertEqual(afterNormalStop, neutral)
        XCTAssertEqual(afterCrashRecovery, neutral)
        XCTAssertEqual(afterNormalStop, afterCrashRecovery)
    }

    func testAnUnfinishedRideIsForgottenOnceTheTrainerIsPutRight() async throws {
        try await startRide()
        XCTAssertNotNil(
            defaults.object(forKey: "VirtualShift.unfinishedRideBaselineMillimeters")
        )

        await coordinator.stopRide()

        XCTAssertNil(
            defaults.object(forKey: "VirtualShift.unfinishedRideBaselineMillimeters")
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

    /// A ride that cannot start must still put the trainer back, because the
    /// initial gear may already have been set by then.
    func testAFailedStartStillPutsTheTrainerBack() async throws {
        trainer.failNextWahooCommand = true
        coordinator.startRide(configuration: makeConfiguration())
        try await settle {
            if case .failed = self.coordinator.state { return true }
            return false
        }

        XCTAssertFalse(screen.keepAwake)
        XCTAssertTrue(trainer.didDisconnect)
    }
}
