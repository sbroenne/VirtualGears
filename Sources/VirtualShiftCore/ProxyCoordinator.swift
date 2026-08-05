import Foundation
import Observation
import VirtualShiftCore

@MainActor
@Observable
public final class ProxyCoordinator {
    /// Where the ride has got to, and every rule that follows from it. Kept in
    /// the package so those rules can be checked without a trainer.
    public private(set) var lifecycle = RideLifecycle()
    public private(set) var displayedGear: VirtualGear?
    public private(set) var confirmedGearIndex: Int?
    /// The gear the rider asked for. It differs from `confirmedGearIndex` only
    /// while the trainer has not acknowledged a shift, so the ride screen can
    /// acknowledge a tap without ever displaying an unconfirmed gear.
    public private(set) var requestedGearIndex: Int?
    public private(set) var gearSequence: [VirtualGear] = []
    public private(set) var shiftConfirmation = 0
    public private(set) var shiftInteraction = 0
    /// The wheel size the gears are currently built around. A riding app can
    /// move it mid-ride, so it is not the size the trainer gets back on Stop.
    public private(set) var sessionBaselineMillimeters: Double?
    /// The wheel size the trainer had before this ride borrowed it, and the one
    /// value every exit path puts back. It is deliberately separate from
    /// `sessionBaselineMillimeters`: a riding app that sets its own wheel size
    /// changes what the gears are scaled around, not what the trainer is owed.
    public private(set) var borrowedNeutralMillimeters: Double?
    /// True once a riding app has set its own wheel size, so the ride screen can
    /// say whose number the gears are built around.
    public private(set) var ridingAppSetWheelSize = false

    public let peripheral: any FitnessMachineBroadcast
    private let kickr: any TrainerLink
    private let click: any ShifterLink
    private let screen: any ScreenWake
    private let defaults: UserDefaults
    private let diagnostics: ProductDiagnosticsStore
    private var gearEngine: ConfirmedGearEngine?
    private var shiftTask: Task<Void, Never>?
    /// The run of a ride that is still getting going. A stop waits for this to
    /// finish before it puts the trainer back, so the two can never be writing
    /// wheel sizes to the trainer at the same time.
    private var startTask: Task<Void, Never>?
    /// Set while a shift button is held. The sweep continues off each confirmed
    /// gear rather than a timer, so it never runs ahead of the trainer.
    private var heldDirection: ShiftDirection?
    private var recoveryTask: Task<Void, Never>?
    private var usesClick = false
    private var feedback = ShiftFeedbackLedger()
    /// Set while the gears are being rebuilt, either because a riding app
    /// moved the wheel size or because the rider chose different gears.
    /// Shifting stands aside for it, and only one rebuild runs at a time: two
    /// would each be working from a picture of the gears the other had already
    /// changed, leaving the rider shown a gear the trainer is not on.
    private var baselineUpdateInProgress = false
    private var restoreTask: Task<Void, Never>?

    /// The wheel size a ride borrowed, written down before the ride starts.
    /// A ride normally puts it back on Stop and clears this, so a value still
    /// here at launch means the last ride never got to finish.
    private let unfinishedRideKey = "VirtualShift.unfinishedRideBaselineMillimeters"

    public var state: ProxySessionState { lifecycle.state }
    public var failure: RideFailure? { lifecycle.failure }
    public var lastShiftFeedback: ShiftFeedbackKind { feedback.latest }

    public var isRidePresented: Bool { lifecycle.isRidePresented }

    public var canShiftEasier: Bool {
        lifecycle.isRiding && (confirmedGearIndex ?? 0) > 0
    }

    public var canShiftHarder: Bool {
        lifecycle.isRiding
            && (confirmedGearIndex ?? Int.max) < gearSequence.count - 1
    }

    public init(
        kickr: any TrainerLink,
        click: any ShifterLink,
        peripheral: any FitnessMachineBroadcast,
        screen: any ScreenWake,
        diagnostics: ProductDiagnosticsStore,
        defaults: UserDefaults = .standard
    ) {
        self.kickr = kickr
        self.click = click
        self.peripheral = peripheral
        self.screen = screen
        self.diagnostics = diagnostics
        self.defaults = defaults

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
    public func restoreInterruptedRideIfNeeded() {
        guard restoreTask == nil, lifecycle.isBetweenRides else { return }
        restoreTask = Task { [weak self] in
            await self?.restoreInterruptedRide()
            self?.restoreTask = nil
        }
    }

    private func restoreInterruptedRide() async {
        guard lifecycle.isBetweenRides else { return }
        let token = lifecycle.restoreToken
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
    public func startRide(configuration: AppConfiguration) {
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
        startTask = Task { [weak self] in
            await self?.runRide(configuration: configuration, sessionID: id)
            self?.startTask = nil
        }
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
            defaults.set(
                Double(configuration.neutralCircumferenceMillimeters),
                forKey: unfinishedRideKey
            )

            kickr.resumeSavedConnection()
            if usesClick { click.resumeSavedConnection() }
            // The connecting screen is exactly when a rider is pedalling to
            // wake the trainer and watching for it to appear. Letting the phone
            // sleep here hides the one thing they are waiting for. Every exit
            // path below hands control of this back.
            screen.keepAwake = true
            try await waitUntilReady(kickr, named: "KICKR", sessionID: id)
            guard startMayProceed(id) else { throw CancellationError() }
            let response = try await kickr.execute(.requestControl)
            guard startMayProceed(id) else { throw CancellationError() }
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
            guard startMayProceed(id) else { throw CancellationError() }
            let initialResponse = try await kickr.executeWahoo(initialCommand)
            guard startMayProceed(id) else { throw CancellationError() }
            guard initialResponse.confirmsSuccess(for: initialCommand) else {
                throw ProductBluetoothError.commandFailed(
                    "KICKR did not confirm the initial virtual gear"
                )
            }
            guard startMayProceed(id) else { throw CancellationError() }
            peripheral.startAdvertising()
            try await waitUntilPeripheralReady(sessionID: id)
            lifecycle.markActive()
            log("Ride session started")
        } catch {
            guard lifecycle.owns(id), !lifecycle.isStopping else { return }
            await abortStart(error)
        }
    }

    public func stopRide() async {
        guard let id = lifecycle.beginStopping() else { return }
        peripheral.stopAcceptingCommands()
        shiftTask?.cancel()
        recoveryTask?.cancel()
        // A ride that is still connecting has its own trainer writes to make.
        // Letting them run alongside the restore below is how a trainer ends up
        // left on a gear's wheel size with the recovery record already deleted,
        // so the stop waits for the start to notice it has been called off.
        startTask?.cancel()
        await startTask?.value
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
                defaults.removeObject(forKey: unfinishedRideKey)
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
        kickr.disconnect(restoringCircumferenceMillimeters: nil)
        screen.keepAwake = false
        clearRideData()
        // The record is only removed once the trainer confirms the original
        // wheel size is back, so its presence is the honest answer to whether
        // the trainer still needs putting right.
        let stillSet = defaults
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
        heldDirection = nil
        displayedGear = nil
        confirmedGearIndex = nil
        requestedGearIndex = nil
        gearSequence = []
        feedback.clear()
        sessionBaselineMillimeters = nil
        borrowedNeutralMillimeters = nil
        ridingAppSetWheelSize = false
    }

    public func shift(_ direction: ShiftDirection) {
        handleShiftRequest(.single(direction))
    }

    /// An on-screen button has been held. The sweep runs until `endHold`, paced
    /// by the trainer, exactly as a held Click button does.
    public func beginHold(_ direction: ShiftDirection) {
        handleShiftRequest(.holdBegan(direction))
    }

    public func endHold() {
        handleShiftRequest(.holdEnded)
    }

    /// Applies a new set of gears without ending the ride.
    ///
    /// This used to stop the ride and start it again, which tears the fitness
    /// machine service out from under the riding app and disconnects it. The
    /// rider had to go back to their PC and reconnect, mid-ride, because they
    /// changed a gear. The gears are rebuilt in place instead, exactly as they
    /// are when a riding app sets its own wheel size, so the riding app never
    /// notices anything happened.
    public func changeDrivetrain(_ configuration: AppConfiguration) async {
        guard lifecycle.isRiding, let id = lifecycle.sessionID,
              let drivetrain = configuration.drivetrain,
              AppConfiguration.isSafe(drivetrain) else { return }
        guard await waitForGearsToSettle(id) else { return }
        baselineUpdateInProgress = true
        defer { baselineUpdateInProgress = false }
        heldDirection = nil
        guard let baseline = sessionBaselineMillimeters else { return }
        do {
            let rebuilt = try ConfirmedGearEngine(
                drivetrain: drivetrain,
                baselineCircumferenceMillimeters: baseline
            )
            let command = rebuilt.confirmedSetting.command
            // The ride can be stopped while the trainer is answering. Writing
            // a gear's wheel size after the stop has put the trainer back is
            // exactly what leaves it carrying one, with nothing recorded to put
            // it right at the next launch.
            guard stillRiding(id) else { return }
            let response = try await kickr.executeWahoo(command)
            guard stillRiding(id) else { return }
            guard response.confirmsSuccess(for: command) else {
                throw ProductBluetoothError.commandFailed(
                    "KICKR did not confirm the new gears"
                )
            }
            gearEngine = rebuilt
            gearSequence = drivetrain.gears
            feedback.clear()
            updateDisplayedGear()
            log("Applied new gears without interrupting the ride")
        } catch {
            // The ride carries on with the gears it already had. Ending it
            // would cost the rider their session over a settings change.
            log(
                "Could not apply the new gears: \(error.localizedDescription)",
                .error
            )
        }
    }

    /// Whether the ride this work belongs to is still the one running. Every
    /// step that suspends has to ask again afterwards: a stop can be claimed
    /// while the trainer is mid-answer, and it owns putting the trainer back.
    private func stillRiding(_ id: UUID) -> Bool {
        lifecycle.owns(id) && lifecycle.isRiding && !lifecycle.isStopping
    }

    /// Waits for shifting to finish and for any other gear rebuild to let go.
    /// Bounded, because a wait that cannot end would leave a riding app's
    /// command unanswered for the rest of the ride.
    private func waitForGearsToSettle(_ id: UUID) async -> Bool {
        for _ in 0..<250 {
            guard stillRiding(id) else { return false }
            if shiftTask == nil, !baselineUpdateInProgress { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Whether a ride that is still getting going may carry on. A claimed stop
    /// always wins: the alternative is two different wheel sizes racing to the
    /// trainer, with whichever lands last deciding what it is left on.
    private func startMayProceed(_ id: UUID) -> Bool {
        lifecycle.owns(id) && !lifecycle.isStopping && !Task.isCancelled
    }

    private func waitUntilReady(
        _ service: any ConnectableLink,
        named name: String,
        sessionID: UUID
    ) async throws {
        for _ in 0..<300 {
            guard startMayProceed(sessionID) else { throw CancellationError() }
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
            guard startMayProceed(sessionID) else { throw CancellationError() }
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
        guard let id = lifecycle.sessionID else {
            return .init(result: .operationFailed, status: nil)
        }
        // Waits for shifting to finish, and for the rider's own gear change to
        // let go if they happen to be choosing new gears at this moment.
        guard await waitForGearsToSettle(id) else {
            return .init(result: .operationFailed, status: nil)
        }
        baselineUpdateInProgress = true
        defer { baselineUpdateInProgress = false }
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
        // Stopping only turns away commands still queued; this one is already
        // in the handler. Without these checks a wheel size can reach the
        // trainer after the stop has put it back.
        guard stillRiding(id) else {
            return .init(result: .operationFailed, status: nil)
        }
        let effectiveResponse = try await kickr.executeWahoo(effectiveCommand)
        guard stillRiding(id) else {
            return .init(result: .operationFailed, status: nil)
        }
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
        // A sweep cannot outlive the connection it was riding on.
        heldDirection = nil
        gearEngine?.cancelPendingChanges()
        feedback.clear()
        updateDisplayedGear()
        if startImmediately, kickr.isReady {
            handleKickrState(.ready)
        }
    }

    private func handleShiftRequest(_ request: ShiftRequest) {
        // Letting go is obeyed before anything else. Every other request can be
        // turned down, but a sweep that ignores the rider taking their finger
        // off carries on to the end of the cassette on its own.
        //
        // Nothing known reaches this line with the sweep still running: a gear
        // rebuild now claims its flag only once shifting has finished. That is
        // the reason there is no test that fails without these three lines, and
        // it is also why they stay. Clearing what stops a runaway sweep must
        // not depend on a second piece of code continuing to behave.
        if case .holdEnded = request {
            // The gear already asked for is left to finish. Cancelling it would
            // leave the trainer on a wheel size the rider was never shown.
            heldDirection = nil
            return
        }
        guard lifecycle.isRiding, !baselineUpdateInProgress else { return }
        let direction: ShiftDirection
        let feedback: ShiftFeedbackKind
        switch request {
        case let .single(value):
            direction = value
            feedback = .single
        case let .holdBegan(value):
            heldDirection = value
            direction = value
            feedback = .multiple
        case .holdEnded:
            return
        }
        shiftInteraction &+= 1
        guard var engine = gearEngine else { return }
        let oldRequested = engine.requestedIndex
        let oldConfirmed = engine.confirmedIndex
        let change = engine.requestShift(by: direction == .harder ? 1 : -1)
        gearEngine = engine
        if engine.requestedIndex == oldRequested {
            log("Ignored shift at drivetrain boundary")
            heldDirection = nil
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
                    // A lost connection cancels this task and clears the gear
                    // engine's pending change while this line is suspended.
                    // Carrying on would put that change straight back into an
                    // engine no task is driving any more, and every later shift
                    // would then be refused for the rest of the ride.
                    guard !Task.isCancelled else { break }
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
                    // A held button asks for its next gear here rather than on a
                    // timer, so the sweep runs at whatever pace the trainer can
                    // actually manage and never asks for a gear it has not
                    // finished the last one of.
                    if change == nil, let held = self.heldDirection,
                       var sweeping = self.gearEngine {
                        change = sweeping.requestShift(
                            by: held == .harder ? 1 : -1
                        )
                        self.gearEngine = sweeping
                        if change != nil {
                            self.feedback.record(.multiple)
                            self.shiftInteraction &+= 1
                            self.updateDisplayedGear()
                        } else {
                            self.heldDirection = nil
                        }
                    }
                } catch {
                    self.heldDirection = nil
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
                defaults.removeObject(forKey: unfinishedRideKey)
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
        kickr.disconnect(restoringCircumferenceMillimeters: nil)
        screen.keepAwake = false
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
