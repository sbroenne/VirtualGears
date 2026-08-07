import XCTest
@testable import VirtualGearsCore

final class TrainerPickerTests: XCTestCase {
    private func trainer(_ strength: Int) -> DiscoveredTrainer {
        DiscoveredTrainer(id: UUID(), signalStrength: strength)
    }

    func testNothingFoundAsks() {
        XCTAssertEqual(TrainerPicker.choice(from: []), .ask)
    }

    /// The rider with one trainer in the room, which is the whole point.
    func testASingleTrainerInTheRoomIsConnectedWithoutAsking() {
        let only = trainer(-58)

        XCTAssertEqual(
            TrainerPicker.choice(from: [only]),
            .connect(only.id)
        )
    }

    /// One faint trainer is far more likely to be a neighbour's than the one
    /// the rider is sitting on.
    func testASingleDistantTrainerAsks() {
        XCTAssertEqual(TrainerPicker.choice(from: [trainer(-92)]), .ask)
    }

    func testTheNearTrainerWinsWhenTheOtherIsFarAway() {
        let mine = trainer(-52)
        let neighbour = trainer(-88)

        XCTAssertEqual(
            TrainerPicker.choice(from: [neighbour, mine]),
            .connect(mine.id)
        )
    }

    /// Two trainers at similar strength could be two bikes in one room, and
    /// choosing wrongly would change someone else's trainer.
    func testTwoSimilarTrainersAsk() {
        XCTAssertEqual(
            TrainerPicker.choice(from: [trainer(-55), trainer(-60)]),
            .ask
        )
    }

    /// Being the nearest is not enough when nothing is actually near.
    func testTheNearestIsNotTrustedWhenItIsStillFarAway() {
        XCTAssertEqual(
            TrainerPicker.choice(from: [trainer(-78), trainer(-95)]),
            .ask
        )
    }

    func testTheGapIsMeasuredAgainstTheSecondNearest() {
        let mine = trainer(-45)

        XCTAssertEqual(
            TrainerPicker.choice(from: [trainer(-90), mine, trainer(-80)]),
            .connect(mine.id)
        )
    }
}
