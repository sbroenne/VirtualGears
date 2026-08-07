import XCTest
@testable import VirtualGearsCore

final class TrainerPickerTests: XCTestCase {
    private func trainer() -> DiscoveredTrainer {
        DiscoveredTrainer(id: UUID())
    }

    func testNothingFoundAsks() {
        XCTAssertEqual(TrainerPicker.choice(from: []), .ask)
    }

    func testASingleTrainerIsConnectedWithoutAsking() {
        let only = trainer()

        XCTAssertEqual(
            TrainerPicker.choice(from: [only]),
            .connect(only.id)
        )
    }

    func testTwoTrainersAlwaysAsk() {
        XCTAssertEqual(
            TrainerPicker.choice(from: [trainer(), trainer()]),
            .ask
        )
    }

    func testThreeTrainersAlwaysAsk() {
        XCTAssertEqual(
            TrainerPicker.choice(from: [trainer(), trainer(), trainer()]),
            .ask
        )
    }
}
