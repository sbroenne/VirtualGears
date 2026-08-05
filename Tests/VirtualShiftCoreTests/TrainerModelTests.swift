import Foundation
import XCTest
@testable import VirtualShiftCore

final class TrainerModelTests: XCTestCase {
    func testTheTrainerTheAppWasMeasuredAgainstIsSupported() {
        XCTAssertEqual(
            TrainerModel.compatibility(forAdvertisedName: "Wahoo KICKR 2A93"),
            .supported
        )
    }

    func testAnyWahooKickrIsSupportedWhateverItsSuffix() {
        for name in ["Wahoo KICKR 0000", "WAHOO KICKR FFFF", "wahoo kickr abcd"] {
            XCTAssertEqual(
                TrainerModel.compatibility(forAdvertisedName: name),
                .supported,
                "\(name) should be treated as supported"
            )
        }
    }

    func testTheSnapIsRefusedBecauseItShiftsAnotherWay() throws {
        let result = TrainerModel.compatibility(
            forAdvertisedName: "KICKR SNAP 1234"
        )
        guard case let .unsupported(model, reason) = result else {
            return XCTFail("The Snap should be refused, got \(result)")
        }
        XCTAssertEqual(model, "KICKR Snap")
        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(result.isUsable)
    }

    func testTheBikeIsRefusedBecauseItAlreadyHasGears() throws {
        let result = TrainerModel.compatibility(
            forAdvertisedName: "KICKR BIKE 5678"
        )
        guard case let .unsupported(model, _) = result else {
            return XCTFail("The Bike should be refused, got \(result)")
        }
        XCTAssertEqual(model, "KICKR Bike")
    }

    /// The model matters more than the maker's prefix, so a Snap is a Snap
    /// however Wahoo chooses to name it.
    func testAnUnsuitableModelIsCaughtEvenWithTheWahooPrefix() {
        XCTAssertFalse(
            TrainerModel
                .compatibility(forAdvertisedName: "Wahoo KICKR SNAP 1234")
                .isUsable
        )
        XCTAssertFalse(
            TrainerModel
                .compatibility(forAdvertisedName: "Wahoo KICKR BIKE 1234")
                .isUsable
        )
    }

    /// Newer trainers will appear that nobody has tried this with. Refusing
    /// them outright would be guessing, and the trainer confirms every gear
    /// change anyway, so it can answer for itself.
    func testAnUnfamiliarKickrIsAllowedRatherThanGuessedAt() {
        for name in ["KICKR MOVE 1234", "KICKR CORE 9999", "KICKR ROLLR 4321"] {
            XCTAssertEqual(
                TrainerModel.compatibility(forAdvertisedName: name),
                .untested,
                "\(name) should be allowed but not claimed as supported"
            )
            XCTAssertTrue(
                TrainerModel.compatibility(forAdvertisedName: name).isUsable
            )
        }
    }

    func testOnlyKickrsAreOffered() {
        XCTAssertTrue(TrainerModel.isKickr(advertisedName: "Wahoo KICKR 2A93"))
        XCTAssertTrue(TrainerModel.isKickr(advertisedName: "KICKR SNAP 1234"))
        XCTAssertFalse(TrainerModel.isKickr(advertisedName: "TACX NEO 2T"))
        XCTAssertFalse(TrainerModel.isKickr(advertisedName: "Elite Suito"))
    }

    /// The unsuitable trainers are still listed, because a rider who cannot
    /// find their trainer assumes the app is broken.
    func testUnsuitableTrainersAreStillListed() {
        XCTAssertTrue(TrainerModel.isKickr(advertisedName: "KICKR BIKE 5678"))
    }
}
