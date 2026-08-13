import XCTest
@testable import VirtualGearsCore

/// These cover the decisions that used to live three times over inside the
/// trainer, fan and shifter services, where nothing could reach them without a
/// radio and a real device.
final class ConnectionPolicyTests: XCTestCase {
    // MARK: - Reconnect timing

    func testDelaysBackOffAndThenHold() {
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 0), 1)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 1), 2)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 2), 4)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 3), 8)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 4), 15)
    }

    /// A rider mid-ride is not helped by the app giving up, so the longest wait
    /// repeats rather than the table running off its end.
    func testWaitsStayAtTheLongestDelayForever() {
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 5), 15)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 50), 15)
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: 5_000), 15)
    }

    func testNegativeAttemptCountIsTreatedAsTheFirst() {
        XCTAssertEqual(ReconnectPolicy.delaySeconds(afterAttempts: -1), 1)
    }

    func testSchedulesOnlyWhenStillWantedAndTheRadioIsOn() {
        XCTAssertTrue(
            ReconnectPolicy.shouldSchedule(wantsConnection: true, radioIsOn: true)
        )
        XCTAssertFalse(
            ReconnectPolicy.shouldSchedule(wantsConnection: false, radioIsOn: true)
        )
        XCTAssertFalse(
            ReconnectPolicy.shouldSchedule(wantsConnection: true, radioIsOn: false)
        )
    }

    func testAttemptIsAbandonedIfTheRiderDisconnectedDuringTheWait() {
        XCTAssertFalse(
            ReconnectPolicy.shouldProceed(wantsConnection: false, link: .disconnected)
        )
    }

    /// The link can come back on its own while the wait is running. Connecting
    /// again on top of that is how one attempt tears down another.
    func testAttemptIsAbandonedIfTheLinkCameBackDuringTheWait() {
        XCTAssertFalse(
            ReconnectPolicy.shouldProceed(wantsConnection: true, link: .connected)
        )
        XCTAssertFalse(
            ReconnectPolicy.shouldProceed(wantsConnection: true, link: .connecting)
        )
    }

    func testAttemptGoesAheadWhenStillWantedAndStillDown() {
        XCTAssertTrue(
            ReconnectPolicy.shouldProceed(wantsConnection: true, link: .disconnected)
        )
        XCTAssertTrue(
            ReconnectPolicy.shouldProceed(wantsConnection: true, link: .absent)
        )
    }

    // MARK: - Reconnecting to a saved device

    func testConnectsToASavedDeviceThatIsNotConnected() {
        XCTAssertEqual(
            SavedConnectionPolicy.decide(
                hasSavedDevice: true,
                isSuspendedForDemo: false,
                isScanning: false,
                link: .absent
            ),
            .connect
        )
    }

    func testDoesNothingWithoutASavedDevice() {
        XCTAssertEqual(
            SavedConnectionPolicy.decide(
                hasSavedDevice: false,
                isSuspendedForDemo: false,
                isScanning: false,
                link: .absent
            ),
            .doNothing
        )
    }

    /// Demo Mode must never reach for the rider's real equipment.
    func testDoesNothingDuringDemoMode() {
        XCTAssertEqual(
            SavedConnectionPolicy.decide(
                hasSavedDevice: true,
                isSuspendedForDemo: true,
                isScanning: false,
                link: .absent
            ),
            .doNothing
        )
    }

    /// Scanning is the rider picking a device. Reconnecting underneath that
    /// takes the choice off the screen.
    func testDoesNothingWhileTheRiderIsChoosing() {
        XCTAssertEqual(
            SavedConnectionPolicy.decide(
                hasSavedDevice: true,
                isSuspendedForDemo: false,
                isScanning: true,
                link: .absent
            ),
            .doNothing
        )
    }

    func testLeavesAConnectionInFlightAlone() {
        for link in [LinkState.connected, .connecting, .disconnecting] {
            XCTAssertEqual(
                SavedConnectionPolicy.decide(
                    hasSavedDevice: true,
                    isSuspendedForDemo: false,
                    isScanning: false,
                    link: link
                ),
                .leaveAlone,
                "a link that is \(link) should be left to finish"
            )
        }
    }

    // MARK: - Noticing a connection that never finishes

    func testWatchesWhileAConnectionIsInProgress() {
        XCTAssertEqual(
            StallWatchPolicy.decide(state: .connecting(name: "KICKR"), isAlreadyWatching: false),
            .beginWatching
        )
        XCTAssertEqual(
            StallWatchPolicy.decide(state: .discovering, isAlreadyWatching: false),
            .beginWatching
        )
        XCTAssertEqual(
            StallWatchPolicy.decide(state: .preparing, isAlreadyWatching: false),
            .beginWatching
        )
    }

    /// One clock runs across connecting, discovering and preparing. Restarting
    /// it at each step would let a connection that never finishes keep pushing
    /// its own deadline back.
    func testProgressBetweenStepsDoesNotRestartTheClock() {
        XCTAssertEqual(
            StallWatchPolicy.decide(state: .discovering, isAlreadyWatching: true),
            .keepWatching
        )
    }

    func testStopsWatchingOnceThereIsNothingInProgress() {
        for state in [
            ProductConnectionState.ready,
            .disconnected,
            .scanning,
            .failed("nope"),
            .unavailable("off"),
            .disconnecting
        ] {
            XCTAssertEqual(
                StallWatchPolicy.decide(state: state, isAlreadyWatching: true),
                .stopWatching,
                "\(state) is not a connection in progress"
            )
        }
    }

    // MARK: - The saved device

    func testAnIdentityMakesTheRoundTrip() {
        let id = UUID()
        let saved = SavedDeviceIdentity(id: id, name: "Wahoo KICKR 2A93")
        let read = SavedDeviceIdentity.from(stored: saved.stored)
        XCTAssertEqual(read, saved)
    }

    func testAnIdentityWithNoNameMakesTheRoundTrip() {
        let saved = SavedDeviceIdentity(id: UUID(), name: nil)
        XCTAssertEqual(SavedDeviceIdentity.from(stored: saved.stored), saved)
    }

    func testNothingSavedReadsBackAsNothing() {
        XCTAssertNil(SavedDeviceIdentity.from(stored: nil))
        XCTAssertNil(SavedDeviceIdentity.from(stored: [:]))
    }

    /// Whatever is already on a rider's phone has to be survivable, including
    /// something an older version wrote or something that is simply wrong.
    func testRubbishOnDiskIsTreatedAsNoSavedDevice() {
        XCTAssertNil(SavedDeviceIdentity.from(stored: ["id": "not-a-uuid"]))
        XCTAssertNil(SavedDeviceIdentity.from(stored: ["id": 42]))
        XCTAssertNil(SavedDeviceIdentity.from(stored: ["name": "KICKR"]))
    }

    func testAnUnreadableNameIsDroppedRatherThanFailingTheWholeIdentity() {
        let id = UUID()
        let read = SavedDeviceIdentity.from(
            stored: ["id": id.uuidString, "name": 7]
        )
        XCTAssertEqual(read, SavedDeviceIdentity(id: id, name: nil))
    }
}
