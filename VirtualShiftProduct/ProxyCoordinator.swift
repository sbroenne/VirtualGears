import Foundation
import Observation
import UIKit
import VirtualShiftCore

@MainActor
@Observable
final class ProxyCoordinator {
    /// Where the ride has got to, and every rule that follows from it. Kept in
    /// the package so those rules can be checked without a trainer.
    private(set) var lifecycle = RideLifecycle()
    private(set) var displayedGear: VirtualGear?
    private(set) var confirmedGearIndex: Int?
    /// The gear the rider asked for. It differs from `confirmedGearIndex` only
    /// while the trainer has not acknowledged a shift, so the ride screen can
    /// acknowledge a tap without ever displaying an unconfirmed gear.
    private(set) var requestedGearIndex: Int?
    private(set) var gearSequence: [VirtualGear] = []
    private(set) var shiftConfirmation = 0
    private(set) var shiftInteraction = 0
    /// The wheel size the gears are currently built around. A riding app can
    /// move it mid-ride, so it is not the size the trainer gets back on Stop.
    private(set) var sessionBaselineMillimeters: Double?
    /// The wheel size the trainer had before this ride borrowed it, and the one
    /// value every exit path puts back. It is deliberately separate from
    /// `sessionBaselineMillimeters`: a riding app that sets its own wheel size
    /// changes what the gears are scaled around, not what the trainer is owed.
    private(set) var borrowedNeutralMillimeters: Double?
    /// True once a riding app has set its own wheel size, so the ride screen can
    /// say whose number the gears are built around.
    private(set) var ridingAppSetWheelSize = false

    let peripheral: FTMSPeripheral
    private let kickr: KickrCentralService
    private let click: ClickCentralService
    private let diagnostics: ProductDiagnosticsStore
    private var gearEngine: ConfirmedGearEngine?
    private var shiftTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var usesClick = false
    private var feedback = ShiftFeedbackLedger()
    private var baselineUpdateInProgress = false
    private var restoreTask: Task<Void, Never>?

    /// The wheel size a ride borrowed, written down before the ride starts.
    /// A ride normally puts it back on Stop and clears this, so a value still
    /// here at launch means the last ride never got to finish.
    private let unfinishedRideKey = "VirtualShift.unfinishedRideBaselineMillimeters"

    var state: ProxySessionState { lifecycle.state }
    var failure: RideFailure? { lifecycle.failure }
    var lastShiftFeedback: ShiftFeedbackKind { feedback.latest }

    var isRidePresented: Bool { lifecycle.isRidePresented }

    var canShiftEasier: Bool {
        lifecycle.isRiding && (confirmedGearIndex ?? 0) > 0
    }

    var canShiftHarder: Bool {
        lifecycle.isRiding
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

    /// Puts the trainer back after a ride that never got to stop.
    ///
    /// A ride normally restores the wheel size on Stop. If iOS ends the app
    /// first, that never runs and the trainer keeps the last gear's wheel size,
    /// which would quietly distort its speed and distance for anything else that
    /// connects to it. The size a ride borrows is written down before the ride
    /// starts, so the next launch can finish the job.
    ///
    /// Nothing is reported to the rider. This is tidying up after an interruption
    /// they did not cause and cannot act on, and the ride they are about to start
    /// sets its own gear regardless.
    func restoreInterruptedRideIfNeeded() {
        guard restoreTask == nil, lifecycle.isBetweenRides else { return }
        restoreTask = Task { [weak self] in
            await self?.restoreInterruptedRide()
            self?.restoreTask = nil
        }
    }

    private func restoreInterruptedRide() async {
        guard lifecycle.isBetweenRides else { return }
        let token = lifecycle.restoreToken
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: unfinishedRideKey) != nil else { return }
        let baseline = defaults.double(forKey: unfinishedRideKey)
        guard baseline > 0 else {
            defaults.removeObject(forKey: unfinishedRideKey)
            return
        }
        for _ in 0..<100 {
            if kickr.isReady { break }
            guard isStillWanted(token) else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard isStillWanted(token), kickr.isReady else { return }
        do {
            if !kickr.hasFTMSControl {
                let control = try await kickr.execute(.requestControl)
                guard control.result == .success else { return }
            }
            // A ride can have started while control was being asked for. Its
            // own gear is the wheel size that should win, and it owns the
            // record below, so the restore stands down rather than overwrite
            // either.
            guard isStillWanted(token) else { return }
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: baseline
            )
            let response = try await kickr.executeWahoo(command)
            guard response.confirmsSuccess(for: command) else { return }
            guard isStillWanted(token) else { return }
            defaults.removeObject(forKey: unfinishedRideKey)
            log("Restored the wheel size left behind by an interrupted ride")
        } catch {
            log(
                "Could not yet restore the wheel size from an interrupted ride: "
                    + error.localizedDescription,
                .warning
            )
        }
    }

    private func isStillWanted(_ token: UUID) -> Bool {
        !Task.isCancelled && lifecycle.isRestoreWanted(token)
    }

    /// Starts a ride immediately so the UI can switch to the ride screen in the
    /// same update. The state transition is synchronous, so a second tap is
    /// rejected by the same guard that protected the previous async entry point.
    func startRide(configuration: AppConfiguration) {
        guard lifecycle.canStart else { return }
        // A ride sets its own wheel size and puts it back on Stop, so it does
        // the tidying up itself. Letting both run could leave the rider in a
        // gear they did not choose.
        restoreTask?.cancel()
        restoreTask = nil
        lifecycle.abandonRestore()
        // A Click is deliberately absent from this check. It is an optional
        // accessory that may be asleep, and the on-screen buttons always shift.
        guard configuration.setupComplete,
              configuration.canFinishSetup,
              kickr.selectedID?.uuidString == configuration.kickrUUID else {
            lifecycle.refuseStart("Setup is incomplete")
            return
        }
        usesClick = configuration.usesClick
        let id = lifecycle.beginConnecting()
        Task { await runRide(configuration: configuration, sessionID: id) }
    }

    private func runRide(
        configuration: AppConfiguration,
        sessionID id: UUID
    ) async {
        do {
            guard let drivetrain = configuration.drivetrain,
                  AppConfiguration.isSafe(drivetrain) else {
                throw ProductBluetoothError.commandFailed(
                    "These gears are outside the trainer's safe range"
                )
            }
            gearEngine = try ConfirmedGearEngine(
                drivetrain: drivetrain,
                baselineCircumferenceMillimeters:
                    Double(configuration.neutralCircumferenceMillimeters)
            )
            gearSequence = drivetrain.gears
            updateDisplayedGear()
            sessionBaselineMillimeters =
                Double(configuration.neutralCircumferenceMillimeters)
            borrowedNeutralMillimeters =
                Double(configuration.neutralCircumferenceMillimeters)
            UserDefaults.standard.set(
                Double(configuration.neutralCircumferenceMillimeters),
                forKey: unfinishedRideKey
            )

            kickr.resumeSavedConnection()
            if usesClick { click.resumeSavedConnection() }
            // The connecting screen is exactly when a rider is pedalling to
            // wake the trainer and watching for it to appear. Letting the phone
            // sleep here hides the one thing they are waiting for. Every exit
            // path below hands control of this back.
            UIApplication.shared.isIdleTimerDisabled = true
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
            guard lifecycle.owns(id) else { return }
            peripheral.startAdvertising()
            try await waitUntilPeripheralReady(sessionID: id)
            lifecycle.markActive()
            log("Ride session started")
        } catch {
            guard lifecycle.owns(id) else { return }
            await abortStart(error)
        }
    }

    func stopRide() async {
        guard let id = lifecycle.beginStopping() else { return }
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

        // The wheel size the trainer had before this ride, not whatever a
        // riding app moved the gears onto. A trainer left sitting on a riding
        // app's number works out speed and distance wrongly for everything
        // that connects to it afterwards.
        if let neutral = borrowedNeutralMillimeters, kickr.isReady {
            do {
                let command = try WahooKickrCommand.setWheelCircumference(
                    millimeters: neutral
                )
                let response = try await kickr.executeWahoo(command)
                guard response.confirmsSuccess(for: command) else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR did not confirm baseline restoration"
                    )
                }
                UserDefaults.standard.removeObject(forKey: unfinishedRideKey)
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
        clearRideData()
        // The record is only removed once the trainer confirms the original
        // wheel size is back, so its presence is the honest answer to whether
        // the trainer still needs putting right.
        let stillSet = UserDefaults.standard
            .object(forKey: unfinishedRideKey) != nil
        failures.forEach { log($0, .error) }
        lifecycle.finishStop(
            failures: failures,
            trainerNeedsRestoring: stillSet
        )
        if failures.isEmpty { log("Ride session stopped") }
    }

    private func clearRideData() {
        gearEngine = nil
        displayedGear = nil
        confirmedGearIndex = nil
        requestedGearIndex = nil
        gearSequence = []
        feedback.clear()
        sessionBaselineMillimeters = nil
        borrowedNeutralMillimeters = nil
        ridingAppSetWheelSize = false
    }

    func shift(_ direction: ShiftDirection) {
        handleShiftRequest(.single(direction))
    }

    /// A gear from a held control. It behaves like a single shift but is
    /// reported as a sweep, so the feedback matches holding a Click button.
    func shiftRepeatedly(_ direction: ShiftDirection) {
        handleShiftRequest(.multiple(direction))
    }

    private func waitUntilReady(
        _ service: KickrCentralService,
        named name: String,
        sessionID: UUID
    ) async throws {
        for _ in 0..<300 {
            guard lifecycle.owns(sessionID) else { throw CancellationError() }
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
            guard lifecycle.owns(sessionID) else { throw CancellationError() }
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
            guard lifecycle.owns(sessionID) else { throw CancellationError() }
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
            guard lifecycle.owns(sessionID) else { throw CancellationError() }
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
        guard lifecycle.isRiding, kickr.isReady else {
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

    /// Some riding apps, FulGaz among them, set their own wheel size. That is
    /// the size the rider's app believes the trainer is running, so VirtualShift
    /// takes it as the new starting point and rebuilds every gear around it
    /// rather than quietly overruling it.
    ///
    /// It is honoured only as far as it is safe: if the gears would no longer
    /// fit inside what the trainer was proven to accept, the request is refused
    /// and the ride carries on at the wheel size it already had.
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
        let rebased: ConfirmedGearEngine
        do {
            rebased = try engine.rebased(
                baselineCircumferenceMillimeters: millimeters
            )
        } catch let error as VirtualGearError {
            log(
                "Riding app asked for a \(Int(millimeters.rounded())) mm wheel, "
                    + "which your gears cannot be built around safely "
                    + "(\(error)). Keeping "
                    + "\(Int((sessionBaselineMillimeters ?? 0).rounded())) mm.",
                .warning
            )
            return .init(result: .invalidParameter, status: nil)
        }
        let effectiveCommand = rebased.confirmedSetting.command
        let effectiveResponse = try await kickr.executeWahoo(effectiveCommand)
        guard effectiveResponse.confirmsSuccess(for: effectiveCommand) else {
            throw ProductBluetoothError.commandFailed(
                "KICKR did not confirm rescaled gear"
            )
        }
        sessionBaselineMillimeters = millimeters
        ridingAppSetWheelSize = true
        gearEngine = rebased
        updateDisplayedGear()
        return .success(status: .wheelCircumferenceChanged(
            tenthsOfMillimeter: UInt16((millimeters * 10).rounded())
        ))
    }

    private func handleKickrEvent(_ event: KickrEvent) {
        guard lifecycle.sessionID != nil else { return }
        if case let .rawBikeData(data) = event {
            peripheral.relayIndoorBikeData(data)
        } else if event == .status(.controlPermissionLost) {
            beginRecovery()
        }
    }

    private func handleKickrState(_ connectionState: ProductConnectionState) {
        guard lifecycle.canRecover else { return }
        if connectionState != .ready {
            beginRecovery(startImmediately: false)
            return
        }
        guard lifecycle.isReconnecting, recoveryTask == nil else { return }
        let id = lifecycle.sessionID
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.kickr.execute(.requestControl)
                guard !Task.isCancelled,
                      self.lifecycle.isReconnecting,
                      response.result == .success,
                      let command = self.gearEngine?.confirmedSetting.command else {
                    throw ProductBluetoothError.commandFailed(
                        "Could not reacquire KICKR control"
                    )
                }
                let wahoo = try await self.kickr.executeWahoo(command)
                guard !Task.isCancelled,
                      self.lifecycle.isReconnecting,
                      wahoo.confirmsSuccess(for: command),
                      id.map(self.lifecycle.owns) == true else {
                    throw ProductBluetoothError.commandFailed(
                        "Could not restore current virtual gear"
                    )
                }
                self.lifecycle.markActive()
                self.recoveryTask = nil
            } catch {
                guard id.map(self.lifecycle.owns) == true,
                      self.lifecycle.isReconnecting else {
                    self.recoveryTask = nil
                    return
                }
                self.log("KICKR recovery failed: \(error.localizedDescription)", .error)
                self.recoveryTask = nil
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard id.map(self.lifecycle.owns) == true,
                      self.lifecycle.isReconnecting,
                      self.kickr.isReady else { return }
                self.handleKickrState(.ready)
            }
        }
    }

    private func beginRecovery(startImmediately: Bool = true) {
        // A stop in progress is already putting the trainer back, and a KICKR
        // commonly drops the control grant while it stops. Recovering here
        // would re-apply the gear's wheel size behind the stop's back and
        // leave the trainer holding it. Only a live ride is worth recovering.
        guard lifecycle.canRecover else { return }
        lifecycle.markReconnecting()
        peripheral.notifyControlLost()
        shiftTask?.cancel()
        gearEngine?.cancelPendingChanges()
        feedback.clear()
        updateDisplayedGear()
        if startImmediately, kickr.isReady {
            handleKickrState(.ready)
        }
    }

    private func handleShiftRequest(_ request: ShiftRequest) {
        guard lifecycle.isRiding, !baselineUpdateInProgress else { return }
        let direction: ShiftDirection
        let feedback: ShiftFeedbackKind
        switch request {
        case let .single(value):
            direction = value
            feedback = .single
        case let .multiple(value):
            // Holding a button asks for one more gear only once the trainer has
            // finished the last one. Repeats used to arrive on a fixed timer,
            // which is faster than the trainer can confirm a shift, so a hold
            // queued up gears that carried on arriving after the rider had let
            // go. Asking at the trainer's pace means letting go stops it.
            if let engine = gearEngine, !engine.isSettled { return }
            direction = value
            feedback = .multiple
        }
        shiftInteraction &+= 1
        guard var engine = gearEngine else { return }
        let oldRequested = engine.requestedIndex
        let oldConfirmed = engine.confirmedIndex
        let change = engine.requestShift(by: direction == .harder ? 1 : -1)
        gearEngine = engine
        if engine.requestedIndex == oldRequested {
            log("Ignored shift at drivetrain boundary")
            return
        }
        updateDisplayedGear()
        self.feedback.record(feedback)
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
                    self.feedback.clear()
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
        requestedGearIndex = gearEngine?.requestedIndex
    }

    private func confirmShift(from oldIndex: Int, to newIndex: Int) {
        feedback.confirm(from: oldIndex, to: newIndex)
        shiftConfirmation &+= 1
    }

    private func abortStart(_ error: Error) async {
        // The first gear's wheel size may already be on the trainer, and the
        // trainer works out speed and distance from it. Leaving it there would
        // quietly distort any ride done without VirtualShift, so it goes back
        // before the connection is dropped, while there is still one to use.
        var trainerRestored = true
        if let neutral = borrowedNeutralMillimeters, kickr.isReady {
            do {
                let command = try WahooKickrCommand.setWheelCircumference(
                    millimeters: neutral
                )
                let response = try await kickr.executeWahoo(command)
                guard response.confirmsSuccess(for: command) else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR did not confirm baseline restoration"
                    )
                }
                UserDefaults.standard.removeObject(forKey: unfinishedRideKey)
            } catch {
                trainerRestored = false
                log(
                    "Could not put the wheel size back after a failed start: "
                        + error.localizedDescription,
                    .error
                )
            }
        } else if borrowedNeutralMillimeters != nil {
            trainerRestored = false
        }
        peripheral.stopAdvertising()
        click.disconnect()
        kickr.disconnect()
        UIApplication.shared.isIdleTimerDisabled = false
        clearRideData()
        lifecycle.failStart(
            error.localizedDescription,
            trainerNeedsRestoring: !trainerRestored
        )
        log("Ride start failed: \(error.localizedDescription)", .error)
    }

    private func log(
        _ message: String,
        _ level: ProductDiagnosticLevel = .info
    ) {
        diagnostics.record(message, source: "Proxy", level: level)
    }
}
