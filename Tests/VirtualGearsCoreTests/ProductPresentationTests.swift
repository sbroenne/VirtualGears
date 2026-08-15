import XCTest
@testable import VirtualGearsCore

final class ProductPresentationTests: XCTestCase {
    func testEveryConnectionStateHasPlainLanguageLabels() {
        let states: [(ProductConnectionState, String, String)] = [
            (.unavailable("Bluetooth is off"), "Bluetooth is off", "Bluetooth is off"),
            (.disconnected, "Not connected", "Not connected"),
            (.scanning, "Looking for it…", "Looking for it…"),
            (.reconnecting(attempt: 3), "Reconnecting…", "Reconnecting…"),
            (.connecting(name: "KICKR"), "Connecting to KICKR…", "Connecting…"),
            (.discovering, "Getting ready…", "Getting ready…"),
            (.preparing, "Almost ready…", "Almost ready…"),
            (.ready, "Ready", "Ready"),
            (.disconnecting, "Disconnecting…", "Disconnecting…"),
            (.failed("Control denied"), "Control denied", "Control denied"),
        ]

        for (state, label, shortLabel) in states {
            XCTAssertEqual(state.label, label)
            XCTAssertEqual(state.shortLabel, shortLabel)
        }
    }

    func testEveryEquipmentDisplayStateHasALabel() {
        XCTAssertEqual(EquipmentDisplayState.connected.label, "Connected")
        XCTAssertEqual(EquipmentDisplayState.connecting.label, "Connecting")
        XCTAssertEqual(EquipmentDisplayState.disconnected.label, "Not connected")
        XCTAssertEqual(EquipmentDisplayState.notAdded.label, "Not added")
    }

    func testDiscoveryCanReturnToSearchingAndReset() {
        var discovery = DeviceDiscoveryState()
        discovery.start()
        discovery.observe(candidateCount: 1)
        XCTAssertEqual(discovery.phase, .showingResults)

        discovery.observe(candidateCount: 0)
        XCTAssertEqual(discovery.phase, .searching)

        discovery.reset()
        XCTAssertEqual(discovery.phase, .idle)
    }

    func testTrainerSafetyRoundsToTheCommandResolution() {
        XCTAssertEqual(TrainerSafety.circumferenceAsSent(2_070.04), 2_070.0)
        XCTAssertEqual(TrainerSafety.circumferenceAsSent(2_070.06), 2_070.1)
        XCTAssertEqual(
            TrainerSafety.widestSupportedSpan,
            TrainerSafety.supportedScaleRange.upperBound
                / TrainerSafety.supportedScaleRange.lowerBound
        )
    }

    func testKickrCapabilitiesAndPeripheralSuccessKeepTheirValues() throws {
        let feature = FitnessMachineFeature(
            machineFeatures: [.cadence],
            targetSettingFeatures: []
        )
        let resistance = try SupportedResistanceLevelRange(
            minimumTenths: -10,
            maximumTenths: 100,
            incrementTenths: 1
        )
        let capabilities = KickrCapabilities(
            feature: feature,
            resistanceRange: resistance,
            supportsWahooControl: true
        )

        XCTAssertEqual(capabilities.feature, feature)
        XCTAssertEqual(capabilities.resistanceRange, resistance)
        XCTAssertTrue(capabilities.supportsWahooControl)

        let result = FTMSPeripheralCommandResult.success(status: .startedOrResumed)
        XCTAssertEqual(result.result, .success)
        XCTAssertEqual(result.status, .startedOrResumed)
    }
}
