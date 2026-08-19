import XCTest
@testable import VirtualGearsCore

/// These cover the rules that decide whether a rider can start at all. They
/// exist because those rules were being satisfied in one place and quietly
/// skipped in another, which left anyone installing the app unable to ride.
final class AppConfigurationTests: XCTestCase {
    /// A rider who has chosen a trainer and confirmed which gear the bike is
    /// parked in — the two things a ride genuinely needs.
    private func trainerReady() -> AppConfiguration {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        configuration.parkInSuggestion()
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

    /// A trainer on its own is not enough any more. The app also has to know
    /// which gear the bike is left sitting in, because that is what every
    /// virtual gear is scaled from and guessing it moves the whole ladder.
    func testATrainerAloneIsNotEnoughWithoutTheParkedGear() {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        XCTAssertTrue(configuration.hasValidKickr)
        XCTAssertFalse(configuration.canFinishSetup)
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

    func testForgettingAHeadwindClearsBothStoredFields() {
        var configuration = trainerReady()
        configuration.rememberHeadwind(named: "HEADWIND 9267", id: UUID())
        XCTAssertTrue(configuration.usesHeadwind)

        configuration.forgetHeadwind()

        XCTAssertNil(configuration.headwindName)
        XCTAssertNil(configuration.headwindUUID)
        XCTAssertFalse(configuration.usesHeadwind)
        XCTAssertTrue(configuration.canFinishSetup)
    }

    // MARK: - Gears the trainer can actually copy

    func testTheStartingChoiceIsSafeWithoutTheRiderTouchingAnything() {
        let configuration = trainerReady()
        XCTAssertTrue(configuration.usesVirtualGears)
        XCTAssertNotNil(configuration.drivetrain)
        XCTAssertTrue(configuration.hasSafeCircumference)
        XCTAssertEqual(configuration.drivetrainName, "Standard 24")
        XCTAssertEqual(
            configuration.gearSummary,
            "24 gears · 0.75 to 5.49, the common virtual ladder"
        )
    }

    /// A rider who never opened Custom still has parameters to fall back on
    /// if they later switch, and they start from the same numbers as Standard
    /// so switching to Custom for the first time changes nothing on its own.
    func testUnusedCustomLadderDefaultsMatchStandard() {
        let configuration = AppConfiguration()
        XCTAssertFalse(configuration.usesCustomLadder)
        XCTAssertEqual(configuration.customLadder.gearCount, 24)
        XCTAssertEqual(configuration.customLadder.easiestRatioHundredths, 75)
        XCTAssertEqual(configuration.customLadder.hardestRatioHundredths, 549)
    }

    /// Switching to Custom is what `gearLadder` should read once it happens,
    /// and the ladder it builds should have the rider's own gear count.
    func testSwitchingToCustomBuildsTheLadderFromTheRidersOwnParameters() {
        var configuration = trainerReady()
        configuration.customLadder = CustomGearLadder(
            gearCount: 12,
            easiestRatioHundredths: 100,
            hardestRatioHundredths: 300
        )
        configuration.gearLadderID = GearLadderCatalog.customLadderID

        XCTAssertTrue(configuration.usesCustomLadder)
        XCTAssertEqual(configuration.gearLadder.gearCount, 12)
        XCTAssertEqual(configuration.gearLadder.ratiosHundredths.first, 100)
        XCTAssertEqual(configuration.gearLadder.ratiosHundredths.last, 300)
        XCTAssertNotNil(configuration.drivetrain)
        XCTAssertTrue(configuration.hasSafeCircumference)
    }

    /// The same safety check that catches an impossible real drivetrain also
    /// has to catch an impossible custom ladder — a rider typing in a wide
    /// range should be told plainly, not left with a ride that fails later.
    func testACustomLadderThatIsTooWideForTheTrainerIsRejected() {
        var configuration = trainerReady()
        configuration.customLadder = CustomGearLadder(
            gearCount: 24,
            easiestRatioHundredths: 20,
            hardestRatioHundredths: 2_000
        )
        configuration.gearLadderID = GearLadderCatalog.customLadderID

        XCTAssertNil(configuration.drivetrain)
        XCTAssertFalse(configuration.hasSafeCircumference)
        XCTAssertFalse(configuration.canFinishSetup)
    }

    func testUnsafeParkedGearDoesNotMakeSafeGearingLookInvalid() throws {
        var configuration = trainerReady()
        let drivetrain = try XCTUnwrap(configuration.drivetrain)
        let unsuitable = try XCTUnwrap(
            ParkedGearAdvice.usableParkedGears(in: configuration.physical)
                .first {
                    !ParkedGearAdvice.isWorkable($0, simulating: drivetrain)
                }
        )

        configuration.park(in: unsuitable)

        XCTAssertTrue(configuration.hasSafeGearing)
        XCTAssertTrue(configuration.parkedGearPutsGearsOutOfReach)
        XCTAssertFalse(configuration.hasSafeCircumference)
        XCTAssertFalse(configuration.canFinishSetup)
    }

    /// A saved configuration from before Custom existed has no `customLadder`
    /// key at all. Decoding must fall back rather than throw away the rest of
    /// a rider's saved setup.
    // MARK: - Setup guide

    func testAFreshConfigurationHasNotSeenTheSetupGuide() {
        let configuration = AppConfiguration()
        XCTAssertFalse(configuration.setupWizardCompleted)
    }

    func testCompletingTheSetupGuideMarksItSeen() {
        var configuration = AppConfiguration()
        configuration.completeSetupWizard()
        XCTAssertTrue(configuration.setupWizardCompleted)
    }

    func testDecodingAConfigurationWithNoSetupWizardKeyFallsBackToNotSeen() throws {
        var configuration = AppConfiguration()
        configuration.completeSetupWizard()
        var data = try JSONEncoder().encode(configuration)
        var object = try JSONSerialization.jsonObject(
            with: data
        ) as! [String: Any]
        object.removeValue(forKey: "setupWizardCompleted")
        data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: data
        )
        XCTAssertFalse(decoded.setupWizardCompleted)
    }

    func testDecodingAConfigurationWithNoCustomLadderKeyFallsBackToDefault() throws {
        var configuration = AppConfiguration()
        configuration.rememberKickr(named: "KICKR CORE", id: UUID())
        var data = try JSONEncoder().encode(configuration)
        var object = try JSONSerialization.jsonObject(
            with: data
        ) as! [String: Any]
        object.removeValue(forKey: "customLadder")
        data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: data
        )
        XCTAssertEqual(decoded.customLadder, .default)
        XCTAssertFalse(decoded.usesCustomLadder)
    }

    func testNormalWheelSizeDefaultsTo2070Millimeters() {
        let configuration = AppConfiguration()
        XCTAssertEqual(configuration.neutralCircumferenceMillimeters, 2_070)
    }

    func testNormalWheelSizeCanBeChangedInsideTheSupportedRange() {
        var configuration = AppConfiguration()

        XCTAssertTrue(
            configuration.setNormalWheelCircumference(millimeters: 2_105)
        )
        XCTAssertEqual(configuration.neutralCircumferenceMillimeters, 2_105)
    }

    func testNormalWheelSizeRefusesValuesOutsideTheSupportedRange() {
        var configuration = AppConfiguration()

        XCTAssertFalse(
            configuration.setNormalWheelCircumference(millimeters: 1_799)
        )
        XCTAssertFalse(
            configuration.setNormalWheelCircumference(millimeters: 2_401)
        )
        XCTAssertEqual(configuration.neutralCircumferenceMillimeters, 2_070)
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

    func testRealDrivetrainsUsePartNamesAndDescribeTheirRange() {
        let expectedDescriptions = [
            "close together, for flat roads",
            "a normal road spread",
            "wide, with easy climbing gears",
            "very wide, for steep climbs",
        ]
        var observedDescriptions = Set<String>()

        for chainring in DrivetrainCatalog.chainrings {
            for cassette in DrivetrainCatalog.cassettes {
                var configuration = trainerReady()
                configuration.usesVirtualGears = false
                configuration.chainringID = chainring.id
                configuration.cassetteID = cassette.id
                guard configuration.drivetrain != nil else { continue }

                if let groupset = configuration.groupset {
                    XCTAssertEqual(
                        configuration.drivetrainName,
                        "\(groupset.qualifiedName) · "
                            + "\(chainring.name) \(cassette.name)"
                    )
                } else {
                    XCTAssertEqual(
                        configuration.drivetrainName,
                        "\(chainring.name) · \(cassette.name)"
                    )
                }
                for description in expectedDescriptions
                where configuration.gearSummary.contains(description) {
                    observedDescriptions.insert(description)
                }
            }
        }

        XCTAssertEqual(observedDescriptions, Set(expectedDescriptions))
    }

    // MARK: - Surviving an update

    /// The configuration is stored on the phone between launches, so a rider
    /// who already chose a trainer must not be asked to choose it again.
    func testAStoredConfigurationSurvivesBeingReloaded() throws {
        var configuration = trainerReady()
        configuration.rememberClick(named: "Zwift Click", id: UUID())
        configuration.rememberHeadwind(named: "HEADWIND 9267", id: UUID())
        configuration.setNormalWheelCircumference(millimeters: 2_105)
        let restored = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(restored, configuration)
        XCTAssertTrue(restored.canFinishSetup)
        XCTAssertTrue(restored.usesClick)
        XCTAssertTrue(restored.usesHeadwind)
        XCTAssertEqual(restored.neutralCircumferenceMillimeters, 2_105)
    }

    func testAConfigurationFromBeforeHeadwindSupportStillLoads() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "kickrName": "Wahoo KICKR",
              "kickrUUID": "\(id.uuidString)",
              "clickName": "",
              "clickUUID": "",
              "chainringID": "\(DrivetrainCatalog.defaultChainringID)",
              "cassetteID": "\(DrivetrainCatalog.defaultCassetteID)",
              "usesVirtualGears": true
            }
            """.utf8
        )

        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: data
        )

        XCTAssertTrue(configuration.hasValidKickr)
        XCTAssertFalse(configuration.usesHeadwind)
        XCTAssertEqual(configuration.neutralCircumferenceMillimeters, 2_070)
        // Fields added later fall back to their defaults rather than throwing
        // the whole saved setup away.
        XCTAssertEqual(
            configuration.gearLadderID,
            GearLadderCatalog.defaultLadderID
        )
        XCTAssertEqual(configuration.physical, .default)
        XCTAssertNil(configuration.parkedGear)
    }
}
