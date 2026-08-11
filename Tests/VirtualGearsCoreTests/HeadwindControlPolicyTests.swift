import XCTest

@testable import VirtualGearsCore

/// A fan moves real air in the rider's face, so these tests are mostly about
/// the app keeping quiet. The bug they exist to prevent: opening the app put a
/// Headwind straight back to full speed, with no ride anywhere in sight.
final class HeadwindControlPolicyTests: XCTestCase {
    func testConnectingWithASavedManualSpeedSendsNothing() {
        let situation = HeadwindSituation(
            rideIsDrivingFan: false,
            wantsManualControl: true,
            desiredManualSpeed: 100,
            observedMode: .heartRate
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }

    func testStartingARideRestoresTheSavedManualSpeed() {
        let situation = HeadwindSituation(
            rideIsDrivingFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 60,
            observedMode: .heartRate
        )
        XCTAssertEqual(
            HeadwindControlPolicy.commands(for: situation),
            [.setMode(.manual), .setManualSpeed(60)]
        )
    }

    func testARideLeavesSensorControlAlone() {
        let situation = HeadwindSituation(
            rideIsDrivingFan: true,
            wantsManualControl: false,
            lastSensorMode: .heartRate,
            observedMode: .manual
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }

    func testAFanAlreadyAtTheWantedSpeedIsLeftAlone() {
        let situation = HeadwindSituation(
            rideIsDrivingFan: true,
            wantsManualControl: true,
            desiredManualSpeed: 60,
            observedMode: .manual,
            observedManualSpeed: 60
        )
        XCTAssertEqual(HeadwindControlPolicy.commands(for: situation), [])
    }

    func testAFanInManualAtTheWrongSpeedIsOnlyRespeeded() {
        let situation = HeadwindSituation(
            rideIsDrivingFan: true,
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
            rideIsDrivingFan: false,
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
            rideIsDrivingFan: true,
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
