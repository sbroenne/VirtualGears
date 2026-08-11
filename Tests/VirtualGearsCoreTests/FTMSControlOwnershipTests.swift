import XCTest

@testable import VirtualGearsCore

/// Who gets to steer the trainer. The bug these exist to prevent: a riding app
/// whose link dropped kept its claim, and nothing on the PC could clear it, so
/// the app trying to reconnect was locked out of its own trainer.
final class FTMSControlOwnershipTests: XCTestCase {
    private let zwift = UUID()
    private let other = UUID()

    func testAnUnclaimedTrainerGrantsControl() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(request: .requestControl, requesterID: zwift)
        )
        XCTAssertEqual(decision, .handOn)
    }

    func testALiveOwnerKeepsTheTrainer() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: other,
                ownerID: zwift,
                ownerIsPresent: true
            )
        )
        XCTAssertEqual(decision, .refuse(.controlNotPermitted))
    }

    /// The lock-out bug, in one test.
    func testAVanishedOwnerDoesNotLockOutTheNextApp() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: other,
                ownerID: zwift,
                ownerIsPresent: false
            )
        )
        XCTAssertEqual(decision, .handOn)
    }

    func testTheOwnerMayAskForControlAgain() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: zwift,
                ownerID: zwift,
                ownerIsPresent: true
            )
        )
        XCTAssertEqual(decision, .handOn)
    }

    func testSteeringWithoutAskingIsRefused() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .setTargetPower(watts: 150),
                requesterID: other,
                ownerID: zwift,
                ownerIsPresent: true
            )
        )
        XCTAssertEqual(decision, .refuse(.controlNotPermitted))
    }

    func testTheOwnerMaySteer() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .setTargetPower(watts: 150),
                requesterID: zwift,
                ownerID: zwift,
                ownerIsPresent: true
            )
        )
        XCTAssertEqual(decision, .handOn)
    }

    /// A command on a subscription that has already ended belongs to a
    /// conversation that is over, and is a different failure from never having
    /// subscribed at all.
    func testAStaleSubscriptionFailsRatherThanBeingRefused() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: zwift,
                requesterSubscriptionIsCurrent: false
            )
        )
        XCTAssertEqual(decision, .refuse(.operationFailed))
    }

    func testAnAppThatNeverSubscribedIsNotPermitted() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: zwift,
                requesterIsSubscribed: false
            )
        )
        XCTAssertEqual(decision, .refuse(.controlNotPermitted))
    }

    func testNothingIsAcceptedWhileTheProxyIsNotReady() {
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: .requestControl,
                requesterID: zwift,
                isAcceptingCommands: false
            )
        )
        XCTAssertEqual(decision, .refuse(.operationFailed))
    }

    // MARK: - Where the claim ends up

    func testGrantedControlMovesTheClaim() {
        let owner = FTMSControlOwnership.owner(
            after: .requestControl,
            result: .success,
            currentOwner: nil,
            requesterID: zwift
        )
        XCTAssertEqual(owner, zwift)
    }

    func testResetReleasesTheTrainer() {
        let owner = FTMSControlOwnership.owner(
            after: .reset,
            result: .success,
            currentOwner: zwift,
            requesterID: zwift
        )
        XCTAssertNil(owner)
    }

    func testAFailedRequestLeavesTheClaimWhereItWas() {
        let owner = FTMSControlOwnership.owner(
            after: .requestControl,
            result: .operationFailed,
            currentOwner: zwift,
            requesterID: other
        )
        XCTAssertEqual(owner, zwift)
    }

    func testSteeringDoesNotChangeWhoHoldsTheTrainer() {
        let owner = FTMSControlOwnership.owner(
            after: .setTargetPower(watts: 200),
            result: .success,
            currentOwner: zwift,
            requesterID: zwift
        )
        XCTAssertEqual(owner, zwift)
    }
}
