import Foundation

/// Why a ride ended badly. A failure to start and a failure to stop need
/// different words: one is worth retrying, the other means the trainer may
/// still be carrying a gear's wheel size and needs putting right.
public enum RideFailure: Equatable, Sendable {
    case starting(trainerNeedsRestoring: Bool)
    case stopping(trainerNeedsRestoring: Bool)

    public var trainerNeedsRestoring: Bool {
        switch self {
        case let .starting(needs), let .stopping(needs): needs
        }
    }

    public var happenedWhileStopping: Bool {
        if case .stopping = self { return true }
        return false
    }
}

public enum ProxySessionState: Equatable, Sendable {
    case idle
    case connecting
    case active
    case reconnecting
    case stopping
    case failed(String)

    public var label: String {
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

public enum ShiftFeedbackKind: Equatable, Sendable {
    case single
    case multiple
}

/// Where a ride has got to, and every decision that follows from it.
///
/// This is deliberately free of Bluetooth and of the phone. The rules about
/// when a ride may start, when losing trainer control is worth recovering, and
/// whether the trainer is still carrying a gear's wheel size are the part worth
/// being certain about, and keeping them here means they can be checked without
/// a trainer in the room.
public struct RideLifecycle: Sendable {
    public private(set) var state: ProxySessionState = .idle
    /// Only meaningful alongside a failed state, and always set before it, so
    /// the screen never has to guess which kind of failure it is describing.
    public private(set) var failure: RideFailure?
    /// Identifies the current ride. Work started by one ride checks this before
    /// changing anything, so a slow reply from the trainer cannot land in a
    /// ride that has since been stopped and started again.
    public private(set) var sessionID: UUID?
    /// Changed whenever a ride starts. Tidying up after an interrupted ride
    /// carries a copy and stands down if it no longer matches, because
    /// cancelling that work is not enough on its own: it spends most of its
    /// life waiting on a Bluetooth round trip, and those waits do not notice
    /// cancellation.
    public private(set) var restoreToken = UUID()

    public init() {}

    // MARK: - Where things stand

    public var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// No ride is running, so tidying up after an earlier one is allowed.
    public var isBetweenRides: Bool {
        state == .idle || isFailed
    }

    public var isRidePresented: Bool {
        switch state {
        case .connecting, .active, .reconnecting, .stopping: true
        case .idle, .failed: false
        }
    }

    public var isRiding: Bool {
        state == .active
    }

    /// Whether work belonging to `id` may still change anything.
    public func owns(_ id: UUID) -> Bool {
        sessionID == id
    }

    /// A stop has been claimed and is running. The session identity is kept
    /// until the stop finishes so the stop itself can check it, which means
    /// `owns` alone still answers yes to a ride that is only just starting.
    /// Anything on the starting side has to ask this too, or it would carry on
    /// writing wheel sizes to the trainer while the stop is putting them back.
    public var isStopping: Bool {
        state == .stopping
    }

    // MARK: - Tidying up after an interrupted ride

    /// Whether the restore holding `token` may still act.
    ///
    /// A ride that has started since owns the trainer's wheel size and owns the
    /// record of it, so an older restore must not overwrite either.
    public func isRestoreWanted(_ token: UUID) -> Bool {
        token == restoreToken && isBetweenRides
    }

    /// Stands down any restore in flight. A ride sets its own wheel size and
    /// puts it back when it stops, so it does the tidying itself; letting both
    /// run could leave the rider in a gear they did not choose.
    public mutating func abandonRestore() {
        restoreToken = UUID()
    }

    // MARK: - Starting

    public var canStart: Bool {
        isBetweenRides
    }

    /// Refuses a ride before anything has been connected, so nothing needs
    /// putting right.
    public mutating func refuseStart(_ reason: String) {
        failure = .starting(trainerNeedsRestoring: false)
        state = .failed(reason)
    }

    @discardableResult
    public mutating func beginConnecting() -> UUID {
        let id = UUID()
        sessionID = id
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
        trainerNeedsRestoring: Bool
    ) {
        clearSession()
        failure = .starting(trainerNeedsRestoring: trainerNeedsRestoring)
        state = .failed(message)
    }

    // MARK: - Losing and regaining trainer control

    /// Whether losing control is worth recovering from.
    ///
    /// A stop in progress is already putting the trainer back, and a KICKR
    /// commonly drops the control grant while it stops. Recovering there would
    /// re-apply the gear's wheel size behind the stop's back and leave the
    /// trainer holding it. Only a live ride is worth recovering.
    public var canRecover: Bool {
        sessionID != nil && (state == .active || state == .reconnecting)
    }

    public mutating func markReconnecting() {
        state = .reconnecting
    }

    public var isReconnecting: Bool {
        state == .reconnecting
    }

    // MARK: - Stopping

    /// Claims the stop. Returns the ride being stopped, or nothing if there is
    /// no ride or one is already stopping.
    public mutating func beginStopping() -> UUID? {
        guard let id = sessionID, state != .stopping else { return nil }
        state = .stopping
        return id
    }

    /// Ends the stop. `trainerNeedsRestoring` should come from whether the
    /// record of the borrowed wheel size is still there, because that record is
    /// only removed once the trainer confirms the original size is back, and so
    /// is the honest answer.
    public mutating func finishStop(
        failures: [String],
        trainerNeedsRestoring: Bool
    ) {
        clearSession()
        guard !failures.isEmpty else {
            failure = nil
            state = .idle
            return
        }
        failure = .stopping(trainerNeedsRestoring: trainerNeedsRestoring)
        state = .failed(failures.joined(separator: ". "))
    }

    private mutating func clearSession() {
        sessionID = nil
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
