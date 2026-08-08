import XCTest
@testable import VirtualGearsCore

final class DemoRideStateTests: XCTestCase {
    func testDemoStartsOnTheConfiguredReferenceGear() throws {
        let configuration = AppConfiguration.demo
        let drivetrain = try XCTUnwrap(configuration.drivetrain)

        let state = DemoRideState(configuration: configuration)

        XCTAssertEqual(state.gearSequence, drivetrain.gears)
        XCTAssertEqual(state.selectedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(state.displayedGear, drivetrain.referenceGear)
    }

    func testDemoShiftsWithoutLeavingTheGearLadder() {
        var state = DemoRideState(configuration: .demo)

        for _ in 0..<100 {
            state.shift(.easier)
        }
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertFalse(state.canShiftEasier)

        for _ in 0..<100 {
            state.shift(.harder)
        }
        XCTAssertEqual(state.selectedIndex, state.gearSequence.count - 1)
        XCTAssertFalse(state.canShiftHarder)
    }

    func testChangingGearTypeRebuildsTheLocalDemoOnly() throws {
        var state = DemoRideState(configuration: .demo)
        var realBike = AppConfiguration.demo
        realBike.usesVirtualGears = false
        let drivetrain = try XCTUnwrap(realBike.drivetrain)

        state.use(realBike)

        XCTAssertEqual(state.gearSequence, drivetrain.gears)
        XCTAssertEqual(state.selectedIndex, drivetrain.referenceIndex)
        XCTAssertEqual(state.displayedGear, drivetrain.referenceGear)
    }
}
