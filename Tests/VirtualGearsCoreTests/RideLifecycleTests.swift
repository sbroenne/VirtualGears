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
final class RideLifecycleTests: XCTestCase {
    private func riding() -> RideLifecycle {
        var lifecycle = RideLifecycle()
        lifecycle.beginConnecting()
        lifecycle.markActive()
        return lifecycle
    }

    // MARK: - Where things stand

    func testAFreshLifecycleIsIdleAndShowsNoRideScreen() {
        let lifecycle = RideLifecycle()
        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.failure)
        XCTAssertNil(lifecycle.sessionID)
        XCTAssertFalse(lifecycle.isRidePresented)
        XCTAssertTrue(lifecycle.isBetweenRides)
        XCTAssertTrue(lifecycle.canStart)
    }

    func testTheRideScreenIsShownFromConnectingUntilStopped() {
        var lifecycle = RideLifecycle()
        lifecycle.beginConnecting()
        XCTAssertTrue(lifecycle.isRidePresented)
        lifecycle.markActive()
        XCTAssertTrue(lifecycle.isRidePresented)
        lifecycle.markReconnecting()
        XCTAssertTrue(lifecycle.isRidePresented)
        XCTAssertNotNil(lifecycle.beginStopping())
        XCTAssertTrue(lifecycle.isRidePresented)
        lifecycle.finishStop(failures: [], trainerNeedsBaselineReset: false)
        XCTAssertFalse(lifecycle.isRidePresented)
    }

    func testARideCanBeStartedAgainAfterAFailure() {
        var lifecycle = RideLifecycle()
        lifecycle.refuseStart("Setup is incomplete")
        XCTAssertTrue(lifecycle.isFailed)
        XCTAssertTrue(lifecycle.canStart)
        XCTAssertFalse(lifecycle.isRidePresented)
    }

    func testStartingClearsAnEarlierFailure() {
        var lifecycle = RideLifecycle()
        lifecycle.refuseStart("Setup is incomplete")
        lifecycle.beginConnecting()
        XCTAssertNil(lifecycle.failure)
        XCTAssertEqual(lifecycle.state, .connecting)
    }

    // MARK: - Work belonging to an older ride

    func testWorkFromAnEarlierRideIsDisowned() {
        var lifecycle = RideLifecycle()
        let first = lifecycle.beginConnecting()
        lifecycle.markActive()
        XCTAssertTrue(lifecycle.owns(first))

        lifecycle.finishStop(failures: [], trainerNeedsBaselineReset: false)
        let second = lifecycle.beginConnecting()

        XCTAssertFalse(lifecycle.owns(first))
        XCTAssertTrue(lifecycle.owns(second))
    }

    func testNothingIsOwnedOnceARideHasStopped() {
        var lifecycle = RideLifecycle()
        let id = lifecycle.beginConnecting()
        lifecycle.finishStop(failures: [], trainerNeedsBaselineReset: false)
        XCTAssertFalse(lifecycle.owns(id))
    }

    // MARK: - Resetting after an interrupted ride

    func testTidyingUpIsAllowedWhenNoRideIsRunning() {
        var lifecycle = RideLifecycle()
        let token = lifecycle.baselineResetToken
        XCTAssertTrue(lifecycle.isBaselineResetWanted(token))

        lifecycle.refuseStart("Setup is incomplete")
        XCTAssertTrue(
            lifecycle.isBaselineResetWanted(token),
            "A failed ride still leaves the trainer worth tidying up"
        )
    }

    /// The bug this pins down: cancelling the tidy-up is not enough, because it
    /// spends most of its life waiting on the trainer and those waits ignore
    /// cancellation. Without the token it would carry on and overwrite the
    /// gear the new ride had just set.
    func testStartingARideStandsDownTheTidyUpAlreadyInFlight() {
        var lifecycle = RideLifecycle()
        let token = lifecycle.baselineResetToken

        lifecycle.abandonBaselineReset()
        lifecycle.beginConnecting()
        lifecycle.markActive()

        XCTAssertFalse(lifecycle.isBaselineResetWanted(token))
    }

    func testTheTidyUpStandsDownEvenIfItStartedBeforeTheRide() {
        var lifecycle = RideLifecycle()
        let token = lifecycle.baselineResetToken
        lifecycle.beginConnecting()

        XCTAssertFalse(
            lifecycle.isBaselineResetWanted(token),
            "A ride is running, so its wheel size is the one that should win"
        )
    }

    func testAbandoningTheTidyUpTwiceInvalidatesBothAttempts() {
        var lifecycle = RideLifecycle()
        let first = lifecycle.baselineResetToken
        lifecycle.abandonBaselineReset()
        let second = lifecycle.baselineResetToken
        lifecycle.abandonBaselineReset()

        XCTAssertFalse(lifecycle.isBaselineResetWanted(first))
        XCTAssertFalse(lifecycle.isBaselineResetWanted(second))
        XCTAssertTrue(
            lifecycle.isBaselineResetWanted(lifecycle.baselineResetToken)
        )
    }

    // MARK: - Losing trainer control

    func testLosingControlDuringARideIsWorthRecovering() {
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
        var lifecycle = RideLifecycle()
        lifecycle.beginConnecting()
        XCTAssertFalse(lifecycle.canRecover)
    }

    func testThereIsNothingToRecoverWithoutARide() {
        let lifecycle = RideLifecycle()
        XCTAssertFalse(lifecycle.canRecover)
    }

    func testRecoveringPutsTheRideBackToActive() {
        var lifecycle = riding()
        lifecycle.markReconnecting()
        XCTAssertTrue(lifecycle.isReconnecting)
        XCTAssertFalse(lifecycle.isRiding)

        lifecycle.markActive()
        XCTAssertTrue(lifecycle.isRiding)
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

    func testStoppingWithoutARideDoesNothing() {
        var lifecycle = RideLifecycle()
        XCTAssertNil(lifecycle.beginStopping())
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testACleanStopLeavesNoFailure() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(failures: [], trainerNeedsBaselineReset: false)

        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.failure)
        XCTAssertNil(lifecycle.sessionID)
    }

    func testAFailedStopRecordsWhetherTheBaselineStillNeedsResetting() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed"],
            trainerNeedsBaselineReset: true
        )

        XCTAssertEqual(
            lifecycle.failure,
            .stopping(trainerNeedsBaselineReset: true)
        )
        XCTAssertTrue(lifecycle.failure?.happenedWhileStopping == true)
        XCTAssertTrue(lifecycle.failure?.trainerNeedsBaselineReset == true)
    }

    func testAFailedStopThatResetTheBaselineRecordsNoPendingReset() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed"],
            trainerNeedsBaselineReset: false
        )

        XCTAssertEqual(
            lifecycle.failure,
            .stopping(trainerNeedsBaselineReset: false)
        )
        XCTAssertFalse(lifecycle.failure?.trainerNeedsBaselineReset == true)
    }

    func testEveryReasonAStopFailedIsReported() {
        var lifecycle = riding()
        _ = lifecycle.beginStopping()
        lifecycle.finishStop(
            failures: ["Trainer stop failed", "Baseline reset failed"],
            trainerNeedsBaselineReset: true
        )

        XCTAssertEqual(
            lifecycle.state,
            .failed("Trainer stop failed. Baseline reset failed")
        )
    }

    // MARK: - Failing to start

    /// A refused start never touched the trainer, so the rider must not be told
    /// to go and check it.
    func testARefusedStartLeavesNothingToPutRight() {
        var lifecycle = RideLifecycle()
        lifecycle.refuseStart("Setup is incomplete")

        XCTAssertEqual(
            lifecycle.failure,
            .starting(trainerNeedsBaselineReset: false)
        )
        XCTAssertFalse(lifecycle.failure?.happenedWhileStopping == true)
        XCTAssertEqual(lifecycle.state, .failed("Setup is incomplete"))
    }

    /// A start that got as far as setting the first gear did touch the trainer,
    /// so if putting it back failed the rider has to be told.
    func testAStartThatLeftTheTrainerChangedSaysSo() {
        var lifecycle = RideLifecycle()
        lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsBaselineReset: true
        )

        XCTAssertEqual(
            lifecycle.failure,
            .starting(trainerNeedsBaselineReset: true)
        )
        XCTAssertNil(lifecycle.sessionID)
        XCTAssertTrue(lifecycle.canStart)
    }

    func testAFailedStartThatPutTheTrainerBackDoesNotAlarmTheRider() {
        var lifecycle = RideLifecycle()
        lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsBaselineReset: false
        )

        XCTAssertFalse(lifecycle.failure?.trainerNeedsBaselineReset == true)
    }

    func testAFailedStartDisownsItsOwnWorkSoLateRepliesAreIgnored() {
        var lifecycle = RideLifecycle()
        let id = lifecycle.beginConnecting()
        lifecycle.failStart(
            "KICKR denied FTMS control",
            trainerNeedsBaselineReset: false
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
