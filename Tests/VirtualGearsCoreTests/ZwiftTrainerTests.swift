import Foundation
import XCTest
@testable import VirtualGearsCore

final class ZwiftTrainerCodecTests: XCTestCase {
    func testAdvertisementExposesZwiftServiceOnlyInAppControlledMode() {
        XCTAssertEqual(
            ShiftingMode.independent.advertisedTrainerServiceUUIDs,
            [FTMSUUID.fitnessMachineService, CyclingPowerUUID.service]
        )
        XCTAssertEqual(
            ShiftingMode.zwiftCompatible.advertisedTrainerServiceUUIDs,
            [FTMSUUID.fitnessMachineService, CyclingPowerUUID.service, ZwiftTrainerUUID.service]
        )
    }

    func testDeviceInformationIncludesObservedHubHandshakeField() throws {
        let envelope = try ZwiftProtobuf(Data(ZwiftTrainerResponse.information().data.dropFirst()))
        let content = try XCTUnwrap(envelope.message(2)?.message(1))
        XCTAssertEqual(content.fields[3], .bytes(Data("Virtual Gears".utf8)))
        XCTAssertNil(content.fields[6])
        XCTAssertEqual(content.fields[8], .bytes(Data([0x08, 0x01, 0x10, 0x14])))
    }

    func testKnownWireExamples() throws {
        XCTAssertEqual(try ZwiftTrainerRequest.decode(Data("RideOn".utf8) + Data([2])), .rideOn)
        XCTAssertEqual(try ZwiftTrainerRequest.decode(Data("RideOn".utf8) + Data([2, 4])), .rideOn)
        XCTAssertThrowsError(try ZwiftTrainerRequest.decode(Data("RideOn".utf8) + Data([2, 4, 4])))
        XCTAssertEqual(try ZwiftTrainerRequest.decode(Data([0x41, 8, 5])), .deviceInformation)
        XCTAssertEqual(try ZwiftTrainerRequest.decode(Data([0, 8, 0x88, 4])), .query(520))
        for (bytes, ratio) in [
            ([UInt8(0xCC), 0x3A], UInt32(7500)),
            ([0xC0, 0xBB, 1], 24000),
            ([0xF3, 0xAC, 3], 54899),
        ] {
            let message = Data([4, 0x2A, UInt8(bytes.count + 1), 0x10] + bytes)
            XCTAssertEqual(try ZwiftTrainerRequest.decode(message), .command(.init(ratioX10000: ratio)))
            XCTAssertEqual(
                ZwiftTrainerResponse.ratio(ratio).data,
                Data([0x3C, 8, 0x88, 4, 0x12, UInt8(bytes.count + 3), 0x0A, UInt8(bytes.count + 1), 0x40] + bytes)
            )
        }
        XCTAssertEqual(ZwiftTrainerResponse.rideOn.data, Data("RideOn".utf8) + Data([2, 0]))
    }

    func testRoundTripsIncludingCombinedCommandsAndSignedValues() throws {
        let simulation = ZwiftSimulation(
            windHundredths: -125, inclineHundredths: -1200,
            aerodynamicTenThousandths: 5100, rollingHundredThousandths: 400
        )
        let requests: [ZwiftTrainerRequest] = [
            .rideOn, .deviceInformation, .query(0), .query(520),
            .command(.init(powerTarget: 0)),
            .command(.init(ratioX10000: 54900, simulation: simulation, powerTarget: 250)),
            .command(.init(simulation: .init())),
            .command(.init(simulation: .init(windHundredths: .min, inclineHundredths: .max))),
        ]
        for request in requests {
            XCTAssertEqual(try ZwiftTrainerRequest.decode(request.encode()), request)
        }
        let ftms = try simulation.ftmsParameters()
        XCTAssertEqual(ftms.windSpeedThousandthsMetersPerSecond, -1250)
        XCTAssertEqual(ftms.gradeHundredthsPercent, -1200)
        XCTAssertEqual(ftms.windResistanceCoefficientHundredthsKilogramsPerMeter, 51)
        XCTAssertEqual(ftms.rollingResistanceCoefficientTenThousandths, 40)
    }

    func testSimulationMergesPartialUpdatesAndRejectsUnrepresentableValues() throws {
        let merged = ZwiftSimulation(
            windHundredths: 20, inclineHundredths: 100,
            aerodynamicTenThousandths: 6000, rollingHundredThousandths: 500
        ).merging(.init(inclineHundredths: -500))
        let parameters = try merged.ftmsParameters()
        XCTAssertEqual(parameters.gradeHundredthsPercent, -500)
        XCTAssertEqual(parameters.windSpeedThousandthsMetersPerSecond, 200)
        XCTAssertEqual(parameters.windResistanceCoefficientHundredthsKilogramsPerMeter, 60)
        XCTAssertEqual(parameters.rollingResistanceCoefficientTenThousandths, 50)
        XCTAssertEqual(try ZwiftSimulation().ftmsParameters().gradeHundredthsPercent, 0)
        for sim in [
            ZwiftSimulation(windHundredths: .max),
            .init(inclineHundredths: .min),
            .init(aerodynamicTenThousandths: .max),
            .init(rollingHundredThousandths: .max),
        ] {
            XCTAssertThrowsError(try sim.ftmsParameters())
        }
    }

    func testMalformedAndUnsupportedMessagesCannotTrap() {
        let messages: [[UInt8]] = [
            [], [4], [4, 0], [4, 0x80], [4, 0x2A, 10, 0x10, 1],
            [4, 0x2A, 2, 0x10, 0], [4, 0x2A, 2, 0x10, 0x80],
            [4, 0x28, 1], [4, 0x1A, 0], [4, 0x0B],
            [4, 0x09, 1], [4, 0x0D, 1],
            [0x41, 8, 6], [0x41], [0xFF, 8, 1],
            [4, 0x18] + Array(repeating: 0xFF, count: 11),
            [4, 0x2A, 6, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F],
        ]
        for bytes in messages {
            XCTAssertThrowsError(try ZwiftTrainerRequest.decode(Data(bytes)), "\(bytes)")
        }
        XCTAssertThrowsError(try ZwiftTrainerRequest.decode(Data(repeating: 4, count: 514)))
    }

    func testUnknownFieldsAndVarintBoundaries() throws {
        let unknownFixedFields = Data([0x49]) + Data(repeating: 0, count: 8)
            + Data([0x55]) + Data(repeating: 0, count: 4)
        XCTAssertEqual(
            try ZwiftTrainerRequest.decode(Data([0, 8, 1]) + unknownFixedFields), .query(1)
        )
        let protobuf = try ZwiftProtobuf(ZwiftProtobuf.bytes(9, Data([1, 2])))
        XCTAssertThrowsError(try protobuf.integer(9))
        XCTAssertNil(try protobuf.message(10))
        for value: UInt64 in [0, 127, 128, UInt64(UInt32.max), .max] {
            let wire = Data([8]) + ZwiftProtobuf.varint(value)
            let parsed = try ZwiftProtobuf(wire)
            XCTAssertEqual(parsed.fields[1], .integer(value))
        }
        XCTAssertThrowsError(try ZwiftProtobuf(Data([8]) + ZwiftProtobuf.varint(.max)).integer(1))
        XCTAssertThrowsError(try ZwiftProtobuf(Data([8]) + Data(repeating: 0x80, count: 10)))
    }

    func testTelemetryUsesRealTrainerReadings() throws {
        let data = ZwiftTrainerResponse.ridingData(.init(
            instantaneousSpeedHundredths: 3245, instantaneousCadenceHalfRPM: 181,
            instantaneousPowerWatts: 237, heartRateBPM: 145
        ))
        XCTAssertEqual(data.first, 3)
        let decoded = try ZwiftProtobuf(Data(data.dropFirst()))
        XCTAssertEqual(try decoded.integer(1), 237)
        XCTAssertEqual(try decoded.integer(2), 90)
        XCTAssertEqual(try decoded.integer(3), 3245)
        XCTAssertEqual(try decoded.integer(4), 145)
        let sparse = ZwiftTrainerResponse.ridingData(.init(instantaneousSpeedHundredths: nil))
        XCTAssertEqual(sparse, Data([3]))
        let negative = ZwiftTrainerResponse.ridingData(.init(
            instantaneousSpeedHundredths: nil, instantaneousPowerWatts: -1
        ))
        XCTAssertEqual(try ZwiftProtobuf(Data(negative.dropFirst())).integer(1), 0)
        let info = try ZwiftProtobuf(Data(ZwiftTrainerResponse.information().data.dropFirst()))
        XCTAssertEqual(try info.integer(1), 0)
        let content = try XCTUnwrap(info.message(2)?.message(1))
        XCTAssertEqual(content.fields[3], .bytes(Data("Virtual Gears".utf8)))
    }

    func testConfigurationMigrationAndModeSpecificGearing() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: Data("{}".utf8)).shiftingMode, .independent)
        XCTAssertEqual(try JSONDecoder().decode(
            AppConfiguration.self, from: Data(#"{"shiftingMode":"future"}"#.utf8)
        ).shiftingMode, .independent)
        var configuration = AppConfiguration()
        configuration.rememberClick(named: "Click", id: UUID())
        XCTAssertTrue(configuration.connectsClick)
        configuration.shiftingMode = .zwiftCompatible
        configuration.parkInSuggestion()
        XCTAssertFalse(configuration.connectsClick)
        XCTAssertTrue(configuration.usesClick)
        XCTAssertTrue(configuration.hasSafeCircumference)
        XCTAssertFalse(configuration.parkedGearPutsGearsOutOfReach)
        XCTAssertEqual(configuration.drivetrainName, ShiftingMode.zwiftCompatible.name)
        XCTAssertTrue(configuration.gearSummary.contains("riding app"))
        XCTAssertTrue(configuration.setupDescription.contains("Start Shifting"))
        configuration.usesVirtualGears = true
        configuration.gearLadderID = GearLadderCatalog.customLadderID
        configuration.customLadder = .init(gearCount: 24, easiestRatioHundredths: 24, hardestRatioHundredths: 1000)
        XCTAssertTrue(configuration.hasSafeGearing)
        configuration.park(in: ParkedGear(chainringTeeth: 34, cogTeeth: 34)!)
        XCTAssertTrue(configuration.parkedGearPutsGearsOutOfReach)
        XCTAssertFalse(configuration.hasSafeCircumference)
        XCTAssertNotNil(configuration.parkedGearWarning)
        let decoded = try JSONDecoder().decode(
            AppConfiguration.self, from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(decoded.shiftingMode, .zwiftCompatible)
        for mode in ShiftingMode.allCases {
            XCTAssertFalse(mode.name.isEmpty)
            XCTAssertFalse(mode.explanation.isEmpty)
        }
    }

    func testRatioScalingClampingRoundingAndInvalidInputs() throws {
        let setting = try AppRatioSetting(ratio: 3, neutralMillimeters: 2105, parkedRatio: 2)
        XCTAssertEqual(setting.circumferenceMillimeters, 3157.5)
        XCTAssertEqual(setting.appliedRatio, 3)
        XCTAssertEqual(setting.encodedRatio, 30000)
        XCTAssertFalse(setting.wasClamped)
        for ratio in [0.0001, 1000.0, Double.greatestFiniteMagnitude] {
            let limited = try AppRatioSetting(ratio: ratio, neutralMillimeters: 2400, parkedRatio: 2.4)
            XCTAssertTrue(limited.wasClamped)
            XCTAssertLessThanOrEqual(limited.circumferenceMillimeters, WahooKickrCommand.maximumCircumferenceMillimeters)
            XCTAssertGreaterThanOrEqual(limited.circumferenceMillimeters, 2400 * TrainerSafety.supportedScaleRange.lowerBound)
        }
        for ratio in [0, -1, .infinity, .nan] {
            XCTAssertThrowsError(try AppRatioSetting(ratio: ratio, neutralMillimeters: 2105, parkedRatio: 2))
        }
        XCTAssertThrowsError(try AppRatioSetting(ratio: 2, neutralMillimeters: 0, parkedRatio: 2))
        XCTAssertThrowsError(try AppRatioSetting(ratio: 2, neutralMillimeters: .nan, parkedRatio: 2))
        XCTAssertThrowsError(try AppRatioSetting(ratio: 2, neutralMillimeters: 2105, parkedRatio: 0))
    }
}

@MainActor
final class ZwiftTrainerCoordinatorTests: XCTestCase {
    private var trainer: FakeTrainer!
    private var link: FakeRidingAppLink!
    private var click: FakeShifter!
    private var coordinator: ProxyCoordinator!
    private var configuration: AppConfiguration!
    private var defaults: UserDefaults!
    private var suite: String!
    private let appID = UUID()

    override func setUp() async throws {
        trainer = FakeTrainer()
        link = FakeRidingAppLink()
        click = FakeShifter()
        suite = "ZwiftTrainerTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        configuration = AppConfiguration()
        configuration.shiftingMode = .zwiftCompatible
        configuration.rememberKickr(named: "KICKR", id: trainer.selectedID!)
        configuration.rememberClick(named: "Click", id: UUID())
        configuration.parkInSuggestion()
        coordinator = ProxyCoordinator(
            kickr: trainer, click: click, peripheral: link, screen: FakeScreen(),
            defaults: defaults, configuration: configuration
        )
        coordinator.makeTrainerProxyAvailable()
    }

    override func tearDown() async throws {
        await coordinator.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }

    private func start() async throws {
        coordinator.startShifting(configuration: configuration)
        try await settle { self.coordinator.state == .active }
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ProductBluetoothError.unavailable("Test did not settle")
    }

    private func ratio(_ value: UInt32) async -> [ZwiftTrainerResponse] {
        await link.sendZwift(.command(.init(ratioX10000: value)), from: appID)
    }

    func testStartRemainsRequiredAndStopKeepsRidingAppConnected() async throws {
        XCTAssertTrue(click.didDisconnect)
        let history = trainer.wheelSizeHistory
        let beforeStart = await ratio(30000)
        XCTAssertEqual(trainer.wheelSizeHistory, history)
        XCTAssertEqual(coordinator.requestedAppRatio, 3)
        XCTAssertNil(coordinator.confirmedAppRatio)
        XCTAssertEqual(beforeStart, [.ratio(UInt32((configuration.parkedGear!.ratio * 10000).rounded()))])
        try await start()
        XCTAssertEqual(coordinator.confirmedAppRatio ?? 0, 3, accuracy: 0.001)
        XCTAssertNotNil(defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"))
        XCTAssertFalse(coordinator.canShiftEasier)
        XCTAssertFalse(coordinator.canShiftHarder)
        let previous = trainer.wheelSizeHistory
        coordinator.shift(.harder)
        click.press(.single(.easier))
        coordinator.beginHold(.harder)
        coordinator.endHold()
        XCTAssertEqual(trainer.wheelSizeHistory, previous)
        let stops = link.advertisingStopCount
        await coordinator.stopShifting()
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
        XCTAssertTrue(link.isAdvertising)
        XCTAssertEqual(link.advertisingStopCount, stops)
        XCTAssertNil(coordinator.confirmedAppRatio)
        XCTAssertNil(defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"))
        _ = await ratio(20000)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
        try await start()
        XCTAssertEqual(coordinator.confirmedAppRatio ?? 0, 2, accuracy: 0.001)
    }

    func testNoRatioAtStartWaitsWithoutInventingAGear() async throws {
        try await start()
        XCTAssertNil(coordinator.confirmedAppRatio)
        XCTAssertNil(coordinator.displayedGear)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
        let responses = await ratio(24000)
        XCTAssertEqual(responses, [.ratio(UInt32((coordinator.confirmedAppRatio! * 10000).rounded()))])
    }

    func testFailedRatioDoesNotReportSuccessOrChangeConfirmedState() async throws {
        try await start()
        _ = await ratio(24000)
        let previous = coordinator.confirmedAppRatio
        let wheel = trainer.currentWheelSizeMillimeters
        trainer.failNextWahooCommand = true
        let responses = await ratio(30000)
        XCTAssertTrue(responses.isEmpty)
        XCTAssertEqual(coordinator.confirmedAppRatio, previous)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, wheel)
        let query = await link.sendZwift(.query(520), from: appID)
        XCTAssertEqual(query, [.ratio(UInt32((previous! * 10000).rounded()))])
    }

    func testStopWaitsForAnInFlightRatioAndRestoresNormalWheelSize() async throws {
        try await start()
        trainer.wahooConfirmationDelay = .milliseconds(80)
        let count = trainer.wahooCommandCount
        let command = Task { await self.ratio(30000) }
        try await settle { self.trainer.wahooCommandCount > count }
        await coordinator.stopShifting()
        _ = await command.value
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
        XCTAssertNil(defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"))
    }

    func testFailedStopKeepsReportingTheRatioTheTrainerMayStillHold() async throws {
        try await start()
        _ = await ratio(30000)
        let held = UInt32((coordinator.confirmedAppRatio! * 10000).rounded())
        trainer.failNextWahooCommand = true
        await coordinator.stopShifting()
        XCTAssertNotNil(defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"))
        let query = await link.sendZwift(.query(520), from: appID)
        XCTAssertEqual(query, [.ratio(held)])
        let staged = await ratio(20000)
        XCTAssertEqual(staged, [.ratio(held)])
        try await start()
        XCTAssertEqual(coordinator.confirmedAppRatio ?? 0, 2, accuracy: 0.001)
        await coordinator.stopShifting()
        let parked = await link.sendZwift(.query(520), from: appID)
        XCTAssertEqual(parked, [.ratio(UInt32((configuration.parkedGear!.ratio * 10000).rounded()))])
    }

    func testOutOfRangeRidingAppWheelSizeIsNotUsedAsTheBaseline() async throws {
        let result = await link.send(.setWheelCircumference(tenthsOfMillimeter: 30000), from: appID)
        XCTAssertEqual(result?.result, .success)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 3000)
        try await start()
        XCTAssertEqual(coordinator.wheelSizeGearsAreBuiltAround, 2105)
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
    }

    func testSimulationWorksBeforeStartAndERGIsRefused() async throws {
        let first = ZwiftSimulation(
            windHundredths: -100, inclineHundredths: -550,
            aerodynamicTenThousandths: 6000, rollingHundredThousandths: 500
        )
        _ = await link.sendZwift(.command(.init(simulation: first, powerTarget: 250)), from: appID)
        XCTAssertFalse(trainer.ftmsRequests.contains(.setTargetPower(watts: 250)))
        XCTAssertTrue(trainer.ftmsRequests.contains(.setIndoorBikeSimulationParameters(try first.ftmsParameters())))
        _ = await link.sendZwift(.command(.init(simulation: .init(inclineHundredths: 200))), from: appID)
        XCTAssertTrue(trainer.ftmsRequests.contains(.setIndoorBikeSimulationParameters(
            try first.merging(.init(inclineHundredths: 200)).ftmsParameters()
        )))
        let result = await link.send(.setTargetPower(watts: 300), from: appID)
        XCTAssertEqual(result?.result, .opcodeNotSupported)
        let count = trainer.ftmsRequests.count
        let ergOnly = await link.sendZwift(.command(.init(powerTarget: 200)), from: appID)
        XCTAssertTrue(ergOnly.isEmpty)
        XCTAssertEqual(trainer.ftmsRequests.count, count)
        XCTAssertFalse(trainer.ftmsRequests.contains { if case .setTargetPower = $0 { true } else { false } })
    }

    func testWheelSizeChangeRebasesAppRatioAndResetTarget() async throws {
        try await start()
        _ = await ratio(30000)
        let result = await link.send(.setWheelCircumference(tenthsOfMillimeter: 23000), from: appID)
        XCTAssertEqual(result?.result, .success)
        XCTAssertEqual(coordinator.confirmedAppRatio ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(coordinator.wheelSizeGearsAreBuiltAround, 2300)
        XCTAssertEqual(defaults.double(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"), 2300)
        let invalid = await link.send(.setWheelCircumference(tenthsOfMillimeter: 50000), from: appID)
        XCTAssertEqual(invalid?.result, .invalidParameter)
        await coordinator.stopShifting()
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2300)
    }

    func testClampedRatioReportsActualSetting() async throws {
        try await start()
        let responses = await ratio(UInt32.max)
        XCTAssertLessThan(coordinator.confirmedAppRatio!, Double(UInt32.max) / 10000)
        XCTAssertEqual(responses, [.ratio(UInt32((coordinator.confirmedAppRatio! * 10000).rounded()))])
    }

    func testHandshakeInformationQueriesAndExpiredSubscriptions() async {
        let handshake = await link.sendZwift(.rideOn, from: appID)
        XCTAssertEqual(handshake, [.rideOn])
        let info = await link.sendZwift(.deviceInformation, from: appID)
        XCTAssertEqual(info, [.information()])
        let query = await link.sendZwift(.query(0), from: appID)
        XCTAssertEqual(query, info)
        let unsupported = await link.sendZwift(.query(900), from: appID)
        XCTAssertTrue(unsupported.isEmpty)
        let expired = await coordinator.peripheral.zwiftCommandHandler?(
            .command(.init(ratioX10000: 30000)),
            .init(centralID: appID, subscriptionID: UUID())
        )
        XCTAssertEqual(expired, [])
    }

    func testModeChangesAreRefusedUntilStopAndRepublishServices() async throws {
        try await start()
        var independent = configuration!
        independent.shiftingMode = .independent
        XCTAssertFalse(coordinator.configureShifting(independent))
        let changed = await coordinator.changeDrivetrain(independent)
        XCTAssertFalse(changed)
        await coordinator.stopShifting()
        XCTAssertTrue(coordinator.configureShifting(independent))
        XCTAssertEqual(link.shiftingMode, .independent)
        let erg = await link.send(.setTargetPower(watts: 250), from: appID)
        XCTAssertEqual(erg?.result, .opcodeNotSupported)
        let zwift = await ratio(30000)
        XCTAssertTrue(zwift.isEmpty)
    }

    func testRecoveryReappliesLastConfirmedAppRatio() async throws {
        try await start()
        _ = await ratio(30000)
        let wheel = trainer.currentWheelSizeMillimeters
        trainer.eventHandler?(.status(.controlPermissionLost))
        try await settle { self.coordinator.state == .active }
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, wheel)
        XCTAssertEqual(coordinator.confirmedAppRatio ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(link.controlLostNotificationCount, 0)
    }

    func testFailedStartResetsAndCanBeRetried() async throws {
        _ = await ratio(30000)
        trainer.failNextWahooCommand = true
        coordinator.startShifting(configuration: configuration)
        try await settle { self.coordinator.failure != nil }
        XCTAssertEqual(trainer.currentWheelSizeMillimeters, 2105)
        XCTAssertNil(coordinator.confirmedAppRatio)
        XCTAssertNil(defaults.object(forKey: "VirtualGears.unfinishedRideBaselineMillimeters"))
    }
}
