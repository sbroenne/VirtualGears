import Foundation

/// Why shifting ended badly. A failure to start and a failure to stop need
/// different words: one is worth retrying, the other means the trainer may
/// still be carrying a gear's wheel size and needs putting right.
public enum ShiftingFailure: Equatable, Sendable {
    case starting(trainerNeedsWheelSizeReset: Bool)
    case stopping(trainerNeedsWheelSizeReset: Bool)

    public var trainerNeedsWheelSizeReset: Bool {
        switch self {
        case let .starting(needs), let .stopping(needs): needs
        }
    }

    public var happenedWhileStopping: Bool {
        if case .stopping = self { return true }
        return false
    }
}

public enum ShiftingState: Equatable, Sendable {
    case idle
    case connecting
    case active
    case reconnecting
    case stopping
    case failed(String)

}

public enum ShiftFeedbackKind: Equatable, Sendable {
    case single
    case multiple
}

/// Where shifting has got to, and every decision that follows from it.
///
/// This is deliberately free of Bluetooth and of the phone. The rules about
/// when shifting may start, when losing trainer control is worth recovering, and
/// whether the trainer is still carrying a gear's wheel size are the part worth
/// being certain about, and keeping them here means they can be checked without
/// a trainer in the room.
public struct ShiftingLifecycle: Sendable {
    public private(set) var state: ShiftingState = .idle
    /// Only meaningful alongside a failed state, and always set before it, so
    /// the screen never has to guess which kind of failure it is describing.
    public private(set) var failure: ShiftingFailure?
    /// Identifies the current run of shifting. Work started by one run checks
    /// this before changing anything, so a slow reply from the trainer cannot
    /// land in a run that has since been stopped and started again.
    public private(set) var shiftingID: UUID?
    /// Changed whenever shifting starts. Tidying up after interrupted shifting
    /// carries a copy and stands down if it no longer matches, because
    /// cancelling that work is not enough on its own: it spends most of its
    /// life waiting on a Bluetooth round trip, and those waits do not notice
    /// cancellation.
    public private(set) var wheelSizeResetToken = UUID()

    public init() {}

    // MARK: - Where things stand

    public var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// No ride is running, so tidying up after an earlier one is allowed.
    public var isNotShifting: Bool {
        state == .idle || isFailed
    }

    public var isShiftingPresented: Bool {
        switch state {
        case .connecting, .active, .reconnecting, .stopping: true
        case .idle, .failed: false
        }
    }

    public var isShifting: Bool {
        state == .active
    }

    /// Whether work belonging to `id` may still change anything.
    public func owns(_ id: UUID) -> Bool {
        shiftingID == id
    }

    /// A stop has been claimed and is running. The session identity is kept
    /// until the stop finishes so the stop itself can check it, which means
    /// `owns` alone still answers yes to shifting that is only just starting.
    /// Anything on the starting side has to ask this too, or it would carry on
    /// writing wheel sizes to the trainer while the stop is putting them back.
    public var isStopping: Bool {
        state == .stopping
    }

    // MARK: - Resetting after interrupted shifting

    /// Whether the wheel size reset holding `token` may still act.
    ///
    /// Shifting that has started since then owns the trainer's wheel size and
    /// record of it, so an older reset must not overwrite either.
    public func isWheelSizeResetWanted(_ token: UUID) -> Bool {
        token == wheelSizeResetToken && isNotShifting
    }

    /// Stands down any wheel size reset in flight. Shifting sets its own initial
    /// gear and resets to its wheel size when it stops; letting both run could
    /// leave the rider in a gear they did not choose.
    public mutating func abandonWheelSizeReset() {
        wheelSizeResetToken = UUID()
    }

    // MARK: - Starting

    public var canStart: Bool {
        isNotShifting
    }

    /// Refuses shifting before anything has been connected, so nothing needs
    /// putting right.
    public mutating func refuseStart(_ reason: String) {
        failure = .starting(trainerNeedsWheelSizeReset: false)
        state = .failed(reason)
    }

    @discardableResult
    public mutating func beginConnecting() -> UUID {
        let id = UUID()
        shiftingID = id
        failure = nil
        state = .connecting
        return id
    }

    public mutating func markActive() {
        failure = nil
        state = .active
    }

    /// A start that got far enough to touch the trainer. Whether the trainer
    /// was put back decides what the rider is told.
    public mutating func failStart(
        _ message: String,
        trainerNeedsWheelSizeReset: Bool
    ) {
        clearSession()
        failure = .starting(
            trainerNeedsWheelSizeReset: trainerNeedsWheelSizeReset
        )
        state = .failed(message)
    }

    // MARK: - Losing and regaining trainer control

    /// Whether losing control is worth recovering from.
    ///
    /// A stop in progress is already putting the trainer back, and a KICKR
    /// commonly drops the control grant while it stops. Recovering there would
    /// re-apply the gear's wheel size behind the stop's back and leave the
    /// trainer holding it. Only live shifting is worth recovering.
    public var canRecover: Bool {
        shiftingID != nil && (state == .active || state == .reconnecting)
    }

    public mutating func markReconnecting() {
        state = .reconnecting
    }

    public var isReconnecting: Bool {
        state == .reconnecting
    }

    // MARK: - Stopping

    /// Claims the stop. Returns the run being stopped, or nothing if there is
    /// nothing running or one is already stopping.
    public mutating func beginStopping() -> UUID? {
        guard let id = shiftingID, state != .stopping else { return nil }
        state = .stopping
        return id
    }

    /// Ends the stop. `trainerNeedsWheelSizeReset` should come from whether the
    /// record of the pre-gear wheel size is still there, because that record is
    /// only removed once the trainer confirms the virtual gear is cleared, and so
    /// is the honest answer.
    public mutating func finishStop(
        failures: [String],
        trainerNeedsWheelSizeReset: Bool
    ) {
        clearSession()
        guard !failures.isEmpty else {
            failure = nil
            state = .idle
            return
        }
        failure = .stopping(
            trainerNeedsWheelSizeReset: trainerNeedsWheelSizeReset
        )
        state = .failed(failures.joined(separator: ". "))
    }

    private mutating func clearSession() {
        shiftingID = nil
    }
}

/// Keeps track of which shifts the rider is still waiting on, so the phone can
/// buzz once for a tap and once for a whole sweep rather than once per gear.
public struct ShiftFeedbackLedger: Sendable {
    private var pending: [ShiftFeedbackKind] = []
    public private(set) var latest: ShiftFeedbackKind = .single

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }

    public mutating func record(_ kind: ShiftFeedbackKind) {
        pending.append(kind)
    }

    public mutating func clear() {
        pending.removeAll()
    }

    /// Settles the gears between two confirmed positions. Several gears at once
    /// is a sweep however it was asked for, because that is what it felt like.
    @discardableResult
    public mutating func confirm(from oldIndex: Int, to newIndex: Int)
        -> ShiftFeedbackKind {
        let count = max(1, abs(newIndex - oldIndex))
        let settled = Array(pending.prefix(count))
        pending.removeFirst(min(count, pending.count))
        latest = settled.contains(.multiple) || count > 1 ? .multiple : .single
        return latest
    }
}
