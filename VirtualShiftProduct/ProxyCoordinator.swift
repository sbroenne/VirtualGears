import Foundation
import Observation
import UIKit
import VirtualShiftCore

enum ProxySessionState: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Ready to ride"
        case .connecting: "Connecting equipment…"
        case .active: "Ride active"
        case .reconnecting: "KICKR reconnecting · control lost"
        case .stopping: "Stopping ride…"
        case let .failed(message): "Ride error: \(message)"
        }
    }
}

enum ShiftFeedbackKind: Equatable {
    case single
    case multiple
}

@MainActor
@Observable
final class ProxyCoordinator {
    private(set) var state: ProxySessionState = .idle
    private(set) var displayedGear: VirtualGear?
    private(set) var confirmedGearIndex: Int?
    private(set) var gearSequence: [VirtualGear] = []
    private(set) var shiftConfirmation = 0
    private(set) var shiftInteraction = 0
    private(set) var lastShiftFeedback: ShiftFeedbackKind = .single
    private(set) var sessionBaselineMillimeters: Double?

    let peripheral: FTMSPeripheral
    private let kickr: KickrCentralService
    private let click: ClickCentralService
    private let diagnostics: ProductDiagnosticsStore
    private var gearEngine: ConfirmedGearEngine?
    private var shiftTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var usesClick = false
    private var pendingFeedback: [ShiftFeedbackKind] = []
    private var baselineUpdateInProgress = false

    var isRidePresented: Bool {
        switch state {
        case .connecting, .active, .reconnecting, .stopping: true
        case .idle, .failed: false
        }
    }

    var canShiftEasier: Bool {
        state == .active && (confirmedGearIndex ?? 0) > 0
    }

    var canShiftHarder: Bool {
        state == .active
            && (confirmedGearIndex ?? Int.max) < gearSequence.count - 1
    }

    init(
        kickr: KickrCentralService,
        click: ClickCentralService,
        diagnostics: ProductDiagnosticsStore
    ) {
        self.kickr = kickr
        self.click = click
        self.diagnostics = diagnostics
        peripheral = FTMSPeripheral(diagnostics: diagnostics)

        peripheral.commandHandler = { [weak self] request, centralID in
            guard let self else {
                return .init(result: .operationFailed, status: nil)
            }
            return await self.handle(request, from: centralID)
        }
        kickr.eventHandler = { [weak self] event in
            self?.handleKickrEvent(event)
        }
        kickr.stateHandler = { [weak self] connectionState in
            self?.handleKickrState(connectionState)
        }
        click.shiftHandler = { [weak self] request in
            self?.handleShiftRequest(request)
        }
    }

    /// Starts a ride immediately so the UI can switch to the ride screen in the
    /// same update. The state transition is synchronous, so a second tap is
    /// rejected by the same guard that protected the previous async entry point.
    func startRide(configuration: AppConfiguration) {
        guard state == .idle || isFailed else { return }
        guard configuration.setupComplete,
              configuration.canFinishSetup,
              kickr.selectedID?.uuidString == configuration.kickrUUID,
              !configuration.usesClick
                || click.selectedID?.uuidString == configuration.clickUUID else {
            state = .failed("Setup is incomplete")
            return
        }
        let id = UUID()
        sessionID = id
        usesClick = configuration.usesClick
        state = .connecting
        Task { await runRide(configuration: configuration, sessionID: id) }
    }

    private func runRide(
        configuration: AppConfiguration,
        sessionID id: UUID
    ) async {
        do {
            gearEngine = try ConfirmedGearEngine(
                drivetrain: configuration.drivetrainPreset.drivetrain,
                baselineCircumferenceMillimeters:
                    Double(configuration.neutralCircumferenceMillimeters)
            )
            gearSequence = configuration.drivetrainPreset.drivetrain.gears
            updateDisplayedGear()
            sessionBaselineMillimeters =
                Double(configuration.neutralCircumferenceMillimeters)

            kickr.resumeSavedConnection()
            if usesClick { click.resumeSavedConnection() }
            try await waitUntilReady(kickr, named: "KICKR", sessionID: id)
            let response = try await kickr.execute(.requestControl)
            guard response.result == .success else {
                throw ProductBluetoothError.commandFailed(
                    "KICKR denied FTMS control"
                )
            }
            guard let initialCommand = gearEngine?.confirmedSetting.command else {
                throw ProductBluetoothError.commandFailed(
                    "Initial virtual gear is unavailable"
                )
            }
            let initialResponse = try await kickr.executeWahoo(initialCommand)
            guard initialResponse.confirmsSuccess(for: initialCommand) else {
                throw ProductBluetoothError.commandFailed(
                    "KICKR did not confirm the initial virtual gear"
                )
            }
            guard sessionID == id else { return }
            peripheral.startAdvertising()
            try await waitUntilPeripheralReady(sessionID: id)
            UIApplication.shared.isIdleTimerDisabled = true
            state = .active
            log("Ride session started")
        } catch {
            guard sessionID == id else { return }
            await abortStart(error)
        }
    }

    func stopRide() async {
        guard let id = sessionID, state != .stopping else { return }
        state = .stopping
        peripheral.stopAcceptingCommands()
        shiftTask?.cancel()
        recoveryTask?.cancel()
        var failures: [String] = []

        if !kickr.isReady {
            do {
                try await waitUntilKickrReadyForStop(sessionID: id)
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        if kickr.isReady, !kickr.hasFTMSControl {
            do {
                let response = try await kickr.execute(.requestControl)
                guard response.result == .success else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR denied control during safe stop"
                    )
                }
            } catch {
                failures.append(
                    "Trainer control could not be recovered: \(error.localizedDescription)"
                )
            }
        }

        if kickr.isReady, kickr.hasFTMSControl {
            do {
                let response = try await kickr.execute(.stopOrPause(.stop))
                guard response.result == .success else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR rejected Stop"
                    )
                }
            } catch {
                failures.append("Trainer stop failed: \(error.localizedDescription)")
            }
        } else {
            failures.append("Trainer stop could not be confirmed")
        }

        if let baseline = sessionBaselineMillimeters, kickr.isReady {
            do {
                let command = try WahooKickrCommand.setWheelCircumference(
                    millimeters: baseline
                )
                let response = try await kickr.executeWahoo(command)
                guard response.confirmsSuccess(for: command) else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR did not confirm baseline restoration"
                    )
                }
            } catch {
                failures.append(
                    "Baseline restoration failed: \(error.localizedDescription)"
                )
            }
        } else {
            failures.append("Trainer starting state could not be restored")
        }

        peripheral.stopAdvertising()
        click.disconnect()
        kickr.disconnect()
        UIApplication.shared.isIdleTimerDisabled = false
        sessionID = nil
        gearEngine = nil
        displayedGear = nil
        confirmedGearIndex = nil
        gearSequence = []
        pendingFeedback = []
        sessionBaselineMillimeters = nil
        if failures.isEmpty {
            state = .idle
            log("Ride session stopped")
        } else {
            failures.forEach { log($0, .error) }
            state = .failed(failures.joined(separator: ". "))
        }
    }

    func shift(_ direction: ShiftDirection) {
        handleShiftRequest(.single(direction))
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func waitUntilReady(
        _ service: KickrCentralService,
        named name: String,
        sessionID: UUID
    ) async throws {
        for _ in 0..<300 {
            guard self.sessionID == sessionID else { throw CancellationError() }
            if service.isReady { return }
            if case let .failed(message) = service.state {
                throw ProductBluetoothError.unavailable("\(name): \(message)")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProductBluetoothError.unavailable("\(name) did not become ready")
    }

    private func waitUntilPeripheralReady(sessionID: UUID) async throws {
        for _ in 0..<100 {
            guard self.sessionID == sessionID else { throw CancellationError() }
            if peripheral.isAdvertising { return }
            if case let .failed(message) = peripheral.latestEvent {
                throw ProductBluetoothError.unavailable("Riding app link: \(message)")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProductBluetoothError.unavailable(
            "The riding app link did not start advertising"
        )
    }

    private func waitUntilKickrReadyForStop(sessionID: UUID) async throws {
        for _ in 0..<100 {
            guard self.sessionID == sessionID else { throw CancellationError() }
            if kickr.isReady { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProductBluetoothError.unavailable(
            "KICKR did not reconnect in time for safe stop"
        )
    }

    private func waitUntilReady(
        _ service: ClickCentralService,
        named name: String,
        sessionID: UUID
    ) async throws {
        for _ in 0..<300 {
            guard self.sessionID == sessionID else { throw CancellationError() }
            if service.isReady { return }
            if case let .failed(message) = service.state {
                throw ProductBluetoothError.unavailable("\(name): \(message)")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProductBluetoothError.unavailable("\(name) did not become ready")
    }

    private func handle(
        _ request: FitnessMachineControlPointRequest,
        from centralID: UUID
    ) async -> FTMSPeripheralCommandResult {
        guard state == .active, kickr.isReady else {
            return .init(result: .operationFailed, status: nil)
        }
        guard VirtualTrainerFTMSProfile.supports(request) else {
            log("Rejected unsupported ERG target-power command", .warning)
            return .init(result: .opcodeNotSupported, status: nil)
        }
        do {
            if case let .setWheelCircumference(tenths) = request {
                return try await setBaseline(
                    millimeters: Double(tenths) / 10
                )
            }
            let response = try await kickr.execute(request)
            guard response.requestOpcode == request.opcode,
                  response.result == .success else {
                return .init(result: response.result, status: nil)
            }
            return .success(status: status(for: request))
        } catch {
            log(
                "Riding app command 0x\(String(format: "%02X", request.opcode)) "
                    + "failed: \(error.localizedDescription)",
                .error
            )
            return .init(result: .operationFailed, status: nil)
        }
    }

    private func setBaseline(
        millimeters: Double
    ) async throws -> FTMSPeripheralCommandResult {
        baselineUpdateInProgress = true
        defer { baselineUpdateInProgress = false }
        while shiftTask != nil {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let engine = gearEngine else {
            throw ProductBluetoothError.commandFailed(
                "Gear engine is unavailable"
            )
        }
        let rebased = try engine.rebased(
            baselineCircumferenceMillimeters: millimeters
        )
        let effectiveCommand = rebased.confirmedSetting.command
        let effectiveResponse = try await kickr.executeWahoo(effectiveCommand)
        guard effectiveResponse.confirmsSuccess(for: effectiveCommand) else {
            throw ProductBluetoothError.commandFailed(
                "KICKR did not confirm rescaled gear"
            )
        }
        sessionBaselineMillimeters = millimeters
        gearEngine = rebased
        updateDisplayedGear()
        return .success(status: .wheelCircumferenceChanged(
            tenthsOfMillimeter: UInt16((millimeters * 10).rounded())
        ))
    }

    private func handleKickrEvent(_ event: KickrEvent) {
        guard sessionID != nil else { return }
        if case let .rawBikeData(data) = event {
            peripheral.relayIndoorBikeData(data)
        } else if event == .status(.controlPermissionLost) {
            beginRecovery()
        }
    }

    private func handleKickrState(_ connectionState: ProductConnectionState) {
        guard sessionID != nil else { return }
        guard state == .active || state == .reconnecting else { return }
        if connectionState != .ready {
            beginRecovery(startImmediately: false)
            return
        }
        guard state == .reconnecting, recoveryTask == nil else { return }
        let id = sessionID
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.kickr.execute(.requestControl)
                guard !Task.isCancelled,
                      self.state == .reconnecting,
                      response.result == .success,
                      let command = self.gearEngine?.confirmedSetting.command else {
                    throw ProductBluetoothError.commandFailed(
                        "Could not reacquire KICKR control"
                    )
                }
                let wahoo = try await self.kickr.executeWahoo(command)
                guard !Task.isCancelled,
                      self.state == .reconnecting,
                      wahoo.confirmsSuccess(for: command),
                      self.sessionID == id else {
                    throw ProductBluetoothError.commandFailed(
                        "Could not restore current virtual gear"
                    )
                }
                self.state = .active
                self.recoveryTask = nil
            } catch {
                guard self.sessionID == id, self.state == .reconnecting else {
                    self.recoveryTask = nil
                    return
                }
                self.state = .reconnecting
                self.log("KICKR recovery failed: \(error.localizedDescription)", .error)
                self.recoveryTask = nil
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard self.sessionID == id,
                      self.state == .reconnecting,
                      self.kickr.isReady else { return }
                self.handleKickrState(.ready)
            }
        }
    }

    private func beginRecovery(startImmediately: Bool = true) {
        guard sessionID != nil else { return }
        state = .reconnecting
        peripheral.notifyControlLost()
        shiftTask?.cancel()
        gearEngine?.cancelPendingChanges()
        pendingFeedback.removeAll()
        updateDisplayedGear()
        if startImmediately, kickr.isReady {
            handleKickrState(.ready)
        }
    }

    private func handleShiftRequest(_ request: ShiftRequest) {
        guard state == .active, !baselineUpdateInProgress else { return }
        shiftInteraction &+= 1
        let direction: ShiftDirection
        let feedback: ShiftFeedbackKind
        switch request {
        case let .single(value):
            direction = value
            feedback = .single
        case let .multiple(value):
            direction = value
            feedback = .multiple
        }
        guard var engine = gearEngine else { return }
        let oldRequested = engine.requestedIndex
        let oldConfirmed = engine.confirmedIndex
        let change = engine.requestShift(by: direction == .harder ? 1 : -1)
        gearEngine = engine
        if engine.requestedIndex == oldRequested {
            log("Ignored shift at drivetrain boundary")
            return
        }
        pendingFeedback.append(feedback)
        if let change {
            guard shiftTask == nil else { return }
            startShift(change)
        } else if engine.confirmedIndex != oldConfirmed {
            updateDisplayedGear()
            confirmShift(from: oldConfirmed, to: engine.confirmedIndex)
        }
    }

    private func startShift(_ initial: PendingGearChange) {
        shiftTask = Task { [weak self] in
            guard let self else { return }
            var change: PendingGearChange? = initial
            while let current = change, !Task.isCancelled {
                do {
                    let response = try await self.kickr.executeWahoo(current.command)
                    guard response.confirmsSuccess(for: current.command),
                          var engine = self.gearEngine else {
                        throw ProductBluetoothError.commandFailed(
                            "KICKR did not confirm virtual shift"
                        )
                    }
                    let oldIndex = engine.confirmedIndex
                    change = engine.acknowledge(response)
                    self.gearEngine = engine
                    self.updateDisplayedGear()
                    self.confirmShift(from: oldIndex, to: engine.confirmedIndex)
                } catch {
                    self.gearEngine?.cancelPendingChanges()
                    self.pendingFeedback.removeAll()
                    self.updateDisplayedGear()
                    self.log("Virtual shift failed: \(error.localizedDescription)", .error)
                    break
                }
            }
            self.shiftTask = nil
        }
    }

    private func status(
        for request: FitnessMachineControlPointRequest
    ) -> FitnessMachineStatus? {
        switch request {
        case .requestControl: nil
        case .reset: .reset
        case let .setTargetResistanceLevel(value):
            .targetResistanceLevelChanged(tenths: value)
        case .setTargetPower: nil
        case .startOrResume: .startedOrResumed
        case let .stopOrPause(value): .stoppedOrPaused(value)
        case let .setIndoorBikeSimulationParameters(value):
            .indoorBikeSimulationParametersChanged(value)
        case let .setWheelCircumference(value):
            .wheelCircumferenceChanged(tenthsOfMillimeter: value)
        }
    }

    private func updateDisplayedGear() {
        displayedGear = gearEngine?.confirmedGear
        confirmedGearIndex = gearEngine?.confirmedIndex
    }

    private func confirmShift(from oldIndex: Int, to newIndex: Int) {
        let count = max(1, abs(newIndex - oldIndex))
        let confirmed = Array(pendingFeedback.prefix(count))
        pendingFeedback.removeFirst(min(count, pendingFeedback.count))
        lastShiftFeedback =
            confirmed.contains(.multiple) || count > 1 ? .multiple : .single
        shiftConfirmation &+= 1
    }

    private func abortStart(_ error: Error) async {
        peripheral.stopAdvertising()
        click.disconnect()
        kickr.disconnect()
        UIApplication.shared.isIdleTimerDisabled = false
        sessionID = nil
        gearEngine = nil
        displayedGear = nil
        confirmedGearIndex = nil
        gearSequence = []
        pendingFeedback = []
        sessionBaselineMillimeters = nil
        state = .failed(error.localizedDescription)
        log("Ride start failed: \(error.localizedDescription)", .error)
    }

    private func log(
        _ message: String,
        _ level: ProductDiagnosticLevel = .info
    ) {
        diagnostics.record(message, source: "Proxy", level: level)
    }
}
