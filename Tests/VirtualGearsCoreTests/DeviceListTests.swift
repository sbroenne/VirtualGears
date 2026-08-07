import XCTest
@testable import VirtualGearsCore

/// The found-devices list, from the point of view of somebody reaching for a
/// row on a phone propped on the handlebars.
final class DeviceListTests: XCTestCase {
    private func candidate(
        _ id: UUID,
        _ name: String,
        _ compatibility: TrainerCompatibility = .untested
    ) -> BluetoothCandidate {
        BluetoothCandidate(id: id, name: name, compatibility: compatibility)
    }

    func testDevicesKeepTheOrderTheyWereFoundIn() {
        let first = UUID()
        let second = UUID()
        var list: [BluetoothCandidate] = []
        list.absorb(candidate(first, "KICKR 1234"))
        list.absorb(candidate(second, "KICKR 5678"))

        // A row that moves while somebody is reaching for it is how the wrong
        // trainer gets tapped.
        XCTAssertEqual(list.map(\.id), [first, second])
    }

    func testRepeatedSightingsAreNotWorthRedrawing() {
        let id = UUID()
        var list: [BluetoothCandidate] = []
        XCTAssertTrue(list.absorb(candidate(id, "KICKR 1234")))

        XCTAssertFalse(list.absorb(candidate(id, "KICKR 1234")))
    }

    func testSomethingTheRiderCanReadAlwaysUpdates() {
        let id = UUID()
        var list: [BluetoothCandidate] = []
        list.absorb(candidate(id, "Unnamed trainer"))

        XCTAssertTrue(
            list.absorb(candidate(id, "KICKR 1234")),
            "A device that finally reports its name must show it"
        )
        XCTAssertTrue(
            list.absorb(candidate(id, "KICKR 1234", .supported)),
            "And so must a change in whether it is known to work"
        )
        XCTAssertEqual(list.count, 1, "It is still one trainer, not three")
    }
}
