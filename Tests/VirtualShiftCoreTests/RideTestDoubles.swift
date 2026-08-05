import Foundation
import VirtualShiftCore

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
    private(set) var wheelSizeHistory: [Double] = []
    private(set) var didDisconnect = false
    private(set) var disconnectRestoreRequest: Double??

    /// What the trainer is left on. The whole point of the restore rules.
    var currentWheelSizeMillimeters: Double? { wheelSizeHistory.last }

    /// Set to make the next Wahoo command fail, as a trainer that has gone to
    /// sleep or refused a value would.
    var failNextWahooCommand = false
    /// How long the trainer takes to confirm a gear. Real ones are not instant,
    /// and the hold sweep is paced by exactly this.
    var wahooConfirmationDelay: Duration = .zero
    private(set) var wahooCommandCount = 0

    func execute(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> FitnessMachineControlPointResponse {
        if case .requestControl = request { hasFTMSControl = true }
        return FitnessMachineControlPointResponse(
            requestOpcode: request.opcode,
            result: .success
        )
    }

    func executeWahoo(_ data: Data) async throws -> WahooKickrResponse {
        wahooCommandCount += 1
        if wahooConfirmationDelay > .zero {
            try? await Task.sleep(for: wahooConfirmationDelay)
        }
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
        UUID
    ) async -> FTMSPeripheralCommandResult)?

    /// How many times the riding app has had the trainer pulled out from under
    /// it. Stopping advertising is what disconnects a connected riding app, so
    /// this counts real interruptions, not cosmetic ones.
    private(set) var advertisingStopCount = 0
    private(set) var didStopAcceptingCommands = false

    func startAdvertising() {
        isAdvertising = true
        latestEvent = .advertisingStarted
    }

    func stopAdvertising() {
        if isAdvertising { advertisingStopCount += 1 }
        isAdvertising = false
        latestEvent = .advertisingStopped
    }

    func stopAcceptingCommands() { didStopAcceptingCommands = true }

    /// Sends a command the way a connected riding app would, through the same
    /// handler the real link uses, so tests exercise the real wiring.
    func send(
        _ request: FitnessMachineControlPointRequest,
        from app: UUID = UUID()
    ) async -> FTMSPeripheralCommandResult? {
        await commandHandler?(request, app)
    }
    func relayIndoorBikeData(_ data: Data) {}
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
