import XCTest

@testable import VirtualGearsCore

/// A fan moves real air in the rider's face, so these tests are mostly about
/// the app keeping quiet. The bug they exist to prevent: opening the app put a
/// Headwind straight back to full speed, with no ride anywhere in sight.
final class HeadwindControlPolicyTests: XCTestCase {
    func testConnectingWithASavedManualSpeedSendsNothing() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: false,
            wantsManualControl: true,
            desiredManualSpeed: 100,
            observedMode: .heartRate
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }
}

final class HeadwindRestorationPolicyTests: XCTestCase {
        func testRestoresEveryNonManualModeExactly() {
            for mode in [HeadwindMode.off, .heartRate, .speed, .sleep] {
                XCTAssertEqual(
                    HeadwindRestorationPolicy.commands(
                        restoring: .init(mode: mode, manualSpeed: 35),
                        from: .init(mode: .manual, manualSpeed: 70)
                    ),
                    [.setMode(mode)]
                )
            }
        }

        func testRestoringManualModeAndSpeedUsesCorrectOrder() {
            XCTAssertEqual(
                HeadwindRestorationPolicy.commands(
                    restoring: .init(mode: .manual, manualSpeed: 35),
                    from: .init(mode: .heartRate, manualSpeed: 70)
                ),
                [.setMode(.manual), .setManualSpeed(35)]
            )
        }

        func testRestoringManualAvoidsRedundantCommands() {
            XCTAssertEqual(
                HeadwindRestorationPolicy.commands(
                    restoring: .init(mode: .manual, manualSpeed: 35),
                    from: .init(mode: .manual, manualSpeed: 70)
                ),
                [.setManualSpeed(35)]
            )
            XCTAssertEqual(
                HeadwindRestorationPolicy.commands(
                    restoring: .init(mode: .manual, manualSpeed: 35),
                    from: .init(mode: .speed, manualSpeed: 35)
                ),
                [.setMode(.manual)]
            )
        }

        func testAlreadyMatchingStateNeedsNoCommands() {
            for mode in HeadwindMode.allCases {
                let state = HeadwindState(mode: mode, manualSpeed: 55)
                XCTAssertEqual(
                    HeadwindRestorationPolicy.commands(restoring: state, from: state),
                    []
                )
            }
        }

        func testNonManualStateIgnoresIrrelevantManualSpeed() {
            XCTAssertTrue(
                HeadwindState(mode: .off, manualSpeed: 10).matches(
                    .init(mode: .off, manualSpeed: 90)
                )
            )
        }
    }

final class HeadwindControlLifecycleTests: XCTestCase {
        func testCapturesOnceAndDoesNotOverwriteBaseline() {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .speed, manualSpeed: 25)

            XCTAssertTrue(
                lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)
            )
            XCTAssertFalse(
                lifecycle.begin(
                    observedState: .init(mode: .manual, manualSpeed: 80),
                    hasUnsettledCommand: false
                )
            )
            XCTAssertEqual(lifecycle.beginRestoration(), baseline)
        }

        func testStartBeforeReadyWaitsForAuthoritativeState() {
            var lifecycle = HeadwindControlLifecycle()
            XCTAssertFalse(
                lifecycle.begin(observedState: nil, hasUnsettledCommand: false)
            )
            XCTAssertTrue(lifecycle.isAwaitingBaseline)

            let baseline = HeadwindState(mode: .sleep, manualSpeed: 40)
            XCTAssertTrue(lifecycle.observeAuthoritative(baseline))
            XCTAssertEqual(lifecycle.beginRestoration(), baseline)
        }

        func testStoppingBeforeBaselineWasCapturedIsANoOp() {
            var lifecycle = HeadwindControlLifecycle()
            lifecycle.begin(observedState: nil, hasUnsettledCommand: false)
            XCTAssertNil(lifecycle.beginRestoration())
            XCTAssertEqual(lifecycle.phase, .idle)
            XCTAssertNil(lifecycle.beginRestoration())
        }

        func testRepeatedStopKeepsRestorationTargetUntilObserved() {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .manual, manualSpeed: 30)
            lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)

            XCTAssertEqual(lifecycle.beginRestoration(), baseline)
            XCTAssertEqual(lifecycle.beginRestoration(), baseline)
            XCTAssertFalse(
                lifecycle.finishRestoration(
                    ifObserved: .init(mode: .manual, manualSpeed: 70)
                )
            )
            XCTAssertTrue(lifecycle.finishRestoration(ifObserved: baseline))
            XCTAssertEqual(lifecycle.phase, .idle)
        }

        func testRestartDuringRestorationDoesNotReuseStaleBaseline() {
            var lifecycle = HeadwindControlLifecycle()
            lifecycle.begin(
                observedState: .init(mode: .heartRate, manualSpeed: 20),
                hasUnsettledCommand: false
            )
            lifecycle.beginRestoration()

            XCTAssertFalse(
                lifecycle.begin(
                    observedState: .init(mode: .heartRate, manualSpeed: 20),
                    hasUnsettledCommand: true
                )
            )
            XCTAssertTrue(lifecycle.isAwaitingBaseline)

            let newBaseline = HeadwindState(mode: .manual, manualSpeed: 65)
            XCTAssertFalse(
                lifecycle.observeAuthoritative(
                    newBaseline,
                    hasUnsettledCommand: true
                )
            )
            XCTAssertTrue(lifecycle.isAwaitingBaseline)
            XCTAssertTrue(lifecycle.observeAuthoritative(newBaseline))
            XCTAssertEqual(lifecycle.beginRestoration(), newBaseline)
        }

        func testDisconnectDoesNotDiscardRestorationTarget() {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .off, manualSpeed: 0)
            lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)
            lifecycle.beginRestoration()

            XCTAssertEqual(lifecycle.restorationTarget, baseline)
            XCTAssertFalse(
                lifecycle.finishRestoration(
                    ifObserved: .init(mode: .manual, manualSpeed: 50)
                )
            )
            XCTAssertEqual(lifecycle.restorationTarget, baseline)
        }

        func testReconnectReplansRestoreFromItsAuthoritativeState() throws {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .sleep, manualSpeed: 15)
            lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)
            lifecycle.beginRestoration()

            let reconnectedState = HeadwindState(mode: .manual, manualSpeed: 80)
            XCTAssertEqual(
                HeadwindRestorationPolicy.commands(
                    restoring: try XCTUnwrap(lifecycle.restorationTarget),
                    from: reconnectedState
                ),
                [.setMode(.sleep)]
            )
            XCTAssertFalse(lifecycle.finishRestoration(ifObserved: reconnectedState))
            XCTAssertTrue(
                lifecycle.finishRestoration(
                    ifObserved: reconnectedState.applying(.setMode(.sleep))
                )
            )
        }

        func testFailedCommandCanBeRetriedWithoutDiscardingBaseline() throws {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .heartRate, manualSpeed: 20)
            lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)
            lifecycle.beginRestoration()

            let current = HeadwindState(mode: .manual, manualSpeed: 90)
            let firstAttempt = HeadwindRestorationPolicy.commands(
                restoring: try XCTUnwrap(lifecycle.restorationTarget),
                from: current
            )
            XCTAssertEqual(firstAttempt, [.setMode(.heartRate)])
            XCTAssertEqual(lifecycle.restorationTarget, baseline)
            XCTAssertEqual(
                HeadwindRestorationPolicy.commands(
                    restoring: try XCTUnwrap(lifecycle.restorationTarget),
                    from: current
                ),
                firstAttempt
            )
        }

        func testManualBaselineLivesUntilModeAndSpeedAreBothAcknowledged() throws {
            var lifecycle = HeadwindControlLifecycle()
            let baseline = HeadwindState(mode: .manual, manualSpeed: 35)
            lifecycle.begin(observedState: baseline, hasUnsettledCommand: false)
            lifecycle.beginRestoration()

            var observed = HeadwindState(mode: .off, manualSpeed: 80)
            let commands = HeadwindRestorationPolicy.commands(
                restoring: try XCTUnwrap(lifecycle.restorationTarget),
                from: observed
            )
            XCTAssertEqual(commands, [.setMode(.manual), .setManualSpeed(35)])

            observed = observed.applying(commands[0])
            XCTAssertFalse(lifecycle.finishRestoration(ifObserved: observed))
            XCTAssertEqual(lifecycle.restorationTarget, baseline)

            observed = observed.applying(commands[1])
            XCTAssertTrue(lifecycle.finishRestoration(ifObserved: observed))
            XCTAssertNil(lifecycle.restorationTarget)
        }

        func testStopWithoutVirtualGearsTakingControlDoesNotRestore() {
            var lifecycle = HeadwindControlLifecycle()
            XCTAssertNil(lifecycle.beginRestoration())
            XCTAssertEqual(lifecycle.phase, .idle)
        }
    }

extension HeadwindControlPolicyTests {
    func testStartingARideRestoresTheSavedManualSpeed() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 60,
            observedMode: .heartRate
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setMode(.manual), .setManualSpeed(60)]
        )
    }

    func testShiftingLeavesSensorControlAlone() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: true,
            wantsManualControl: false,
            lastSensorMode: .heartRate,
            observedMode: .manual
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }

    func testAFanAlreadyAtTheWantedSpeedIsLeftAlone() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 60,
            observedMode: .manual,
            observedManualSpeed: 60
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }

    func testAFanInManualAtTheWrongSpeedIsOnlyRespeeded() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 60,
            observedMode: .manual,
            observedManualSpeed: 25
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setManualSpeed(60)]
        )
    }

    /// Refusing to start a fan must never become refusing to stop one.
    func testHandingTheFanBackHappensEvenOutsideARide() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: false,
            isHandingBack: true,
            wantsManualControl: true,
            lastSensorMode: .speed,
            observedMode: .manual,
            observedManualSpeed: 100
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setMode(.speed)]
        )
    }

    /// The sensor mode is learned from the fan, not chosen by the app, so
    /// handing it back returns it to the one it was actually using.
    func testHandingBackReturnsTheFanToItsOwnSensorMode() {
        let situation = HeadwindSituation(
            isHandingBack: true,
            lastSensorMode: .heartRate,
            observedMode: .manual
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setMode(.heartRate)]
        )
    }

    func testAFanThatHasNotSaidAnythingYetIsStillSetUpForARide() {
        let situation = HeadwindSituation(
            weAreDrivingTheFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 40,
            observedMode: nil
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setMode(.manual), .setManualSpeed(40)]
        )
    }
}
