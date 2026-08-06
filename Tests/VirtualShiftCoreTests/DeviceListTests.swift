import XCTest
@testable import VirtualShiftCore

/// The found-devices list, from the point of view of somebody reaching for a
/// row on a phone propped on the handlebars.
final class DeviceListTests: XCTestCase {
    private func candidate(
        _ id: UUID,
        _ name: String,
        _ rssi: Int,
        _ compatibility: TrainerCompatibility = .untested
    ) -> BluetoothCandidate {
        BluetoothCandidate(id: id, name: name, rssi: rssi, compatibility: compatibility)
    }

    func testDevicesKeepTheOrderTheyWereFoundIn() {
        let first = UUID()
        let second = UUID()
        var list: [BluetoothCandidate] = []
        list.absorb(candidate(first, "KICKR 1234", -80))
        list.absorb(candidate(second, "KICKR 5678", -50))

        // The second one is far stronger. It still must not jump the queue: a
        // row that moves while somebody is reaching for it is how the wrong
        // trainer gets tapped.
        XCTAssertEqual(list.map(\.id), [first, second])

        // And it must not overtake later either, however the signal drifts.
        list.absorb(candidate(first, "KICKR 1234", -95))
        XCTAssertEqual(list.map(\.id), [first, second])
    }

    func testSmallSignalDriftIsNotWorthRedrawing() {
        let id = UUID()
        var list: [BluetoothCandidate] = []
        XCTAssertTrue(list.absorb(candidate(id, "KICKR 1234", -60)))

        XCTAssertFalse(
            list.absorb(candidate(id, "KICKR 1234", -61)),
            "A decibel of drift moves nothing on screen and must not redraw it"
        )
        XCTAssertFalse(list.absorb(candidate(id, "KICKR 1234", -62)))
        XCTAssertTrue(
            list.absorb(candidate(id, "KICKR 1234", -63)),
            "Drift is measured against what is stored, so it cannot creep away "
                + "unnoticed one decibel at a time"
        )
        XCTAssertEqual(list.first?.rssi, -63)
    }

    func testTheReadingNeverLagsFarEnoughToChangeTheAutomaticChoice() {
        // The automatic choice needs one trainer to be 12 dB clearer than the
        // next. A stored reading is allowed to lag, so the lag has to stay well
        // inside that or the app could pick the wrong trainer.
        XCTAssertLessThan(
            [BluetoothCandidate].signalTolerance * 2,
            TrainerPicker.clearlyCloser
        )
    }

    func testSomethingTheRiderCanReadAlwaysUpdates() {
        let id = UUID()
        var list: [BluetoothCandidate] = []
        list.absorb(candidate(id, "Unnamed trainer", -60))

        XCTAssertTrue(
            list.absorb(candidate(id, "KICKR 1234", -60)),
            "A device that finally reports its name must show it"
        )
        XCTAssertTrue(
            list.absorb(candidate(id, "KICKR 1234", -60, .supported)),
            "And so must a change in whether it is known to work"
        )
        XCTAssertEqual(list.count, 1, "It is still one trainer, not three")
    }
}
