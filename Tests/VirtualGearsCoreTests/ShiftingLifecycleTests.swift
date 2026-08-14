import XCTest
@testable import VirtualGearsCore

/// These cover the rules that decide when a ride may start, when losing trainer
/// control is worth recovering from, and whether the trainer is still carrying
/// a gear's wheel size after something went wrong.
///
/// They exist because each of those rules had a bug in it that no amount of
/// building or connecting would have shown: the failures only appear in the
/// order events arrive in, which is exactly what can be reproduced here and
/// cannot be reproduced reliably on a bike.
final class ShiftingLifecycleTests: XCTestCase {
    private func riding() -> ShiftingLifecycle {
        var lifecycle = ShiftingLifecycle()
        lifecycle.beginConnecting()
        lifecycle.markActive()
        return lifecycle
    }

    // MARK: - Where things stand

    func testAFreshLifecycleIsIdleAndShowsNoShiftingScreen() {
        let lifecycle = ShiftingLifecycle()
        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.failure)
        XCTAssertNil(lifecycle.shiftingID)
        XCTAssertFalse(lifecycle.isShiftingPresented)
        XCTAssertTrue(lifecycle.isNotShifting)
        XCTAssertTrue(lifecycle.canStart)
    }

    func testTheShiftingScreenIsShownFromConnectingUntilStopped() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.beginConnecting()
        XCTAssertTrue(lifecycle.isShiftingPresented)
        lifecycle.markActive()
        XCTAssertTrue(lifecycle.isShiftingPresented)
        lifecycle.markReconnecting()
        XCTAssertTrue(lifecycle.isShiftingPresented)
        XCTAssertNotNil(lifecycle.beginStopping())
        XCTAssertTrue(lifecycle.isShiftingPresented)
        lifecycle.finishStop(failures: [], trainerNeedsWheelSizeReset: false)
        XCTAssertFalse(lifecycle.isShiftingPresented)
    }

    func testShiftingCanBeStartedAgainAfterAFailure() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.refuseStart("Setup is incomplete")
        XCTAssertTrue(lifecycle.isFailed)
        XCTAssertTrue(lifecycle.canStart)
        XCTAssertFalse(lifecycle.isShiftingPresented)
    }

    func testStartingClearsAnEarlierFailure() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.refuseStart("Setup is incomplete")
        lifecycle.beginConnecting()
        XCTAssertNil(lifecycle.failure)
        XCTAssertEqual(lifecycle.state, .connecting)
    }

    // MARK: - Work belonging to an older ride

    func testWorkFromAnEarlierRunIsDisowned() {
        var lifecycle = ShiftingLifecycle()
        let first = lifecycle.beginConnecting()
        lifecycle.markActive()
        XCTAssertTrue(lifecycle.owns(first))

        lifecycle.finishStop(failures: [], trainerNeedsWheelSizeReset: false)
        let second = lifecycle.beginConnecting()

        XCTAssertFalse(lifecycle.owns(first))
        XCTAssertTrue(lifecycle.owns(second))
    }

    func testNothingIsOwnedOnceShiftingHasStopped() {
        var lifecycle = ShiftingLifecycle()
        let id = lifecycle.beginConnecting()
        lifecycle.finishStop(failures: [], trainerNeedsWheelSizeReset: false)
        XCTAssertFalse(lifecycle.owns(id))
    }

    // MARK: - Resetting after interrupted shifting

    func testTidyingUpIsAllowedWhenShiftingIsNotRunning() {
        var lifecycle = ShiftingLifecycle()
        let token = lifecycle.wheelSizeResetToken
        XCTAssertTrue(lifecycle.isWheelSizeResetWanted(token))

        lifecycle.refuseStart("Setup is incomplete")
        XCTAssertTrue(
            lifecycle.isWheelSizeResetWanted(token),
            "A failed ride still leaves the trainer worth tidying up"
        )
    }

    /// The bug this pins down: cancelling the tidy-up is not enough, because it
    /// spends most of its life waiting on the trainer and those waits ignore
    /// cancellation. Without the token it would carry on and overwrite the
    /// gear the new ride had just set.
    func testStartingShiftingStandsDownTheTidyUpAlreadyInFlight() {
        var lifecycle = ShiftingLifecycle()
        let token = lifecycle.wheelSizeResetToken

        lifecycle.abandonWheelSizeReset()
        lifecycle.beginConnecting()
        lifecycle.markActive()

        XCTAssertFalse(lifecycle.isWheelSizeResetWanted(token))
    }

    func testTheTidyUpStandsDownEvenIfItStartedFirst() {
        var lifecycle = ShiftingLifecycle()
        let token = lifecycle.wheelSizeResetToken
        lifecycle.beginConnecting()

        XCTAssertFalse(
            lifecycle.isWheelSizeResetWanted(token),
            "A ride is running, so its wheel size is the one that should win"
        )
    }

    func testAbandoningTheTidyUpTwiceInvalidatesBothAttempts() {
        var lifecycle = ShiftingLifecycle()
        let first = lifecycle.wheelSizeResetToken
        lifecycle.abandonWheelSizeReset()
        let second = lifecycle.wheelSizeResetToken
        lifecycle.abandonWheelSizeReset()

        XCTAssertFalse(lifecycle.isWheelSizeResetWanted(first))
        XCTAssertFalse(lifecycle.isWheelSizeResetWanted(second))
        XCTAssertTrue(
            lifecycle.isWheelSizeResetWanted(lifecycle.wheelSizeResetToken)
        )
    }

    // MARK: - Losing trainer control

    func testLosingControlWhileShiftingIsWorthRecovering() {
        let lifecycle = riding()
        XCTAssertTrue(lifecycle.canRecover)
    }

    func testLosingControlWhileAlreadyReconnectingIsStillWorthRecovering() {
        var lifecycle = riding()
        lifecycle.markReconnecting()
        XCTAssertTrue(lifecycle.canRecover)
    }

    /// The bug this pins down: a KICKR commonly drops the control grant while
    /// it is stopping. Recovering there would re-apply the gear's wheel size
    /// behind the stop's back and leave the trainer holding it after the ride.
    func testLosingControlWhileStoppingIsNotRecovered() {
        var lifecycle = riding()
        XCTAssertNotNil(lifecycle.beginStopping())
        XCTAssertFalse(lifecycle.canRecover)
    }

    func testLosingControlWhileConnectingIsNotRecovered() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.beginConnecting()
        XCTAssertFalse(lifecycle.canRecover)
    }

    func testThereIsNothingToRecoverWhenNotShifting() {
        let lifecycle = ShiftingLifecycle()
        XCTAssertFalse(lifecycle.canRecover)
    }

    func testRecoveringPutsShiftingBackToActive() {
        var lifecycle = riding()
        lifecycle.markReconnecting()
        XCTAssertTrue(lifecycle.isReconnecting)
        XCTAssertFalse(lifecycle.isShifting)

        lifecycle.markActive()
        XCTAssertTrue(lifecycle.isShifting)
        XCTAssertFalse(lifecycle.isReconnecting)
    }

    // MARK: - Stopping

    func testASecondStopIsIgnored() {
        var lifecycle = riding()
        XCTAssertNotNil(lifecycle.beginStopping())
        XCTAssertNil(
            lifecycle.beginStopping(),
            "Tapping stop twice must not run the whole stop twice"
        )
    }

    func testStoppingWhenNothingIsRunningDoesNothing() {
        var lifecycle = ShiftingLifecycle()
        XCTAssertNil(lifecycle.beginStopping())
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testACleanStopLeavesNoFailure() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(failures: [], trainerNeedsWheelSizeReset: false)

        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.failure)
        XCTAssertNil(lifecycle.shiftingID)
    }

    func testAFailedStopRecordsWhetherTheBaselineStillNeedsResetting() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed"],
            trainerNeedsWheelSizeReset: true
        )

        XCTAssertEqual(
            lifecycle.failure,
            .stopping(trainerNeedsWheelSizeReset: true)
        )
        XCTAssertTrue(lifecycle.failure?.happenedWhileStopping == true)
        XCTAssertTrue(lifecycle.failure?.trainerNeedsWheelSizeReset == true)
    }

    func testAFailedStopThatResetTheBaselineRecordsNoPendingReset() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed"],
            trainerNeedsWheelSizeReset: false
        )

        XCTAssertEqual(
            lifecycle.failure,
            .stopping(trainerNeedsWheelSizeReset: false)
        )
        XCTAssertFalse(lifecycle.failure?.trainerNeedsWheelSizeReset == true)
    }

    func testEveryReasonAStopFailedIsReported() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed", "Wheel size reset failed"],
            trainerNeedsWheelSizeReset: true
        )

        XCTAssertEqual(
            lifecycle.state,
            .failed("Trainer stop failed. Wheel size reset failed")
        )
    }

    // MARK: - Failing to start

    /// A refused start never touched the trainer, so the rider must not be told
    /// to go and check it.
    func testARefusedStartLeavesNothingToPutRight() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.refuseStart("Setup is incomplete")

        XCTAssertEqual(
            lifecycle.failure,
            .starting(trainerNeedsWheelSizeReset: false)
        )
        XCTAssertFalse(lifecycle.failure?.happenedWhileStopping == true)
        XCTAssertEqual(lifecycle.state, .failed("Setup is incomplete"))
    }

    /// A start that got as far as setting the first gear did touch the trainer,
    /// so if putting it back failed the rider has to be told.
    func testAStartThatLeftTheTrainerChangedSaysSo() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsWheelSizeReset: true
        )

        XCTAssertEqual(
            lifecycle.failure,
            .starting(trainerNeedsWheelSizeReset: true)
        )
        XCTAssertNil(lifecycle.shiftingID)
        XCTAssertTrue(lifecycle.canStart)
    }

    func testAFailedStartThatPutTheTrainerBackDoesNotAlarmTheRider() {
        var lifecycle = ShiftingLifecycle()
        lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsWheelSizeReset: false
        )

        XCTAssertFalse(lifecycle.failure?.trainerNeedsWheelSizeReset == true)
    }

    func testAFailedStartDisownsItsOwnWorkSoLateRepliesAreIgnored() {
        var lifecycle = ShiftingLifecycle()
        let id = lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsWheelSizeReset: false
        )

        XCTAssertFalse(lifecycle.owns(id))
    }
}

/// The phone should buzz once for a tap and once for a whole sweep, not once
/// per gear, which is what makes holding a button feel like one action.
final class ShiftFeedbackLedgerTests: XCTestCase {
    func testASingleShiftFeelsLikeASingleShift() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.single)
        XCTAssertEqual(ledger.confirm(from: 3, to: 4), .single)
        XCTAssertTrue(ledger.isEmpty)
    }

    func testAHeldButtonFeelsLikeASweep() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.multiple)
        XCTAssertEqual(ledger.confirm(from: 3, to: 4), .multiple)
    }

    func testSeveralGearsAtOnceFeelLikeASweepHoweverTheyWereAskedFor() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.single)
        ledger.record(.single)
        XCTAssertEqual(ledger.confirm(from: 3, to: 5), .multiple)
    }

    func testShiftingDownCountsTheSameAsShiftingUp() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.single)
        ledger.record(.single)
        XCTAssertEqual(ledger.confirm(from: 5, to: 3), .multiple)
    }

    func testOnlyTheGearsConfirmedAreSettled() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.single)
        ledger.record(.multiple)
        XCTAssertEqual(ledger.confirm(from: 3, to: 4), .single)
        XCTAssertFalse(ledger.isEmpty)
        XCTAssertEqual(ledger.confirm(from: 4, to: 5), .multiple)
        XCTAssertTrue(ledger.isEmpty)
    }

    func testAConfirmationWithNothingWaitingStillReportsSomething() {
        var ledger = ShiftFeedbackLedger()
        XCTAssertEqual(ledger.confirm(from: 3, to: 4), .single)
    }

    func testAFailedShiftClearsWhatWasWaiting() {
        var ledger = ShiftFeedbackLedger()
        ledger.record(.multiple)
        ledger.clear()
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertEqual(ledger.confirm(from: 3, to: 4), .single)
    }
}
