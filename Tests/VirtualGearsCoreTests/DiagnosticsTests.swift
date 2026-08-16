import Foundation
import XCTest
@testable import VirtualGearsCore

final class DiagnosticsTests: XCTestCase {
    func testAppIdentityReadsBundleValuesAndFormatsVersion() {
        let identity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Virtual Gears",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "11",
        ])

        XCTAssertEqual(identity.displayName, "Virtual Gears")
        XCTAssertEqual(identity.versionAndBuild, "1.0 (11)")
    }

    func testAppIdentityUsesSafeFallbacksForMissingMetadata() {
        let identity = AppIdentity(infoDictionary: [
            "CFBundleName": "VirtualGears",
        ])

        XCTAssertEqual(identity.displayName, "VirtualGears")
        XCTAssertEqual(identity.versionAndBuild, "Unknown (Unknown)")
    }

    func testLiveStateMapsToPlainEnglishWithoutIdentifiers() {
        let appID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let state = DiagnosticsState(
            trainerConnection: .ready,
            isProxyAdvertising: true,
            subscriberCount: 1,
            isControlledByRidingApp: true,
            latestPeripheralEvent: .centralSubscribed(
                appID,
                characteristic: FTMSUUID.indoorBikeData
            )
        )

        XCTAssertEqual(state.trainerSummary, "Connected and ready")
        XCTAssertEqual(state.advertisingSummary, "Advertising")
        XCTAssertEqual(state.subscribersSummary, "1 riding app subscribed")
        XCTAssertEqual(state.controlSummary, "A riding app has control")
        XCTAssertEqual(
            state.latestEventSummary,
            "A riding app subscribed to FTMS Indoor Bike Data"
        )
        XCTAssertFalse(state.latestEventSummary.contains(appID.uuidString))
    }

    func testEveryTrainerStateAndSubscriberCountMapsToPlainEnglish() {
        let states: [(ProductConnectionState, String)] = [
            (.unavailable("Bluetooth is off"), "Bluetooth is off"),
            (.disconnected, "Not connected"),
            (.scanning, "Looking for trainer"),
            (.reconnecting(attempt: 3), "Reconnecting"),
            (.connecting(name: "KICKR 2A93"), "Connecting"),
            (.discovering, "Connected, getting ready"),
            (.preparing, "Connected, getting ready"),
            (.ready, "Connected and ready"),
            (.disconnecting, "Disconnecting"),
            (.failed("Control denied"), "Control denied"),
        ]

        for (connection, expected) in states {
            let state = DiagnosticsState(
                trainerConnection: connection,
                isProxyAdvertising: false,
                subscriberCount: 0,
                isControlledByRidingApp: false,
                latestPeripheralEvent: nil
            )
            XCTAssertEqual(state.trainerSummary, expected)
            XCTAssertEqual(state.advertisingSummary, "Not advertising")
            XCTAssertEqual(state.subscribersSummary, "No riding apps subscribed")
            XCTAssertEqual(state.controlSummary, "No riding app has control")
            XCTAssertEqual(state.latestEventSummary, "No peripheral event yet")
        }

        let multipleSubscribers = DiagnosticsState(
            trainerConnection: .ready,
            isProxyAdvertising: true,
            subscriberCount: 3,
            isControlledByRidingApp: true,
            latestPeripheralEvent: nil
        )
        XCTAssertEqual(
            multipleSubscribers.subscribersSummary,
            "3 riding apps subscribed"
        )
    }

    func testPeripheralFailureRedactsBluetoothIdentifier() {
        let identifier = "10000000-0000-0000-0000-000000000004"
        let state = DiagnosticsState(
            trainerConnection: .failed("Peripheral \(identifier) failed"),
            isProxyAdvertising: false,
            subscriberCount: 0,
            isControlledByRidingApp: false,
            latestPeripheralEvent: .failed("Peripheral \(identifier) failed")
        )

        XCTAssertEqual(
            state.latestEventSummary,
            "Trainer proxy error: Peripheral [identifier removed] failed"
        )
        XCTAssertFalse(state.latestEventSummary.contains(identifier))
    }

    func testClipboardPolicyExpiresAfterTenMinutes() {
        let copiedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(DiagnosticsReport.clipboardLifetime, 600)
        XCTAssertEqual(
            DiagnosticsReport.clipboardExpiration(after: copiedAt),
            Date(timeIntervalSince1970: 1_600)
        )
    }

    func testReportContainsRequiredStateAndNoBluetoothIdentifiers() {
        let appID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let report = DiagnosticsReport.make(
            timestamp: Date(timeIntervalSince1970: 0),
            app: AppIdentity(
                displayName: "Virtual Gears",
                marketingVersion: "1.0",
                buildNumber: "11"
            ),
            operatingSystem: "iOS 26.6",
            device: "iPhone",
            state: DiagnosticsState(
                trainerConnection: .reconnecting(attempt: 2),
                isProxyAdvertising: false,
                subscriberCount: 2,
                isControlledByRidingApp: false,
                latestPeripheralEvent: .controlRequest(
                    appID,
                    .setWheelCircumference(tenthsOfMillimeter: 22_000)
                )
            )
        )

        XCTAssertTrue(report.contains("App: 1.0 (11)"))
        XCTAssertTrue(report.contains("OS: iOS 26.6"))
        XCTAssertTrue(report.contains("Device: iPhone"))
        XCTAssertTrue(report.contains("KICKR: Reconnecting"))
        XCTAssertTrue(report.contains("Subscribers: 2 riding apps subscribed"))
        XCTAssertTrue(report.contains("wheel circumference 2200.0 mm"))
        XCTAssertTrue(report.contains("FTMS 0x1826 + CPS 0x1818"))
        XCTAssertTrue(report.contains("Generated on-device"))
        XCTAssertFalse(report.contains(appID.uuidString))
    }
}
