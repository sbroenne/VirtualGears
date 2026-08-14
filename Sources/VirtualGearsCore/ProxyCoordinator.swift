import Foundation
import Observation

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
    /// The wheel size the gears are currently built around. A riding app can
    /// supply a new one while a ride is under way, so it is not the size the
    /// trainer gets back on Stop.
    ///
    /// That is not because riding apps change the wheel size part-way through a
    /// ride. FulGaz was watched for five minutes and sent it only as part of
    /// starting a ride, twice, never in between; the capture is
    /// docs/fulgaz-app-tap-run.log. It is because a riding app sends it when
    /// *its* ride starts, and that need not line up with ours: a rider who
    /// starts Virtual Gears first and then starts a course gets a new wheel
    /// size with the gears already engaged.
    public private(set) var sessionBaselineMillimeters: Double?
    /// The baseline selected before the first virtual gear is applied. This is
    /// either 2070 mm or the latest size supplied by the riding app; FTMS does
    /// not expose the trainer's current wheel circumference for reading. It is
    /// deliberately separate from
    /// `sessionBaselineMillimeters`: a riding app that sets its own wheel size
    /// changes what the gears are scaled around.
    public private(set) var preGearBaselineMillimeters: Double?
    /// True once a riding app has set its own wheel size, so the ride screen can
    /// say whose number the gears are built around.
    public private(set) var ridingAppSetWheelSize = false
    /// Whether a virtual gear has actually reached the trainer this ride. Until
    /// it has, there is nothing to put right and nothing to report as unreset.
    private var hasAppliedVirtualGear = false

    public let peripheral: any FitnessMachineBroadcast
    private let kickr: any TrainerLink
    private let click: any ShifterLink
    private let screen: any ScreenWake
    private let defaults: UserDefaults
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
    private var baselineResetTask: Task<Void, Never>?
    private var baselineResetGeneration: UUID?
    /// A normal Stop has to reset Virtual Gears' current gear without racing
    /// the riding app's command queue. Commands already executing finish first;
    /// new ones wait and continue transparently after the reset.
    private var pcCommandGateDepth = 0
    private var pcCommandsInFlight = 0
    private var pcCommandGateWaiters: [CheckedContinuation<Void, Never>] = []
    private var pcCommandIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    /// The riding app's current neutral size survives between Virtual Gears gear
    /// sessions. A retained PC connection is not required to resend it merely
    /// because the rider stopped and restarted virtual shifting.
    private var parkedBaselineMillimeters: Double?
    private var parkedBaselineCameFromRidingApp = false

    /// How many terrain updates have arrived this ride. Only used to give the
    /// log a sense of scale: a wheel-size command arriving after thousands of
    /// terrain updates is plainly mid-ride, one arriving after a handful is
    /// plainly part of starting up.
    private var terrainUpdateCount = 0


    /// The baseline used to build a ride's gears, written down before the ride
    /// starts. A ride normally sends it again on Stop and clears this, so a value
    /// still here at launch means the last ride never got to remove its gear.
    private let unfinishedRideKey = "VirtualGears.unfinishedRideBaselineMillimeters"

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
        defaults: UserDefaults = .standard
    ) {
        self.kickr = kickr
        self.click = click
        self.peripheral = peripheral
        self.screen = screen
        self.defaults = defaults

        peripheral.commandHandler = { [weak self] request, source in
            guard let self else {
                return .init(result: .operationFailed, status: nil)
            }
            return await self.handle(request, from: source)
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

    /// Resets the baseline after a ride that never got to stop.
    ///
    /// A ride normally resets to its baseline on Stop. If iOS ends the app
    /// first, that never runs and the trainer keeps the last gear's wheel size,
    /// which would quietly distort its speed and distance for anything else that
    /// connects to it. The ride's baseline is written down before the ride
    /// starts, so the next launch can finish the reset.
    ///
    /// Nothing is reported to the rider. This is tidying up after an interruption
    /// they did not cause and cannot act on, and the ride they are about to start
    /// sets its own gear regardless.
    public func resetInterruptedRideBaselineIfNeeded() {
        guard baselineResetTask == nil, lifecycle.isBetweenRides else { return }
        let generation = UUID()
        baselineResetGeneration = generation
        baselineResetTask = Task { [weak self] in
            await self?.resetInterruptedRideBaseline()
            guard self?.baselineResetGeneration == generation else { return }
            self?.baselineResetTask = nil
            self?.baselineResetGeneration = nil
        }
    }

    /// Pauses launch-time recovery while the local demo is open.
    ///
    /// The saved baseline remains in place, so returning to the real startup
    /// flow can try again. Demo Mode must never be the reason a trainer command
    /// is sent.
    public func suspendInterruptedRideBaselineRecovery() {
        baselineResetTask?.cancel()
        baselineResetTask = nil
        baselineResetGeneration = nil
    }

    private func resetInterruptedRideBaseline() async {
        guard lifecycle.isBetweenRides else { return }
        let token = lifecycle.baselineResetToken
        guard defaults.object(forKey: unfinishedRideKey) != nil else { return }
        let baseline = parkedBaselineMillimeters
            ?? defaults.double(forKey: unfinishedRideKey)
        guard baseline > 0 else {
            defaults.removeObject(forKey: unfinishedRideKey)
            parkedBaselineMillimeters = baseline
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
            // record below, so the reset stands down rather than overwrite
            // either.
            guard isStillWanted(token) else { return }
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: baseline
            )
            let response = try await kickr.executeWahoo(command)
            guard response.confirmsSuccess(for: command) else { return }
            guard isStillWanted(token) else { return }
            defaults.removeObject(forKey: unfinishedRideKey)
            log("Reset the baseline after an interrupted ride")
        } catch {
            log(
                "Could not yet reset the baseline after an interrupted ride: "
                    + error.localizedDescription,
                .warning
            )
        }
    }

    private func isStillWanted(_ token: UUID) -> Bool {
        !Task.isCancelled && lifecycle.isBaselineResetWanted(token)
    }

    /// Starts a ride immediately so the UI can switch to the ride screen in the
    /// same update. The state transition is synchronous, so a second tap is
    /// rejected by the same guard that protected the previous async entry point.
    public func startRide(configuration: AppConfiguration) {
        guard lifecycle.canStart else { return }
        // A ride sets its own wheel size and puts it back on Stop, so it does
        // the tidying up itself. Letting both run could leave the rider in a
        // gear they did not choose.
        baselineResetTask?.cancel()
        baselineResetTask = nil
        lifecycle.abandonBaselineReset()
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
        closePCCommandGate()
        startTask = Task { [weak self] in
            guard let self else { return }
            await self.waitForPCCommandsToFinish()
            guard self.startMayProceed(id) else {
                self.reopenPCCommandGate()
                return
            }
            await self.runRide(configuration: configuration, sessionID: id)
            self.reopenPCCommandGate()
            self.startTask = nil
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
            let reference = Double(
                configuration.neutralCircumferenceMillimeters
            )
            // A wheel size the riding app parked between rides is only usable
            // if the gears still fit around it. Falling back to the reference
            // keeps Start working instead of failing for the whole launch.
            var baseline = parkedBaselineMillimeters ?? reference
            if !canBuildGears(around: baseline, drivetrain: drivetrain) {
                log(
                    "Your riding app left a \(Int(baseline.rounded())) mm wheel "
                        + "size. Gears built around it would reach outside the "
                        + "range proven safe on this trainer, so this ride "
                        + "starts from \(Int(reference.rounded())) mm instead.",
                    .warning
                )
                baseline = reference
                parkedBaselineCameFromRidingApp = false
            }
            parkedBaselineMillimeters = baseline
            gearEngine = try ConfirmedGearEngine(
                drivetrain: drivetrain,
                baselineCircumferenceMillimeters: baseline
            )
            gearSequence = drivetrain.gears
            updateDisplayedGear()
            sessionBaselineMillimeters = baseline
            preGearBaselineMillimeters = baseline
            ridingAppSetWheelSize = parkedBaselineCameFromRidingApp

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
            // Only now has a virtual gear actually reached the trainer, so only
            // now does the trainer need putting right. Writing the record any
            // earlier makes a stop during connection report a fault that never
            // happened, and leaves a force-quit reset a trainer we never moved.
            hasAppliedVirtualGear = true
            defaults.set(baseline, forKey: unfinishedRideKey)
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

    /// Ends Virtual Gears' gear session without ending the riding app's session.
    ///
    /// The virtual gear is removed before the active gear session is cleared.
    /// Virtual Gears does not send Stop for the riding app, reject its commands,
    /// or remove the service it is connected to.
    public func stopRide() async {
        await stopRide(disconnectWhenFinished: false)
    }

    /// Ends any gear session and drops equipment Virtual Gears owns. The riding
    /// app's link is deliberately left alone; ending that app's session is the
    /// riding app's job.
    public func shutdown() async {
        await stopRide(disconnectWhenFinished: true)
    }

    private func stopRide(disconnectWhenFinished: Bool) async {
        closePCCommandGate()
        defer { reopenPCCommandGate() }
        await waitForPCCommandsToFinish()
        if disconnectWhenFinished, lifecycle.isStopping {
            await waitForCurrentStopToFinish()
            disconnectOwnedEquipment()
            return
        }
        guard let id = lifecycle.beginStopping() else {
            if disconnectWhenFinished { disconnectOwnedEquipment() }
            return
        }
        defer { signalStopFinished() }
        shiftTask?.cancel()
        recoveryTask?.cancel()
        // A ride that is still connecting has its own trainer writes to make.
        // Letting them run alongside the reset below is how a trainer ends up
        // left on a gear's wheel size with the recovery record already deleted,
        // so the stop waits for the start to notice it has been called off.
        startTask?.cancel()
        await startTask?.value
        // The start may have been failing rather than connecting, in which case
        // it has already put the trainer back, said so honestly, and torn the
        // session down while this waited. Carrying on would walk the whole stop
        // through a ride that no longer exists and end by telling the rider the
        // baseline could not be reset when it just was - on the one message
        // in this app that has to be believable.
        guard lifecycle.owns(id) else { return }
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

        // Ending Virtual Gears is not ending the PC app's ride. Remove the
        // virtual gear by returning to the latest baseline the riding app asked
        // for. If it never supplied one, use the 2070 mm reference.
        let parkedBaseline =
            sessionBaselineMillimeters ?? preGearBaselineMillimeters
        if let neutral = parkedBaseline, kickr.isReady {
            do {
                let command = try WahooKickrCommand.setWheelCircumference(
                    millimeters: neutral
                )
                let response = try await kickr.executeWahoo(command)
                guard response.confirmsSuccess(for: command) else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR did not confirm the baseline reset"
                    )
                }
                defaults.removeObject(forKey: unfinishedRideKey)
                parkedBaselineMillimeters = neutral
            } catch {
                failures.append(
                    "Baseline reset failed: \(error.localizedDescription)"
                )
            }
        } else if hasAppliedVirtualGear {
            failures.append("Trainer baseline could not be reset")
        }

        if disconnectWhenFinished { disconnectOwnedEquipment() }
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
            trainerNeedsBaselineReset: stillSet
        )
        if failures.isEmpty { log("Ride session stopped") }
    }

    private func disconnectOwnedEquipment() {
        parkedBaselineMillimeters = nil
        parkedBaselineCameFromRidingApp = false
        click.disconnect()
        kickr.disconnect(resettingCircumferenceMillimeters: nil)
    }

    private func waitForPCCommandGate() async {
        while pcCommandGateDepth > 0 {
            await withCheckedContinuation { pcCommandGateWaiters.append($0) }
        }
    }

    private func closePCCommandGate() {
        pcCommandGateDepth += 1
    }

    private func waitForPCCommandsToFinish() async {
        guard pcCommandsInFlight > 0 else { return }
        await withCheckedContinuation { pcCommandIdleWaiters.append($0) }
    }

    private func finishPCCommand() {
        pcCommandsInFlight -= 1
        guard pcCommandsInFlight == 0 else { return }
        let waiters = pcCommandIdleWaiters
        pcCommandIdleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func reopenPCCommandGate() {
        pcCommandGateDepth -= 1
        guard pcCommandGateDepth == 0 else { return }
        let waiters = pcCommandGateWaiters
        pcCommandGateWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForCurrentStopToFinish() async {
        guard lifecycle.isStopping else { return }
        await withCheckedContinuation { stopCompletionWaiters.append($0) }
    }

    private func signalStopFinished() {
        let waiters = stopCompletionWaiters
        stopCompletionWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
        preGearBaselineMillimeters = nil
        ridingAppSetWheelSize = false
        hasAppliedVirtualGear = false
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
    ///
    /// Returns whether the new gears are the ones now in use, so the rider's
    /// settings can be put back if they are not. Settings quietly claiming
    /// gears the ride is not using is its own kind of wrong answer.
    @discardableResult
    public func changeDrivetrain(_ configuration: AppConfiguration) async -> Bool {
        guard lifecycle.isRiding, let id = lifecycle.sessionID,
              let drivetrain = configuration.drivetrain,
              AppConfiguration.isSafe(drivetrain) else { return false }
        // Nothing may suspend between the wait and the claim below. Two
        // rebuilds would otherwise both see the flag clear and interleave.
        guard await waitForGearsToSettle(id) else {
            log("Gears did not settle in time; keeping the gears in use", .warning)
            return false
        }
        baselineUpdateInProgress = true
        defer { baselineUpdateInProgress = false }
        heldDirection = nil
        guard let baseline = sessionBaselineMillimeters else {
            log("New gears were not applied: the ride had already ended", .warning)
            return false
        }
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
            guard stillRiding(id) else { return false }
            let response = try await kickr.executeWahoo(command)
            guard stillRiding(id) else {
                log("New gears were dropped: the ride ended first", .warning)
                return false
            }
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
            return true
        } catch {
            // The ride carries on with the gears it already had. Ending it
            // would cost the rider their session over a settings change.
            log(
                "Could not apply the new gears: \(error.localizedDescription)",
                .error
            )
            return false
        }
    }

    /// Whether the ride this work belongs to is still the one running. Every
    /// step that suspends has to ask again afterwards: a stop can be claimed
    /// while the trainer is mid-answer, and it owns putting the trainer back.
    /// Whether a full gear ladder still encodes inside the trainer's range
    /// around this wheel size. A riding app is free to set any size it likes.
    /// This is not a limit of the gears or the trainer — either could be built
    /// around far more — but of what has been proven safe, so a size that would
    /// push a gear outside that must not carry into a ride.
    private func canBuildGears(
        around millimeters: Double,
        drivetrain: Drivetrain
    ) -> Bool {
        (try? ConfirmedGearEngine(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters: millimeters
        )) != nil
    }

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
        from source: RidingAppCommandSource
    ) async -> FTMSPeripheralCommandResult {
        logRidingAppCommand(request)
        await waitForPCCommandGate()
        guard peripheral.isControlSubscriber(source) else {
            return .init(result: .controlNotPermitted, status: nil)
        }
        pcCommandsInFlight += 1
        defer { finishPCCommand() }
        return await handleCommand(request, from: source)
    }

    private func handleCommand(
        _ request: FitnessMachineControlPointRequest,
        from source: RidingAppCommandSource
    ) async -> FTMSPeripheralCommandResult {
        guard kickr.isReady else {
            return .init(result: .operationFailed, status: nil)
        }
        guard VirtualTrainerFTMSProfile.supports(request) else {
            log("Rejected unsupported ERG target-power command", .warning)
            return .init(result: .opcodeNotSupported, status: nil)
        }
        do {
            // Between Virtual Gears rides this remains a transparent trainer
            // proxy. Stopping the gear UI must not pause, stop, or otherwise
            // take ownership of the PC riding app's session.
            guard lifecycle.isRiding else {
                if case let .setWheelCircumference(tenths) = request {
                    let millimeters = Double(tenths) / 10
                    let command = try WahooKickrCommand.setWheelCircumference(
                        millimeters: millimeters
                    )
                    let response = try await kickr.executeWahoo(command)
                    guard response.confirmsSuccess(for: command) else {
                        return .init(result: .operationFailed, status: nil)
                    }
                    parkedBaselineMillimeters = millimeters
                    parkedBaselineCameFromRidingApp = true
                    return .success(status: .wheelCircumferenceChanged(
                        tenthsOfMillimeter: tenths
                    ))
                }
                let response = try await kickr.execute(request)
                guard response.requestOpcode == request.opcode,
                      response.result == .success else {
                    return .init(result: response.result, status: nil)
                }
                return .success(status: status(for: request))
            }
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

    /// Wheel circumference is part of the standard interface available to every
    /// riding app. Whenever one sets it, that is the size the app believes the
    /// trainer is running, so Virtual Gears takes it as the new starting point
    /// and rebuilds every gear around it rather than quietly overruling it.
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
        // Nothing may suspend between the wait and the claim below.
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
                "Riding app asked for a \(Int(millimeters.rounded())) mm wheel. "
                    + "Gears built around it would reach outside the range "
                    + "proven safe on this trainer (\(error)). Keeping "
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
        parkedBaselineMillimeters = millimeters
        parkedBaselineCameFromRidingApp = true
        // The reset target just moved. Without this the record left for a
        // force-quit still names the ride's starting size, so recovery would
        // put the trainer somewhere a normal Stop never would.
        defaults.set(millimeters, forKey: unfinishedRideKey)
        gearEngine = rebased
        updateDisplayedGear()
        return .success(status: .wheelCircumferenceChanged(
            tenthsOfMillimeter: UInt16((millimeters * 10).rounded())
        ))
    }

    private func handleKickrEvent(_ event: KickrEvent) {
        if case let .rawBikeData(data) = event {
            peripheral.relayIndoorBikeData(data)
            return
        }
        guard lifecycle.sessionID != nil else { return }
        if event == .status(.controlPermissionLost) {
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
                        "Could not reapply current virtual gear"
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
        // The riding app's control claim is a relationship with Virtual Gears,
        // not with the trainer, so a trainer that blips must not revoke it.
        // Telling the app it has lost control forces it to ask again, and that
        // request is answered from `handleCommand`, which refuses everything
        // while the trainer is away. A riding app that runs out of retries in
        // that window never gets control back for the rest of the ride, with
        // every link still looking healthy. Commands during the blip already
        // fail honestly on their own.
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
        // quietly distort the PC ride that continues through the proxy, so it
        // goes back while the trainer connection is still available.
        var baselineReset = true
        if let neutral = preGearBaselineMillimeters, kickr.isReady {
            do {
                let command = try WahooKickrCommand.setWheelCircumference(
                    millimeters: neutral
                )
                let response = try await kickr.executeWahoo(command)
                guard response.confirmsSuccess(for: command) else {
                    throw ProductBluetoothError.commandFailed(
                        "KICKR did not confirm the baseline reset"
                    )
                }
                defaults.removeObject(forKey: unfinishedRideKey)
            } catch {
                baselineReset = false
                log(
                    "Could not put the wheel size back after a failed start: "
                        + error.localizedDescription,
                    .error
                )
            }
        } else if preGearBaselineMillimeters != nil {
            baselineReset = false
        }
        screen.keepAwake = false
        clearRideData()
        lifecycle.failStart(
            error.localizedDescription,
            trainerNeedsBaselineReset: !baselineReset
        )
        log("Ride start failed: \(error.localizedDescription)", .error)
    }

    private func log(
        _ message: String,
        _ level: ProductLogLevel = .info
    ) {
        ProductLogger.record(message, source: "Proxy", level: level)
    }

    /// Every command a riding app sends, written down as it arrives.

    ///
    /// The app's design assumes a riding app may change the wheel size at any
    /// moment, including mid-ride, and a good deal of machinery exists to cope
    /// with that. Nobody has ever checked whether it happens. This is the one
    /// place every riding-app command passes through, so recording them here
    /// turns that assumption into something a single ride can settle.
    ///
    /// Simulation parameters arrive several times a second on a hilly course
    /// and would bury everything else, so they are counted rather than listed.
    private func logRidingAppCommand(
        _ request: FitnessMachineControlPointRequest
    ) {
        if case .setIndoorBikeSimulationParameters = request {
            terrainUpdateCount &+= 1
            return
        }
        let opcode = "0x" + String(format: "%02X", request.opcode)
        switch request {
        case let .setWheelCircumference(tenths):
            log(
                "Riding app sent \(opcode) set wheel circumference "
                    + "\(Double(tenths) / 10) mm"
                    + " (terrain updates so far: \(terrainUpdateCount))"
            )
        case .requestControl:
            log("Riding app sent \(opcode) request control")
        case .reset:
            log("Riding app sent \(opcode) reset")
        case let .setTargetResistanceLevel(value):
            log("Riding app sent \(opcode) set resistance \(value)")
        case let .setTargetPower(watts):
            log("Riding app sent \(opcode) set target power \(watts) W")
        case .startOrResume:
            log("Riding app sent \(opcode) start or resume")
        case let .stopOrPause(value):
            log("Riding app sent \(opcode) stop or pause \(value)")
        case .setIndoorBikeSimulationParameters:
            break
        }
    }
}

#if DEBUG
extension ProxyCoordinator {
    public func stageScreenshotRide(configuration: AppConfiguration) {
        guard let drivetrain = configuration.drivetrain,
              let engine = try? ConfirmedGearEngine(
                  drivetrain: drivetrain,
                  baselineCircumferenceMillimeters:
                      TrainerSafety.referenceCircumferenceMillimeters
              )
        else { return }

        lifecycle = RideLifecycle()
        _ = lifecycle.beginConnecting()
        lifecycle.markActive()
        gearEngine = engine
        gearSequence = drivetrain.gears
        sessionBaselineMillimeters =
            TrainerSafety.referenceCircumferenceMillimeters
        preGearBaselineMillimeters =
            TrainerSafety.referenceCircumferenceMillimeters
        updateDisplayedGear()
    }
}
#endif
