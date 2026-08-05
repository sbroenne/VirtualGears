import XCTest
@testable import VirtualShiftCore

/// These cover the rules that decide whether a rider can start at all. They
/// exist because those rules were being satisfied in one place and quietly
/// skipped in another, which left anyone installing the app unable to ride.
final class AppConfigurationTests: XCTestCase {
    private func trainerReady() -> AppConfiguration {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        return configuration
    }

    // MARK: - Choosing a trainer

    func testAFreshConfigurationCannotStartARide() {
        let configuration = AppConfiguration()
        XCTAssertFalse(configuration.hasValidKickr)
        XCTAssertFalse(configuration.canFinishSetup)
        XCTAssertFalse(configuration.setupComplete)
    }

    /// The regression this file was written for. A trainer found automatically
    /// used to be connected to without ever being recorded, so every check
    /// below stayed false and the rider waited forever with the start button
    /// disabled.
    func testRememberingATrainerIsEnoughToStartARide() {
        let configuration = trainerReady()
        XCTAssertTrue(configuration.hasValidKickr)
        XCTAssertTrue(configuration.canFinishSetup)
        XCTAssertTrue(configuration.setupComplete)
    }

    func testRememberingATrainerStoresSomethingTheAppCanReconnectTo() {
        let id = UUID()
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: id)
        XCTAssertEqual(configuration.kickrUUID, id.uuidString)
        XCTAssertEqual(UUID(uuidString: configuration.kickrUUID), id)
        XCTAssertEqual(configuration.kickrName, "KICKR CORE")
    }

    /// A trainer that only reported a blank name must not count as chosen, or
    /// the rider would be shown an empty row and no way to tell which it was.
    func testATrainerWithNoNameDoesNotCountAsChosen() {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "   ", id: UUID())
        XCTAssertFalse(configuration.hasValidKickr)
    }

    func testChoosingADifferentTrainerReplacesTheOldOne() {
        var configuration = trainerReady()
        let replacement = UUID()
        configuration.rememberKickr(named: "KICKR V5", id: replacement)
        XCTAssertEqual(configuration.kickrName, "KICKR V5")
        XCTAssertEqual(configuration.kickrUUID, replacement.uuidString)
    }

    // MARK: - The Click stays optional

    func testATrainerAloneIsEnoughAndAClickIsNeverRequired() {
        let configuration = trainerReady()
        XCTAssertFalse(configuration.usesClick)
        XCTAssertTrue(configuration.canFinishSetup)
    }

    func testForgettingAClickLeavesTheRideStillStartable() {
        var configuration = trainerReady()
        configuration.rememberClick(named: "Zwift Click", id: UUID())
        XCTAssertTrue(configuration.usesClick)

        configuration.forgetClick()
        XCTAssertFalse(configuration.usesClick)
        XCTAssertTrue(configuration.kickrName.isEmpty == false)
        XCTAssertTrue(configuration.canFinishSetup)
    }

    // MARK: - Gears the trainer can actually copy

    func testTheStartingChoiceIsSafeWithoutTheRiderTouchingAnything() {
        let configuration = trainerReady()
        XCTAssertTrue(configuration.usesVirtualGears)
        XCTAssertNotNil(configuration.drivetrain)
        XCTAssertTrue(configuration.hasSafeCircumference)
        XCTAssertEqual(configuration.drivetrainName, "Virtual gears")
    }

    /// Gears wider than the trainer can copy must block a ride rather than be
    /// sent to it, since the trainer works out speed from the wheel size.
    func testGearsTooWideForTheTrainerCannotStartARide() {
        var configuration = trainerReady()
        configuration.usesVirtualGears = false
        configuration.chainringID = DrivetrainCatalog.chainrings[0].id
        let widest = DrivetrainCatalog.cassettes.max {
            ($0.cogs.max() ?? 0) - ($0.cogs.min() ?? 0)
                < ($1.cogs.max() ?? 0) - ($1.cogs.min() ?? 0)
        }
        configuration.cassetteID = try! XCTUnwrap(widest).id

        if configuration.drivetrain == nil {
            XCTAssertFalse(configuration.hasSafeCircumference)
            XCTAssertFalse(configuration.canFinishSetup)
            XCTAssertEqual(
                configuration.gearSummary,
                "Too wide a range for the trainer"
            )
        } else {
            // Every drivetrain the catalogue offers should be rideable; if one
            // is not, that is worth knowing about rather than passing quietly.
            XCTAssertTrue(
                configuration.hasSafeCircumference,
                "A drivetrain offered in the app cannot be used on the trainer"
            )
        }
    }

    func testEveryDrivetrainTheAppOffersCanBeRidden() throws {
        for chainring in DrivetrainCatalog.chainrings {
            for cassette in DrivetrainCatalog.cassettes {
                var configuration = trainerReady()
                configuration.usesVirtualGears = false
                configuration.chainringID = chainring.id
                configuration.cassetteID = cassette.id
                guard configuration.drivetrain != nil else { continue }
                XCTAssertTrue(
                    configuration.hasSafeCircumference,
                    "\(chainring.name) with \(cassette.name) builds gears the "
                        + "trainer cannot copy"
                )
            }
        }
    }

    // MARK: - What the rider is told

    func testTheSetupDescriptionNamesTheGearEveryRideStartsIn() throws {
        let configuration = trainerReady()
        let drivetrain = try XCTUnwrap(configuration.drivetrain)
        XCTAssertTrue(
            configuration.setupDescription.contains(
                "gear \(drivetrain.referenceIndex + 1)"
            ),
            configuration.setupDescription
        )
        XCTAssertEqual(configuration.gearCount, drivetrain.gears.count)
    }

    // MARK: - Surviving an update

    /// The configuration is stored on the phone between launches, so a rider
    /// who already chose a trainer must not be asked to choose it again.
    func testAStoredConfigurationSurvivesBeingReloaded() throws {
        var configuration = trainerReady()
        configuration.rememberClick(named: "Zwift Click", id: UUID())
        let restored = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(restored, configuration)
        XCTAssertTrue(restored.canFinishSetup)
        XCTAssertTrue(restored.usesClick)
    }
}
