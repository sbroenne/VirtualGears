import XCTest

@MainActor
final class VirtualGearsUITests: XCTestCase {
    private var app: XCUIApplication!

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

    func testStartupFailureExplainsConflictAndOffersRetry() {
        launch("-shotFailed")

        assertVisibleElement(app.staticTexts["Shifting could not start"])
        assertVisibleElement(
            app.staticTexts[
                "Your trainer would not hand over control. Something else may still be connected to it."
            ]
        )
        assertVisibleElement(app.buttons["Start Shifting"])
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

    func testSettingsNavigatesToEveryDestination() {
        launch("-shotSettings")

        assertVisible("screen.settings")
        for destination in ["Trainer", "Zwift Click", "Wahoo Headwind", "Gears"] {
            let row = app.staticTexts[destination].firstMatch
            assertVisibleElement(row)
            row.tap()
            XCTAssertTrue(
                app.navigationBars[destination].waitForExistence(timeout: 2),
                "\(destination) screen did not open"
            )
            app.navigationBars.buttons.firstMatch.tap()
        }
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

    private func launch(_ fixture: String) {
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
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = [
            fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
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
}
