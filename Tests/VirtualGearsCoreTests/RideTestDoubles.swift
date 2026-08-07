import Foundation
import VirtualGearsCore

/// Stand-ins for the trainer, the riding app link and the Click.
///
/// These exist so a whole ride can be run without a KICKR, a Click and a PC in
/// the room. They are deliberately literal: the fake trainer really decodes the
/// wheel-size command and remembers what it was set to, so a test asking "what
/// is the trainer left on?" gets the same answer a real one would.

@MainActor
final class FakeTrainer: TrainerLink {
    var isReady = true
    var hasFTMSControl = false
    var state: ProductConnectionState = .ready
    var selectedID: UUID? = UUID()
    var eventHandler: ((KickrEvent) -> Void)?
    var stateHandler: ((ProductConnectionState) -> Void)?

    /// Every wheel size the trainer has been set to, in order. The last one is
    /// what a real KICKR would still be carrying.
    private(set) var wheelSizeHistory: [Double] = [
        TrainerSafety.referenceCircumferenceMillimeters
    ]
    private(set) var didDisconnect = false
    private(set) var disconnectRestoreRequest: Double??
    private(set) var ftmsRequests: [FitnessMachineControlPointRequest] = []

    /// What the trainer is left on. The whole point of the restore rules.
    var currentWheelSizeMillimeters: Double? { wheelSizeHistory.last }

    /// Set to make the next Wahoo command fail, as a trainer that has gone to
    /// sleep or refused a value would.
    var failNextWahooCommand = false
    /// How long the trainer takes to confirm a gear. Real ones are not instant,
    /// and the hold sweep is paced by exactly this.
    var wahooConfirmationDelay: Duration = .zero
    private(set) var wahooCommandCount = 0
    private var queueHead = 0
    private var queueTail = 0

    /// Set to make the trainer refuse FTMS control, which is how a start fails
    /// after the trainer is connected but before any gear is written.
    var deniesFTMSControl = false

    func execute(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> FitnessMachineControlPointResponse {
        ftmsRequests.append(request)
        if case .requestControl = request {
            if deniesFTMSControl {
                return FitnessMachineControlPointResponse(
                    requestOpcode: request.opcode,
                    result: .controlNotPermitted
                )
            }
            hasFTMSControl = true
        }
        return FitnessMachineControlPointResponse(
            requestOpcode: request.opcode,
            result: .success
        )
    }

    func executeWahoo(_ data: Data) async throws -> WahooKickrResponse {
        wahooCommandCount += 1
        // A real KICKR takes one command at a time, and the app's queue holds
        // the rest. What the trainer is left carrying is decided by which write
        // reaches it last, so a double that ran commands concurrently could not
        // model the thing most worth testing.
        let place = queueTail
        queueTail = place + 1
        while queueHead < place {
            await Task.yield()
        }
        if wahooConfirmationDelay > .zero {
            try? await Task.sleep(for: wahooConfirmationDelay)
        }
        defer { queueHead += 1 }
        let bytes = Array(data)
        guard bytes.count == 3, bytes[0] == 0x48 else {
            return .unlock(result: 2)
        }
        let encoded = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        if failNextWahooCommand {
            failNextWahooCommand = false
            // A refusal: the right shape of answer, but not a success, and the
            // trainer keeps the size it already had.
            return .wheelCircumference(result: 0, encodedTenthsOfMillimeter: encoded)
        }
        wheelSizeHistory.append(Double(encoded) / 10)
        return .wheelCircumference(result: 1, encodedTenthsOfMillimeter: encoded)
    }

    func resumeSavedConnection() {}

    func disconnect(restoringCircumferenceMillimeters: Double?) {
        didDisconnect = true
        disconnectRestoreRequest = restoringCircumferenceMillimeters
        if let restore = restoringCircumferenceMillimeters {
            wheelSizeHistory.append(restore)
        }
        // A disconnected trainer cannot be written to. Leaving this double
        // "ready" after a disconnect let code that writes to a trainer it has
        // already dropped look like it worked.
        isReady = false
        state = .disconnected
        stateHandler?(.disconnected)
    }
}

@MainActor
final class FakeRidingAppLink: FitnessMachineBroadcast {
    private(set) var isAdvertising = false
    var subscribedAppCount = 0
    var controllingAppID: UUID?
    var latestEvent: FTMSPeripheralEvent?
    var commandHandler: ((
        FitnessMachineControlPointRequest,
        RidingAppCommandSource
    ) async -> FTMSPeripheralCommandResult)?

    /// How many times the riding app has had the trainer pulled out from under
    /// it. Stopping advertising is what disconnects a connected riding app, so
    /// this counts real interruptions, not cosmetic ones.
    private(set) var advertisingStopCount = 0
    private(set) var didStopAcceptingCommands = false
    private(set) var acceptingCommands = false
    private(set) var relayedBikeData: [Data] = []
    private var controlSubscribers: [UUID: UUID] = [:]

    func startAdvertising() {
        isAdvertising = true
        acceptingCommands = true
        latestEvent = .advertisingStarted
    }

    func stopAdvertising() {
        if isAdvertising { advertisingStopCount += 1 }
        isAdvertising = false
        latestEvent = .advertisingStopped
        controlSubscribers.removeAll()
    }

    func stopAcceptingCommands() {
        didStopAcceptingCommands = true
        acceptingCommands = false
    }

    func isControlSubscriber(_ source: RidingAppCommandSource) -> Bool {
        controlSubscribers[source.centralID] == source.subscriptionID
    }

    func disconnect(_ id: UUID) {
        controlSubscribers.removeValue(forKey: id)
    }

    func subscribe(_ id: UUID) {
        controlSubscribers[id] = UUID()
    }

    /// Sends a command the way a connected riding app would, through the same
    /// handler the real link uses, so tests exercise the real wiring.
    func send(
        _ request: FitnessMachineControlPointRequest,
        from app: UUID = UUID()
    ) async -> FTMSPeripheralCommandResult? {
        if controlSubscribers[app] == nil { subscribe(app) }
        guard acceptingCommands else {
            return .init(result: .operationFailed, status: nil)
        }
        let source = RidingAppCommandSource(
            centralID: app,
            subscriptionID: controlSubscribers[app]!
        )
        return await commandHandler?(request, source)
    }
    func relayIndoorBikeData(_ data: Data) { relayedBikeData.append(data) }
    func notifyControlLost() {}
}

@MainActor
final class FakeShifter: ShifterLink {
    var isReady = true
    var state: ProductConnectionState = .ready
    var shiftHandler: ((ShiftRequest) -> Void)?
    private(set) var didDisconnect = false

    func resumeSavedConnection() {}
    func disconnect() { didDisconnect = true }

    /// Pretends a button was pressed, the way the real Click would report it.
    func press(_ request: ShiftRequest) { shiftHandler?(request) }
}

@MainActor
final class FakeScreen: ScreenWake {
    var keepAwake = false {
        didSet { if keepAwake { wasEverAwake = true } }
    }
    private(set) var wasEverAwake = false
}
