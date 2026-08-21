import XCTest

/// The maintained contract for "100% UX coverage": every intentionally
/// designed, app-owned visual state belongs here and is exercised by one of the
/// journey tests below. Adding a state without assigning it a test fails the
/// manifest completeness test.
private enum DesignedUXState: String, CaseIterable {
    // Setup wizard
    case wizardBikeCassette = "setup/bike-cassette"
    case wizardBikeSingleSprocket = "setup/bike-single-sprocket"
    case wizardParkedGearRecommended = "setup/parked-gear-recommended"
    case wizardParkedGearWarning = "setup/parked-gear-warning"
    case wizardAccessibilityText = "setup/accessibility-text"

    // Startup
    case startupSavedTrainerConnecting = "startup/saved-trainer-connecting"
    case startupLookingForTrainer = "startup/looking-for-trainer"
    case startupChooseTrainer = "startup/choose-trainer"
    case startupReady = "startup/ready"
    case startupMissingParkedGear = "startup/missing-parked-gear"
    case startupFailure = "startup/failure"

    // Ride
    case rideActive = "ride/active"
    case rideWaitingForApp = "ride/waiting-for-riding-app"
    case ridePendingShift = "ride/pending-shift"
    case rideClickPressed = "ride/click-pressed"
    case rideLowBattery = "ride/low-click-battery"
    case rideReconnecting = "ride/reconnecting"
    case rideStopping = "ride/stopping"
    case rideAppWheelSize = "ride/riding-app-wheel-size"
    case rideStopConfirmation = "ride/stop-confirmation"
    case rideLandscape = "ride/landscape"
    case rideAccessibilityText = "ride/accessibility-text"
    case rideDarkMode = "ride/dark-mode"

    // Settings and equipment
    case settingsConnected = "settings/connected"
    case settingsMissingParkedGear = "settings/missing-parked-gear"
    case settingsUnsafeGears = "settings/unsafe-gears"
    case settingsAccessibilityText = "settings/accessibility-text"
    case wheelSizeDefault = "settings/wheel-size-default"
    case wheelSizeShortcut = "settings/wheel-size-shortcut"
    case wheelSizeValid = "settings/wheel-size-valid"
    case wheelSizeInvalid = "settings/wheel-size-invalid"
    case trainerConnected = "equipment/trainer-connected"
    case trainerSearching = "equipment/trainer-searching"
    case trainerResults = "equipment/trainer-results"
    case trainerUnsupported = "equipment/trainer-unsupported"
    case trainerTimedOut = "equipment/trainer-timed-out"
    case trainerBluetoothIssue = "equipment/trainer-bluetooth-issue"
    case trainerStalled = "equipment/trainer-stalled"
    case clickConnected = "equipment/click-connected"
    case clickLowBattery = "equipment/click-low-battery"
    case clickDuplicatePrompt = "equipment/click-duplicate-prompt"
    case clickIdentifying = "equipment/click-identifying"
    case headwindSetup = "equipment/headwind-connected"

    // Simulated and physical gears
    case gearsVirtual = "gears/virtual"
    case gearsCustom = "gears/custom"
    case gearsRealBike = "gears/real-bike"
    case groupsetPicker = "gears/groupset-picker"
    case groupsetMatchBikeOffer = "gears/groupset-match-bike-offer"
    case chainringPicker = "gears/chainring-picker"
    case cassettePicker = "gears/cassette-picker"
    case gearPreviewTooWide = "gears/preview-too-wide"
    case parkedGearCassette = "physical/parked-gear-cassette"
    case parkedGearSingleSprocket = "physical/parked-gear-single-sprocket"
    case parkedGearOutOfReach = "physical/parked-gear-out-of-reach"

    // Headwind
    case headwindManual = "headwind/manual"
    case headwindAutomatic = "headwind/automatic"
    case headwindPending = "headwind/pending-command"
    case headwindError = "headwind/command-error"
    case headwindLandscape = "headwind/landscape"
    case headwindDarkMode = "headwind/dark-mode"

    // Demo
    case demoRide = "demo/ride"
    case demoSettings = "demo/settings"
    case demoGearSettings = "demo/gear-settings"
    case demoHeadwindAutomatic = "demo/headwind-automatic"
    case demoHeadwindManual = "demo/headwind-manual"
}

private let uxCoverageManifest: [DesignedUXState: String] = {
    var result: [DesignedUXState: String] = [:]
    func assign(_ states: [DesignedUXState], to test: String) {
        for state in states { result[state] = test }
    }
    assign([
        .wizardBikeCassette, .wizardBikeSingleSprocket,
        .wizardParkedGearRecommended, .wizardParkedGearWarning,
    ], to: "testUXCoverageSetupWizardStates")
    assign([
        .startupSavedTrainerConnecting, .startupLookingForTrainer,
        .startupChooseTrainer, .startupReady, .startupMissingParkedGear,
        .startupFailure,
    ], to: "testUXCoverageStartupStates")
    assign([
        .rideActive, .rideWaitingForApp, .ridePendingShift, .rideClickPressed,
        .rideLowBattery, .rideReconnecting, .rideStopping, .rideAppWheelSize,
        .rideStopConfirmation, .rideLandscape, .rideAccessibilityText,
    ], to: "testUXCoverageRideStates")
    assign([
        .settingsConnected, .settingsMissingParkedGear, .settingsUnsafeGears,
        .wheelSizeDefault, .wheelSizeShortcut, .wheelSizeValid,
        .wheelSizeInvalid, .trainerConnected,
        .trainerSearching, .trainerResults, .trainerUnsupported,
        .trainerTimedOut, .trainerBluetoothIssue, .trainerStalled,
        .clickConnected, .clickLowBattery, .clickDuplicatePrompt,
        .clickIdentifying, .headwindSetup,
    ], to: "testUXCoverageSettingsAndEquipmentStates")
    assign([
        .gearsVirtual, .gearsCustom, .gearsRealBike, .groupsetPicker,
        .groupsetMatchBikeOffer, .chainringPicker, .cassettePicker,
        .gearPreviewTooWide, .parkedGearCassette,
        .parkedGearSingleSprocket, .parkedGearOutOfReach,
    ], to: "testUXCoverageGearAndPhysicalBikeStates")
    assign([
        .headwindManual, .headwindAutomatic, .headwindPending, .headwindError,
        .headwindLandscape,
    ], to: "testUXCoverageHeadwindStates")
    assign([
        .wizardAccessibilityText, .settingsAccessibilityText, .rideDarkMode,
        .headwindDarkMode,
    ], to: "testUXCoverageAccessibilityAndAppearanceVariants")
    assign([
        .demoRide, .demoSettings, .demoGearSettings,
        .demoHeadwindAutomatic, .demoHeadwindManual,
    ], to: "testUXCoverageDemoStates")
    return result
}()

@MainActor
final class VirtualGearsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var capturedUXStates: Set<DesignedUXState> = []

    func testStartingScreenShowsEveryConfiguredEquipmentStatus() {
        launch("-shotStarting")

        assertVisible("screen.startup")
        XCTAssertTrue(app.navigationBars["Virtual Gears"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.buttons["Try Demo"].exists)
        assertStatusItems(["trainer", "click", "headwind"])
    }

    func testStartingScreenUsesWaitingStateInsteadOfDisabledStartAction() {
        launch("-shotStarting")

        assertVisibleElement(app.buttons["Waiting for trainer"])
        XCTAssertFalse(app.buttons["Start Shifting"].exists)
    }

    func testReadyScreenShowsTrainerAndRidingAppAdvertisingStatus() {
        launch("-shotReady")

        XCTAssertTrue(app.staticTexts["Ready to shift"].waitForExistence(timeout: 3))
        assertStatusItems(["trainer", "click", "headwind", "riding-app"])
        let ridingApp = app.descendants(matching: .any)["status.riding-app"]
        XCTAssertTrue(ridingApp.label.contains("Riding app"))
        XCTAssertTrue(ridingApp.label.contains("Waiting for connection"))
    }

    func testReadyScreenUsesPlatformNeutralNonDuplicativeStatusCopy() {
        launch("-shotReady")

        let trainer = app.descendants(matching: .any)["status.trainer"]
        let click = app.descendants(matching: .any)["status.click"]
        let fan = app.descendants(matching: .any)["status.headwind"]
        let ridingApp = app.descendants(matching: .any)["status.riding-app"]
        XCTAssertEqual(trainer.label, "Wahoo KICKR 2A93, Connected")
        XCTAssertEqual(click.label, "Zwift Click, Connected")
        XCTAssertEqual(fan.label, "KICKR HEADWIND 4D21, Connected")
        XCTAssertEqual(ridingApp.label, "Riding app, Waiting for connection")
    }

    func testRideShowsAllStatusIconsAndPrimaryControls() {
        launch("-shotRide")

        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift easier"])
        assertVisibleElement(app.buttons["Shift harder"])
        assertVisibleElement(app.buttons["Settings"])
        assertVisibleElement(app.buttons["Headwind controls"])
        assertVisibleElement(app.buttons["Stop virtual shifting"])
        assertVisibleElement(app.descendants(matching: .any)["Gear"].firstMatch)
        assertStatusItems(["kickr", "click", "headwind", "ridingapp"])
    }

    func testRideKeepsEveryStatusIndependentlyVisible() {
        launch("-shotRide")

        for identifier in ["kickr", "click", "headwind", "ridingapp"] {
            let item = app.descendants(matching: .any)["status.\(identifier)"]
            assertVisibleElement(item)
        }
    }

    func testAccessibilityRideKeepsStatusWordsAndToolbarSeparated() {
        launch("-shotRideAccessibility")

        for identifier in ["kickr", "click", "headwind", "ridingapp"] {
            let item = app.descendants(matching: .any)["status.\(identifier)"]
            assertVisibleElement(item)
            XCTAssertLessThanOrEqual(
                item.frame.height,
                70,
                "\(identifier) wrapped into a tall, broken label"
            )
        }
        let gearMenu = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "gears")
        ).firstMatch
        assertVisibleElement(gearMenu)
        for control in ["Settings", "Headwind controls"] {
            XCTAssertTrue(
                app.buttons[control].frame.intersection(gearMenu.frame).isNull,
                "The gear menu overlaps \(control)"
            )
        }
    }

    func testRideWaitingForRidingAppKeepsEveryEquipmentStatus() {
        launch("-shotRideWaiting")

        assertStatusItems(["kickr", "click", "headwind", "ridingapp"])
        XCTAssertTrue(
            app.descendants(matching: .any)["status.ridingapp"].label
                .contains("Waiting for connection")
        )
    }

    func testRideShowsLowClickBatteryWithoutReplacingStatuses() {
        launch("-shotRideLowBattery")

        assertStatusItems(["kickr", "click", "headwind", "ridingapp"])
        assertVisibleElement(app.descendants(matching: .any)["Click battery low, 15 percent"])
    }

    func testRideShowsPendingShiftFeedback() {
        launch("-shotRidePending")

        assertVisibleElement(app.staticTexts["Shifting…"])
        assertStatusItems(["kickr", "click", "headwind", "ridingapp"])
    }

    func testAcceptedClickPressMarksMatchingButtonPressed() {
        launch("-shotRidePressed")

        XCTAssertEqual(app.buttons["Shift harder"].value as? String, "Pressed")
        XCTAssertNotEqual(app.buttons["Shift easier"].value as? String, "Pressed")
    }

    func testReconnectProblemIsProminentAndPlainLanguage() {
        launch("-shotRideReconnecting")

        let problem = app.descendants(matching: .any)["status.kickr"]
        assertVisibleElement(problem)
        XCTAssertGreaterThanOrEqual(problem.frame.height, 32)
        XCTAssertTrue(problem.label.contains("Reconnecting"))
    }

    func testReconnectStatusIsSpelledOutRatherThanShrunkToAnIcon() {
        launch("-shotRideReconnecting")

        let status = app.descendants(matching: .any)["ride.status"]
        assertVisibleElement(status)
        XCTAssertEqual(status.label, "Control lost · reconnecting")
        XCTAssertGreaterThan(
            status.frame.width,
            200,
            "The ride status is squeezed down to a wordless icon"
        )
    }

    func testEveryEquipmentStatusSitsOnASingleRow() {
        launch("-shotRide")

        let centres = ["kickr", "click", "headwind", "ridingapp"].map {
            app.descendants(matching: .any)["status.\($0)"].frame.midY
        }
        let spread = (centres.max() ?? 0) - (centres.min() ?? 0)
        XCTAssertLessThan(
            spread,
            8,
            "The equipment statuses are split across rows, orphaning one of them"
        )
    }

    func testLowClickBatteryIsWarnedAboutRatherThanFootnoted() {
        launch("-shotRideLowBattery")

        let note = app.descendants(matching: .any)["note.clickBattery"]
        assertVisibleElement(note)
        XCTAssertGreaterThanOrEqual(
            note.frame.height,
            24,
            "A dying shifter battery is drawn as quietly as a caption"
        )
    }

    func testStartupFailureExplainsConflictAndOffersRetry() {
        launch("-shotFailed")

        assertVisibleElement(app.staticTexts["Shifting could not start"])
        assertVisibleElement(
            app.staticTexts[
                "Your trainer would not hand over control. Something else may still be connected to it."
            ]
        )
        assertVisibleElement(app.buttons["Try Again"])
    }

    func testRideStatusIconsRemainVisibleInLandscape() {
        launch("-shotRide")
        XCUIDevice.shared.orientation = .landscapeLeft

        assertVisible("screen.ride")
        assertStatusItems(["kickr", "click", "headwind", "ridingapp"])
        assertVisibleElement(app.buttons["Shift easier"])
        assertVisibleElement(app.buttons["Shift harder"])
    }

    func testRideOpensSettingsFanAndStopConfirmation() {
        launch("-shotRide")

        app.buttons["Settings"].tap()
        assertVisible("screen.settings")
        app.buttons["Done"].tap()

        app.buttons["Headwind controls"].tap()
        assertVisible("screen.headwind")
        app.buttons["Done"].tap()

        app.buttons["Stop virtual shifting"].tap()
        XCTAssertTrue(app.staticTexts["Stop virtual shifting?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Stop Shifting"].exists)
    }

    func testStoppingRequiresConfirmationBeforeRideControlsDisappear() {
        launch("-shotRide")

        app.buttons["Stop virtual shifting"].tap()

        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift easier"])
        assertVisibleElement(app.buttons["Shift harder"])
        assertVisibleElement(app.buttons["Stop Shifting"])
    }

    func testCancellingTheStopConfirmationReturnsToTheRide() {
        launch("-shotRide")

        app.buttons["Stop virtual shifting"].tap()

        assertVisibleElement(app.buttons["Stop Shifting"])
        assertVisibleElement(app.buttons["Cancel"])

        app.buttons["Cancel"].tap()

        XCTAssertFalse(
            app.buttons["Stop Shifting"].waitForExistence(timeout: 1),
            "Cancelling left the confirmation on screen"
        )
        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift easier"])
        assertVisibleElement(app.buttons["Shift harder"])
        assertVisibleElement(app.buttons["Stop virtual shifting"])
    }

    func testSetupGuideWalksBikeThenParkedGear() {
        launch("-shotSetupWizard")

        assertVisible("screen.setupWizard")
        XCTAssertTrue(
            app.navigationBars["Set up Virtual Gears"].waitForExistence(timeout: 2)
        )
        assertVisibleElement(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Standard 24")
        ).firstMatch)
        XCTAssertFalse(app.buttons["Set up later"].exists)
        app.buttons["wizard.useBikeSetup"].tap()

        XCTAssertTrue(
            app.navigationBars["Position your chain"].waitForExistence(timeout: 2)
        )
        let finish = app.buttons["Finish setup"]
        XCTAssertTrue(finish.waitForExistence(timeout: 2))
        XCTAssertTrue(finish.isEnabled)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Set up Virtual Gears"].waitForExistence(timeout: 2),
            "Back from chain position should return to the physical bike"
        )
    }

    func testFirstRunOffersZwiftCogAndAnySingleSprocket() {
        launch("-shotSetupWizard")

        let single = app.buttons["wizard.rear.singleSprocket"]
        assertVisibleElement(single)
        XCTAssertTrue(single.label.contains("Zwift Cog"))
        single.tap()
        XCTAssertTrue(single.isSelected)
        XCTAssertEqual(app.steppers["wizard.sprocketTeeth"].value as? String, "14")
        app.buttons["wizard.sprocketTeeth-Increment"].tap()
        XCTAssertEqual(app.steppers["wizard.sprocketTeeth"].value as? String, "15")

        app.buttons["wizard.useBikeSetup"].tap()
        XCTAssertTrue(
            app.navigationBars["Position your chain"].waitForExistence(timeout: 2)
        )
        assertVisibleElement(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "/15")
            ).firstMatch
        )
    }

    func testFirstRunHasNoDismissAction() {
        launch("-shotSetupWizard")

        assertVisible("screen.setupWizard")
        XCTAssertFalse(app.buttons["Set up later"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)
    }

    func testSettingsDoesNotOfferTheFirstRunWizardAgain() {
        launch("-shotSettings")

        assertVisible("screen.settings")
        XCTAssertFalse(app.staticTexts["Run setup guide again"].exists)
        XCTAssertFalse(app.staticTexts["Start the full setup guide"].exists)
    }

    func testWheelCircumferenceShortcutsManualEntryAndDefault() {
        launch("-shotSettings")
        app.staticTexts["Wheel circumference"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Wheel circumference"].waitForExistence(timeout: 2)
        )

        let field = app.textFields["Millimetres"]
        let shortcuts = app.scrollViews["wheel.shortcuts"]
        let choices = [
            ("Road, 700×25, 2105 millimetres", "2105"),
            ("Road, 700×28, 2136 millimetres", "2136"),
            ("Gravel, 700×40, 2200 millimetres", "2200"),
            ("MTB, 26×2.0, 2055 millimetres", "2055"),
            ("MTB, 27.5×2.25, 2188 millimetres", "2188"),
            ("MTB, 29×2.25, 2326 millimetres", "2326"),
        ]

        for (label, expectedValue) in choices {
            let button = app.buttons[label]
            for _ in 0..<6 where !button.exists || !button.isHittable {
                shortcuts.swipeLeft(velocity: .slow)
            }
            XCTAssertTrue(button.isHittable, "\(label) is not reachable")
            button.tap()
            XCTAssertEqual(field.value as? String, expectedValue)
            XCTAssertTrue(button.isSelected)
        }

        field.tap()
        field.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8)
        )
        field.typeText("2180")
        XCTAssertEqual(field.value as? String, "2180")
        XCTAssertFalse(
            app.buttons["MTB, 29×2.25, 2326 millimetres"].isSelected
        )

        let useDefault = app.buttons["wheel.useDefault"]
        XCTAssertTrue(useDefault.isEnabled)
        useDefault.tap()
        XCTAssertEqual(field.value as? String, "2105")
        expectation(
            for: NSPredicate(format: "isEnabled == NO"),
            evaluatedWith: useDefault
        )
        waitForExpectations(timeout: 2)
        app.navigationBars.buttons.firstMatch.tap()
        assertVisibleElement(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Default · 2105 mm")
        ).firstMatch)
    }

    func testSettingsNavigatesToEveryDestination() {
        launch("-shotSettings")

        assertVisible("screen.settings")
        for destination in [
            "Trainer", "Zwift Click", "Wahoo Headwind", "Gears",
        ] {
            let row = app.staticTexts[destination].firstMatch
            assertVisibleElement(row)
            row.tap()
            XCTAssertTrue(
                app.navigationBars[destination].waitForExistence(timeout: 2),
                "\(destination) screen did not open"
            )
            app.navigationBars.buttons.firstMatch.tap()
        }

        // The parked-gear row's title and value collapse into a single
        // accessibility element, so it is reached by identifier rather than
        // its title text like the rows above. It also sits below the fold
        // now that the setup guide row was added at the top, so the list
        // needs a scroll before it is on screen.
        app.swipeUp()
        let parkedGearRow = app.descendants(matching: .any)["row.parkedGear"]
        assertVisibleElement(parkedGearRow)
        parkedGearRow.tap()
        XCTAssertTrue(
            app.navigationBars["Gear the bike is in"].waitForExistence(timeout: 2),
            "Gear the bike is in screen did not open"
        )
        app.navigationBars.buttons.firstMatch.tap()
    }

    /// The gear the bike is parked in is the one thing setup cannot guess, so
    /// the screen has to name a gear, mark it as the recommendation and let it
    /// be confirmed in a tap.
    func testParkedGearScreenRecommendsAGearAndLetsItBeConfirmed() {
        launch("-shotSettings")

        // The row is below the fold once the setup guide row is above it.
        app.swipeUp()
        app.descendants(matching: .any)["row.parkedGear"].firstMatch.tap()
        assertVisible("screen.parkedGear")

        // The advice has to name a gear rather than describe one, because
        // "a quiet, straight chain line" is true of gears twice as hard as
        // each other.
        let advice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Park the chain on the")
        ).firstMatch
        XCTAssertTrue(advice.waitForExistence(timeout: 3))

        // Gears that would put part of the ladder beyond the trainer's reach
        // are still listed, and say so, rather than silently vanishing.
        let outOfReach = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@", "Puts some gears out of reach"
            )
        ).firstMatch
        XCTAssertTrue(outOfReach.waitForExistence(timeout: 3))

        // Confirming one of them has to stick and has to leave a one-tap way
        // back, rather than the app silently overriding the rider.
        outOfReach.tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Use ")
            ).firstMatch.waitForExistence(timeout: 3),
            "Confirming another gear should offer a way back to the "
                + "recommendation"
        )

        app.navigationBars.buttons.firstMatch.tap()
        assertVisible("screen.settings")
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "gears fall outside the trainer's safe range"
                )
            ).firstMatch.exists,
            "A bad parked gear must not make valid simulated gearing look unsafe"
        )
        let finishSetup = app.descendants(matching: .any)["action.finishSetup"]
            .firstMatch
        for _ in 0..<3 where !finishSetup.exists || !finishSetup.isHittable {
            app.swipeDown()
        }
        assertVisibleElement(finishSetup)
        XCTAssertTrue(finishSetup.label.contains("Confirm the gear"))
        finishSetup.tap()
        assertVisible("screen.parkedGear")
    }


    /// The parked gear is the app's biggest silent-failure risk, so a rider who
    /// has not confirmed one is told exactly that rather than being told to wait
    /// for a trainer that is already connected. It also used to be disabled,
    /// naming an action it wouldn't perform — now it opens Settings itself.
    func testStartNamesTheParkedGearWhenThatIsWhatIsMissing() {
        launch("-shotUnparked")

        let button = app.buttons["Set the gear you are in"]
        assertVisibleElement(button)
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(app.buttons["Waiting for trainer"].exists)
        XCTAssertFalse(app.buttons["Start Shifting"].exists)

        button.tap()
        assertVisibleElement(app.navigationBars["Settings"])
    }

    func testVirtualGearChoiceShowsModeAndPreview() {
        launch("-shotGears")

        assertVisible("screen.gears")
        XCTAssertTrue(app.buttons["Virtual gears"].exists)
        XCTAssertTrue(app.buttons["Copy a real bike"].exists)
        assertVisibleElement(app.staticTexts["24 gears"].firstMatch)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "same hard end")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "very wide")
        ).firstMatch.exists)
    }

    func testGearModeCanSwitchBetweenVirtualAndRealBikeOptions() {
        launch("-shotGears")

        app.buttons["Copy a real bike"].tap()
        assertVisibleElement(app.staticTexts["Chainrings"])
        assertVisibleElement(app.staticTexts["Cassette"])

        app.buttons["Virtual gears"].tap()
        XCTAssertFalse(app.staticTexts["Chainrings"].exists)
        XCTAssertFalse(app.staticTexts["Cassette"].exists)
        assertVisibleElement(app.staticTexts["24 gears"].firstMatch)
    }

    func testRealGearChoiceNavigatesToChainringsAndCassette() {
        launch("-shotRealGears")

        assertVisible("screen.gears")
        assertVisibleElement(app.staticTexts["Chainrings"])
        assertVisibleElement(app.staticTexts["Cassette"])

        app.staticTexts["Chainrings"].tap()
        XCTAssertTrue(app.navigationBars["Chainrings"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.firstMatch.tap()

        app.staticTexts["Cassette"].tap()
        XCTAssertTrue(app.navigationBars["Cassette"].waitForExistence(timeout: 2))
    }

    /// Regression test for a rendering bug: every selectable row added for
    /// setup (ladders, groupsets, physical parts, the parked gear) was a
    /// hand-rolled `Button` that iOS 26 rendered entirely in the accent
    /// colour, rather than the standard black-text-with-a-blue-checkmark
    /// list style every other row in the app uses. `.buttonStyle(.plain)`
    /// alone did not fix it. The rows now all share the one `ChoiceRow`
    /// already proven correct by the pre-existing chainring/cassette
    /// pickers, so this exercises that every one of them still reports
    /// exactly one selected row, and that tapping a different one moves the
    /// selection rather than leaving two rows marked or none at all.
    func testGroupsetChoiceMovesTheCheckmarkOnSelection() {
        launch("-shotRealGears")

        assertVisible("screen.gears")
        app.staticTexts["Groupset"].tap()
        XCTAssertTrue(app.navigationBars["Groupset"].waitForExistence(timeout: 2))

        let current = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Shimano 105 R7100")
        ).firstMatch
        let other = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Shimano Dura-Ace R9200")
        ).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 2))
        XCTAssertTrue(other.waitForExistence(timeout: 2))
        XCTAssertTrue(current.isSelected)
        XCTAssertFalse(other.isSelected)

        other.tap()
        XCTAssertTrue(other.isSelected)
        XCTAssertFalse(current.isSelected)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Groupset, Shimano Dura-Ace R9200"]
                .waitForExistence(timeout: 2)
        )
    }

    /// Same regression coverage as above, for the virtual gear ladder rows —
    /// updated for the Standard/Custom redesign: one built-in ladder plus a
    /// rider-defined one, instead of choosing between two fixed tables.
    func testGearLadderChoiceCanSwitchToACustomLadderAndBack() {
        launch("-shotGears")

        assertVisible("screen.gears")
        let standard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Standard 24")
        ).firstMatch
        XCTAssertTrue(standard.waitForExistence(timeout: 2))
        XCTAssertTrue(standard.isSelected)

        let custom = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Custom")
        ).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 2))
        XCTAssertFalse(custom.isSelected)

        custom.tap()
        XCTAssertTrue(
            app.navigationBars["Custom Ladder"].waitForExistence(timeout: 2)
        )
        app.navigationBars.buttons.firstMatch.tap()

        assertVisible("screen.gears")
        XCTAssertFalse(standard.isSelected)
        XCTAssertTrue(custom.isSelected)

        standard.tap()
        XCTAssertTrue(standard.isSelected)
        XCTAssertFalse(custom.isSelected)
    }

    /// Editing the gear count on the Custom ladder screen should change the
    /// preview at the bottom — proof the rider's own numbers actually reach
    /// the gearing that gets simulated, not just a label.
    func testCustomLadderGearCountChangesThePreview() {
        launch("-shotGears")
        assertVisible("screen.gears")

        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Custom")
        ).firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Custom Ladder"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["24 gears"].waitForExistence(timeout: 2))

        app.steppers.firstMatch.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["25 gears"].waitForExistence(timeout: 2))
    }

    /// Same regression coverage, for the physical chainring and cassette
    /// pickers reached from the parked-gear screen.
    func testPhysicalChainringAndCassetteChoicesUpdateTheSummary() {
        launch("-shotSettings")

        // The row is below the fold once the setup guide row is above it.
        app.swipeUp()
        app.descendants(matching: .any)["row.parkedGear"].firstMatch.tap()
        assertVisible("screen.parkedGear")

        app.staticTexts["Chainrings"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Chainrings on the bike"].waitForExistence(timeout: 2)
        )
        assertVisibleElement(app.staticTexts["One chainring"])
        let ring38 = app.buttons.matching(
            NSPredicate(format: "label == %@", "38")
        ).firstMatch
        let ring40 = app.buttons.matching(
            NSPredicate(format: "label == %@", "40")
        ).firstMatch
        assertVisibleElement(ring38)
        assertVisibleElement(ring40)
        XCTAssertLessThan(ring38.frame.minY, ring40.frame.minY)
        let defaultChainring = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "50/34")
        ).firstMatch
        let otherChainring = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "38")
        ).firstMatch
        for _ in 0..<3 where !app.staticTexts["Two chainrings"].exists {
            app.swipeUp()
        }
        assertVisibleElement(app.staticTexts["Two chainrings"])
        for _ in 0..<3 where !defaultChainring.exists {
            app.swipeUp()
        }
        XCTAssertTrue(defaultChainring.isSelected)
        for _ in 0..<3 where !otherChainring.isHittable {
            app.swipeDown()
        }
        XCTAssertFalse(otherChainring.isSelected)
        otherChainring.tap()
        XCTAssertTrue(otherChainring.isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Chainrings, 38"].waitForExistence(timeout: 2)
        )

        app.staticTexts["Cassette"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Cassette on the bike"].waitForExistence(timeout: 2)
        )
        let otherCassette = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "11-30 · 11 cogs")
        ).firstMatch
        XCTAssertTrue(otherCassette.waitForExistence(timeout: 2))
        XCTAssertFalse(otherCassette.isSelected)
        otherCassette.tap()
        XCTAssertTrue(otherCassette.isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Cassette, 11-30"].waitForExistence(timeout: 2)
        )
    }

    func testHeadwindControlsExposeModeSpeedAndPresets() {
        launch("-shotHeadwind")

        assertVisible("screen.headwind")
        XCTAssertTrue(app.buttons["Automatic"].exists)
        XCTAssertTrue(app.buttons["Manual"].exists)
        ["Fan off", "25 percent", "50 percent", "75 percent", "100 percent"].forEach {
            assertVisibleElement(app.buttons[$0])
        }
        assertVisibleElement(app.buttons["Slower"])
        assertVisibleElement(app.buttons["Faster"])
    }

    func testDemoSupportsShiftingSettingsAndFanControls() {
        launch("-shotDemo")

        assertVisible("screen.demo")
        XCTAssertTrue(app.navigationBars["Demo Ride"].exists)
        assertVisibleElement(
            app.staticTexts[
                "Try the same large shift buttons and gear display used during a real ride."
            ]
        )
        let gear = app.descendants(matching: .any)["Simulated gear"]
        assertVisibleElement(gear)
        let initialValue = gear.value as? String
        app.buttons["Shift harder"].tap()
        expectation(
            for: NSPredicate(format: "value != %@", initialValue ?? ""),
            evaluatedWith: gear
        )
        waitForExpectations(timeout: 2)

        app.buttons["Settings"].tap()
        assertVisible("screen.demo-settings")
        app.buttons["Done"].tap()

        app.buttons["Fan"].tap()
        assertVisible("screen.demo-headwind")
        app.buttons["Manual"].tap()
        assertVisibleElement(app.buttons["50 percent"])
    }

    func testDemoShiftButtonsAreDrawnLikeTheRideScreensAreWithDistinctWeight() {
        launch("-shotDemo")

        let easier = app.buttons["Shift easier"]
        let harder = app.buttons["Shift harder"]
        assertVisibleElement(easier)
        assertVisibleElement(harder)

        let easierColor = averageColor(of: easier)
        let harderColor = averageColor(of: harder)
        XCTAssertGreaterThan(
            colorDistance(easierColor, harderColor),
            0.1,
            "Demo's Easier and Harder buttons look identical, unlike the ride screen"
        )
    }

    func testDemoCanShiftHarderAndEasierBackToItsStartingGear() {
        launch("-shotDemo")

        let gear = app.descendants(matching: .any)["Simulated gear"]
        assertVisibleElement(gear)
        let initialValue = gear.value as? String

        app.buttons["Shift harder"].tap()
        expectation(
            for: NSPredicate(format: "value != %@", initialValue ?? ""),
            evaluatedWith: gear
        )
        waitForExpectations(timeout: 2)

        app.buttons["Shift easier"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", initialValue ?? ""),
            evaluatedWith: gear
        )
        waitForExpectations(timeout: 2)
    }

    func testDemoFanPresetsChangeTheDisplayedSpeed() {
        launch("-shotDemo")

        app.buttons["Fan"].tap()
        assertVisible("screen.demo-headwind")
        app.buttons["Manual"].tap()
        app.buttons["75 percent"].tap()

        XCTAssertTrue(app.buttons["75 percent"].isSelected)
        XCTAssertFalse(app.buttons["50 percent"].isSelected)
    }

    func testDesignedUXStateManifestIsComplete() {
        XCTAssertEqual(
            Set(uxCoverageManifest.keys),
            Set(DesignedUXState.allCases),
            "Every designed app-owned state must be assigned to executable UX coverage."
        )
        XCTAssertTrue(
            uxCoverageManifest.values.allSatisfy { $0.hasPrefix("testUXCoverage") },
            "Coverage entries must name a journey test rather than prose or a ticket."
        )
    }

    func testUXCoverageSetupWizardStates() {
        launch("-shotSetupWizard")
        XCTAssertTrue(
            app.navigationBars["Set up Virtual Gears"].waitForExistence(timeout: 2)
        )
        assertVisibleElement(app.buttons["wizard.rear.cassette"])
        capture(.wizardBikeCassette)

        let singleSprocket = app.buttons["wizard.rear.singleSprocket"]
        singleSprocket.tap()
        XCTAssertTrue(singleSprocket.isSelected)
        assertVisibleElement(app.steppers["wizard.sprocketTeeth"])
        capture(.wizardBikeSingleSprocket)

        app.buttons["wizard.rear.cassette"].tap()
        app.buttons["wizard.useBikeSetup"].tap()
        XCTAssertTrue(
            app.navigationBars["Position your chain"].waitForExistence(timeout: 2)
        )
        assertVisibleElement(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Park the chain on")
        ).firstMatch)
        capture(.wizardParkedGearRecommended)

        let recommended = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Recommended")
        ).firstMatch
        assertVisibleElement(recommended)
        let outOfReach = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Puts some gears out of reach")
        ).firstMatch
        for _ in 0..<10 where !isFullyVisible(outOfReach) {
            app.swipeUp(velocity: .slow)
        }
        assertVisibleElement(outOfReach)
        outOfReach.tap()
        let warning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "cannot reach")
        ).firstMatch
        for _ in 0..<10 where !isFullyVisible(warning) {
            app.swipeDown(velocity: .slow)
        }
        assertVisibleElement(warning)
        capture(.wizardParkedGearWarning)

        launch("-shotSetupWizard")
        app.buttons["wizard.useBikeSetup"].tap()
        XCTAssertTrue(app.buttons["Finish setup"].isEnabled)
        assertJourneyCoverage()
    }

    func testUXCoverageStartupStates() {
        launch("-shotStarting")
        assertVisibleElement(app.staticTexts["Getting Virtual Gears ready"])
        capture(.startupSavedTrainerConnecting)

        launch("-shotStartupLooking")
        assertVisibleElement(app.staticTexts["Looking for your trainer"])
        capture(.startupLookingForTrainer)

        launch("-shotStartupChoosing")
        assertVisibleElement(app.staticTexts["Which one is yours?"])
        assertVisibleElement(app.buttons["Wahoo KICKR 2A93"])
        capture(.startupChooseTrainer)

        launch("-shotReady")
        assertVisibleElement(app.staticTexts["Ready to shift"])
        assertVisibleElement(app.buttons["Start Shifting"])
        capture(.startupReady)

        launch("-shotUnparked")
        assertVisibleElement(app.buttons["Set the gear you are in"])
        capture(.startupMissingParkedGear)

        launch("-shotFailed")
        assertVisibleElement(app.staticTexts["Shifting could not start"])
        assertVisibleElement(app.buttons["Try Again"])
        capture(.startupFailure)
        assertJourneyCoverage()
    }

    func testUXCoverageRideStates() {
        launch("-shotRide")
        assertVisible("screen.ride")
        capture(.rideActive)

        launch("-shotRideWaiting")
        XCTAssertTrue(
            app.descendants(matching: .any)["status.ridingapp"].label
                .contains("Waiting for connection")
        )
        capture(.rideWaitingForApp)

        launch("-shotRidePending")
        assertVisibleElement(app.staticTexts["Shifting…"])
        capture(.ridePendingShift)

        launch("-shotRidePressed")
        XCTAssertEqual(app.buttons["Shift harder"].value as? String, "Pressed")
        capture(.rideClickPressed)

        launch("-shotRideLowBattery")
        assertVisibleElement(
            app.descendants(matching: .any)["Click battery low, 15 percent"]
        )
        capture(.rideLowBattery)

        launch("-shotRideReconnecting")
        assertVisibleElement(app.descendants(matching: .any)["ride.status"])
        capture(.rideReconnecting)

        launch("-shotRideStopping")
        assertVisibleElement(app.descendants(matching: .any)["ride.status"])
        capture(.rideStopping)

        launch("-shotRideWheelSize")
        assertVisibleElement(
            app.descendants(matching: .any)["note.ridingAppWheelSize"]
        )
        capture(.rideAppWheelSize)

        launch("-shotRide")
        app.buttons["Stop virtual shifting"].tap()
        assertVisibleElement(app.staticTexts["Stop virtual shifting?"])
        assertVisibleElement(app.buttons["Cancel"])
        assertVisibleElement(app.buttons["Stop Shifting"])
        capture(.rideStopConfirmation)

        launch("-shotRide", orientation: .landscapeLeft)
        waitForLandscapeLayout()
        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift easier"])
        assertVisibleElement(app.buttons["Shift harder"])
        capture(.rideLandscape)

        launch("-shotRideAccessibility")
        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift easier"])
        capture(.rideAccessibilityText)
        assertJourneyCoverage()

    }

    func testUXCoverageSettingsAndEquipmentStates() {
        launch("-shotSettings")
        assertVisible("screen.settings")
        capture(.settingsConnected)

        launch("-shotUnparked")
        app.buttons["Set the gear you are in"].tap()
        assertVisible("screen.settings")
        let finishSetup = app.descendants(matching: .any)["action.finishSetup"]
            .firstMatch
        assertVisibleElement(finishSetup)
        XCTAssertTrue(finishSetup.label.contains("Confirm the gear"))
        capture(.settingsMissingParkedGear)
        scrollToParkedGearRow()
        let missingParkedGear = app.descendants(matching: .any)[
            "row.parkedGear"
        ].firstMatch
        XCTAssertTrue(
            missingParkedGear.label.contains("Needed")
        )
        launch("-shotSettingsUnsafeGears")
        assertVisible("screen.settings")
        let chooseSafeGears = app.descendants(matching: .any)["action.finishSetup"]
            .firstMatch
        assertVisibleElement(chooseSafeGears)
        XCTAssertTrue(chooseSafeGears.label.contains("Choose gears that fit"))
        capture(.settingsUnsafeGears)


        launch("-shotSettings")
        app.staticTexts["Wheel circumference"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Wheel circumference"].waitForExistence(timeout: 2)
        )
        let useDefault = app.buttons["wheel.useDefault"]
        XCTAssertFalse(useDefault.isEnabled)
        capture(.wheelSizeDefault)

        let road28 = app.buttons["Road, 700×28, 2136 millimetres"]
        assertVisibleElement(road28)
        road28.tap()
        XCTAssertTrue(road28.isSelected)
        capture(.wheelSizeShortcut)

        let field = app.textFields["Millimetres"]
        XCTAssertEqual(field.value as? String, "2136")
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText("2180")
        XCTAssertFalse(road28.isSelected)
        capture(.wheelSizeValid)

        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText("999")
        app.swipeUp()
        assertVisibleElement(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Enter a value from")
        ).firstMatch)
        capture(.wheelSizeInvalid)

        openSettingsDestination("Trainer", fixture: "-shotSettings")
        capture(.trainerConnected)
        openSettingsDestination("Trainer", fixture: "-shotSettingsSearching")
        assertVisibleElement(app.staticTexts["Looking for trainers…"])
        capture(.trainerSearching)
        openSettingsDestination("Trainer", fixture: "-shotSettingsResults")
        assertVisibleElement(app.buttons["Wahoo KICKR 7B20"])
        capture(.trainerResults)
        openSettingsDestination("Trainer", fixture: "-shotSettingsUnsupported")
        assertVisibleElement(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Wheel-on trainers")
        ).firstMatch)
        capture(.trainerUnsupported)
        openSettingsDestination("Trainer", fixture: "-shotSettingsTimedOut")
        assertVisibleElement(app.staticTexts["No trainer found"])
        capture(.trainerTimedOut)
        openSettingsDestination("Trainer", fixture: "-shotSettingsBluetoothIssue")
        assertVisibleElement(app.buttons["Open Bluetooth Settings"])
        capture(.trainerBluetoothIssue)
        openSettingsDestination("Trainer", fixture: "-shotSettingsStalled")
        assertVisibleElement(app.staticTexts["Still trying to connect"])
        capture(.trainerStalled)

        openSettingsDestination("Zwift Click", fixture: "-shotSettings")
        assertVisibleElement(app.staticTexts["Battery 82%"])
        capture(.clickConnected)
        openSettingsDestination("Zwift Click", fixture: "-shotSettingsClickLowBattery")
        assertVisibleElement(app.staticTexts["Worth replacing the battery soon."])
        capture(.clickLowBattery)
        openSettingsDestination("Zwift Click", fixture: "-shotSettingsClickDuplicates")
        assertVisibleElement(app.buttons["Identify by pressing a button"])
        capture(.clickDuplicatePrompt)
        openSettingsDestination("Zwift Click", fixture: "-shotSettingsClickIdentifying")
        assertVisibleElement(
            app.staticTexts["Keep pressing either button on the Click you want."]
        )
        capture(.clickIdentifying)

        openSettingsDestination("Wahoo Headwind", fixture: "-shotSettings")
        assertVisibleElement(app.staticTexts["KICKR HEADWIND 4D21"])
        capture(.headwindSetup)
        assertJourneyCoverage()
    }

    func testUXCoverageGearAndPhysicalBikeStates() {
        launch("-shotGears")
        assertVisible("screen.gears")
        capture(.gearsVirtual)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Custom")
        ).firstMatch.tap()
        assertVisible("screen.customGearLadder")
        capture(.gearsCustom)

        launch("-shotRealGears")
        assertVisible("screen.gears")
        capture(.gearsRealBike)

        app.staticTexts["Groupset"].tap()
        assertVisible("screen.groupset")
        capture(.groupsetPicker)
        let dura = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Dura-Ace R9200")
        ).firstMatch
        assertVisibleElement(dura)
        dura.tap()
        for _ in 0..<4 { app.swipeUp() }
        assertVisibleElement(app.buttons["Also set this as what's on the bike"])
        capture(.groupsetMatchBikeOffer)

        launch("-shotRealGears")
        app.staticTexts["Chainrings"].tap()
        XCTAssertTrue(app.navigationBars["Chainrings"].waitForExistence(timeout: 2))
        capture(.chainringPicker)

        launch("-shotRealGears")
        app.staticTexts["Cassette"].tap()
        XCTAssertTrue(app.navigationBars["Cassette"].waitForExistence(timeout: 2))
        capture(.cassettePicker)

        launch("-shotSettingsUnsafeGears")
        app.staticTexts["Gears"].firstMatch.tap()
        assertVisibleElement(app.staticTexts["Too wide for the trainer"])
        capture(.gearPreviewTooWide)

        launch("-shotSettings")
        openParkedGear()
        assertVisible("screen.parkedGear")
        capture(.parkedGearCassette)
        app.buttons["Single sprocket"].tap()
        XCTAssertTrue(app.buttons["Single sprocket"].isSelected)
        capture(.parkedGearSingleSprocket)

        app.buttons["Cassette"].tap()
        let outOfReach = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Puts some gears out of reach")
        ).firstMatch
        assertVisibleElement(outOfReach)
        outOfReach.tap()
        assertVisibleElement(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Use ")
        ).firstMatch)
        capture(.parkedGearOutOfReach)
        assertJourneyCoverage()
    }

    func testUXCoverageHeadwindStates() {
        launch("-shotHeadwind")
        assertVisible("screen.headwind")
        assertVisibleElement(app.staticTexts["Fixed fan speed"])
        capture(.headwindManual)

        launch("-shotHeadwindAutomatic")
        assertVisibleElement(app.staticTexts["Sensor control"])
        capture(.headwindAutomatic)

        launch("-shotHeadwindPending")
        assertVisibleElement(app.staticTexts["Applying change…"])
        capture(.headwindPending)

        launch("-shotHeadwindError")
        assertVisibleElement(
            app.staticTexts["The Headwind did not confirm the change."]
        )
        capture(.headwindError)

        launch("-shotHeadwind", orientation: .landscapeLeft)
        waitForLandscapeLayout()
        assertVisible("screen.headwind")
        assertVisibleElement(app.buttons["50 percent"])
        capture(.headwindLandscape)
        assertJourneyCoverage()

    }

    func testUXCoverageAccessibilityAndAppearanceVariants() {
        launch("-shotSetupWizardAccessibility")
        XCTAssertTrue(
            app.navigationBars["Set up Virtual Gears"].waitForExistence(timeout: 2)
        )
        let confirmBike = app.buttons["wizard.useBikeSetup"]
        for _ in 0..<5 where !confirmBike.exists || !confirmBike.isHittable {
            app.swipeUp()
        }
        assertVisibleElement(confirmBike)
        capture(.wizardAccessibilityText)

        launch("-shotSettingsAccessibility")
        assertVisible("screen.settings")
        XCTAssertFalse(app.staticTexts["Run setup guide again"].exists)
        capture(.settingsAccessibilityText)

        launch("-shotRide", extraArguments: ["-AppleInterfaceStyle", "Dark"])
        assertVisible("screen.ride")
        assertVisibleElement(app.buttons["Shift harder"])
        capture(.rideDarkMode)

        launch("-shotHeadwind", extraArguments: ["-AppleInterfaceStyle", "Dark"])
        assertVisible("screen.headwind")
        assertVisibleElement(app.buttons["50 percent"])
        capture(.headwindDarkMode)
        assertJourneyCoverage()
    }

    func testUXCoverageDemoStates() {
        launch("-shotDemo")
        assertVisible("screen.demo")
        capture(.demoRide)

        app.buttons["Settings"].tap()
        assertVisible("screen.demo-settings")
        capture(.demoSettings)
        app.buttons["Done"].tap()

        let gearsMenu = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "gears")
        ).firstMatch
        gearsMenu.tap()
        let allGearSettings = app.buttons["All Gear Settings…"]
        assertVisibleElement(allGearSettings)
        allGearSettings.tap()
        assertVisible("screen.gears")
        capture(.demoGearSettings)
        app.buttons["Done"].tap()

        app.buttons["Fan"].tap()
        assertVisible("screen.demo-headwind")
        capture(.demoHeadwindAutomatic)
        app.buttons["Manual"].tap()
        assertVisibleElement(app.buttons["50 percent"])
        capture(.demoHeadwindManual)
        assertJourneyCoverage()
    }

    private func openSettingsDestination(_ title: String, fixture: String) {
        launch(fixture)
        assertVisible("screen.settings")
        let row = app.staticTexts[title].firstMatch
        for _ in 0..<3 where !row.exists || !row.isHittable {
            app.swipeUp()
        }
        assertVisibleElement(row)
        XCTAssertTrue(row.isHittable, "\(title) row is not tappable")
        row.tap()
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 2),
            "\(title) screen did not open"
        )
    }

    private func openParkedGear() {
        scrollToParkedGearRow()
        let row = app.descendants(matching: .any)["row.parkedGear"].firstMatch
        assertVisibleElement(row)
        row.tap()
    }

    private func scrollToParkedGearRow() {
        let row = app.descendants(matching: .any)["row.parkedGear"].firstMatch
        for _ in 0..<3 where !row.exists || !row.isHittable {
            app.swipeUp()
        }
        assertVisibleElement(row)
    }

    private func waitForLandscapeLayout() {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, window.frame.width <= window.frame.height {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
    }

    private func capture(_ state: DesignedUXState) {
        XCTAssertTrue(
            capturedUXStates.insert(state).inserted,
            "\(state.rawValue) was captured more than once in one journey."
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "UX-\(state.rawValue.replacingOccurrences(of: "/", with: "-"))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertJourneyCoverage() {
        guard let journey = Set(uxCoverageManifest.values).first(
            where: { name.contains($0) }
        ) else {
            return XCTFail("No UX coverage manifest entry matches \(name).")
        }
        let expected = Set(
            uxCoverageManifest.compactMap { state, assignedJourney in
                assignedJourney == journey ? state : nil
            }
        )
        XCTAssertEqual(
            capturedUXStates,
            expected,
            "\(journey) must execute every state assigned to it exactly once."
        )
    }

    private func launch(
        _ fixture: String,
        orientation: UIDeviceOrientation = .portrait,
        extraArguments: [String] = []
    ) {
        continueAfterFailure = false
        app = XCUIApplication()
        addTeardownBlock { @MainActor [weak self] in
            guard let self, let app = self.app else { return }
            if app.state == .runningForeground {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = self.name
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
            }
            app.terminate()
            self.app = nil
        }
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = [
            fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extraArguments
        app.launch()
    }

    func testStartupDoesNotRepeatTheChainPositionAfterSetup() {
        let reminderText = "Chain on 34 at the front and 15 at the back, and "
            + "leave it there."

        launch("-shotStarting")
        XCTAssertFalse(app.staticTexts[reminderText].exists)

        launch("-shotReady")
        XCTAssertFalse(app.staticTexts[reminderText].exists)

        launch("-shotFailed")
        XCTAssertFalse(app.staticTexts[reminderText].exists)
    }

    /// Samples the average colour of an element as it is actually rendered.
    /// Button styling (bordered vs borderedProminent, tint) is not exposed on
    /// the accessibility tree, so the only honest way to test "these two
    /// buttons must not look identical" is to look at the pixels.
    private func averageColor(of element: XCUIElement) -> (r: Double, g: Double, b: Double) {
        let screenshot = element.screenshot().image
        guard let cgImage = screenshot.cgImage else { return (0, 0, 0) }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              let data = cgImage.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        var totals = (r: 0.0, g: 0.0, b: 0.0)
        var samples = 0.0
        // Sample a sparse grid rather than every pixel: fast, and averages out
        // the icon/text drawn on top of the button's own fill colour.
        let strideStep = max(1, min(width, height) / 12)
        for y in stride(from: 0, to: height, by: strideStep) {
            for x in stride(from: 0, to: width, by: strideStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + 2 < CFDataGetLength(data) else { continue }
                totals.r += Double(pointer[offset])
                totals.g += Double(pointer[offset + 1])
                totals.b += Double(pointer[offset + 2])
                samples += 1
            }
        }
        guard samples > 0 else { return (0, 0, 0) }
        return (totals.r / samples / 255, totals.g / samples / 255, totals.b / samples / 255)
    }

    private func colorDistance(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double)
    ) -> Double {
        (pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2)).squareRoot()
    }

    private func assertStatusItems(
        _ identifiers: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var frames: [(String, CGRect)] = []
        for identifier in identifiers {
            assertVisible("status.\(identifier)", file: file, line: line)
            assertVisible(
                "status.\(identifier).icon",
                file: file,
                line: line
            )
            frames.append((
                identifier,
                app.descendants(matching: .any)["status.\(identifier)"].frame
            ))
        }
        for index in frames.indices {
            for otherIndex in frames.indices where otherIndex > index {
                let overlap = frames[index].1.intersection(frames[otherIndex].1)
                XCTAssertTrue(
                    overlap.isNull || overlap.width * overlap.height < 1,
                    "\(frames[index].0) overlaps \(frames[otherIndex].0)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertVisible(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertVisibleElement(
            app.descendants(matching: .any)[identifier],
            file: file,
            line: line
        )
    }

    private func assertVisibleElement(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 3),
            "\(element) does not exist",
            file: file,
            line: line
        )
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 1, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 1, file: file, line: line)
        let windowFrame = app.windows.firstMatch.frame
        let visibleFrame = frame.intersection(windowFrame)
        let visibleArea = visibleFrame.isNull ? 0 : visibleFrame.width * visibleFrame.height
        let totalArea = frame.width * frame.height
        XCTAssertGreaterThanOrEqual(
            visibleArea / totalArea,
            0.95,
            "\(element) is clipped or outside the visible window",
            file: file,
            line: line
        )
    }

    private func isFullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        let visibleFrame = frame.intersection(app.windows.firstMatch.frame)
        guard !visibleFrame.isNull else { return false }
        return visibleFrame.width * visibleFrame.height
            / (frame.width * frame.height) >= 0.95
    }

}
