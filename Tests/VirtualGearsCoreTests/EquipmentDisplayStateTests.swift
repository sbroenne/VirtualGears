import XCTest
@testable import VirtualGearsCore

final class EquipmentDisplayStateTests: XCTestCase {
    func testRequiredEquipmentWithoutASelectionNeedsAttention() {
        XCTAssertEqual(
            EquipmentDisplayState(
                isConfigured: false,
                connectionState: .disconnected,
                isRequired: true
            ),
            .disconnected
        )
    }

    func testOptionalEquipmentWithoutASelectionIsNotAdded() {
        XCTAssertEqual(
            EquipmentDisplayState(
                isConfigured: false,
                connectionState: .disconnected,
                isRequired: false
            ),
            .notAdded
        )
    }

    func testConfiguredEquipmentUsesItsLiveConnectionState() {
        XCTAssertEqual(
            EquipmentDisplayState(
                isConfigured: true,
                connectionState: .ready,
                isRequired: false
            ),
            .connected
        )
        XCTAssertEqual(
            EquipmentDisplayState(
                isConfigured: true,
                connectionState: .connecting(name: "KICKR"),
                isRequired: true
            ),
            .connecting
        )
        XCTAssertEqual(
            EquipmentDisplayState(
                isConfigured: true,
                connectionState: .failed("Asleep"),
                isRequired: false
            ),
            .disconnected
        )
    }

    func testDiscoveryTimesOutOnlyWhenNothingWasFound() {
        var discovery = DeviceDiscoveryState()
        discovery.start()
        discovery.finish(candidateCount: 0)
        XCTAssertEqual(discovery.phase, .timedOut)

        discovery.start()
        discovery.observe(candidateCount: 1)
        XCTAssertEqual(discovery.phase, .showingResults)
        discovery.finish(candidateCount: 1)
        XCTAssertEqual(discovery.phase, .showingResults)
    }

    func testRetryReturnsDiscoveryToSearching() {
        var discovery = DeviceDiscoveryState()
        discovery.start()
        discovery.finish(candidateCount: 0)
        discovery.start()
        XCTAssertEqual(discovery.phase, .searching)
    }

    func testALateCandidateRecoversFromTheEmptyState() {
        var discovery = DeviceDiscoveryState()
        discovery.start()
        discovery.finish(candidateCount: 0)
        discovery.observe(candidateCount: 1)
        XCTAssertEqual(discovery.phase, .showingResults)
    }
}
