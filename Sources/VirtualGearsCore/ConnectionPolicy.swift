import Foundation

/// The link state a Bluetooth peripheral can be in, as far as any decision in
/// this package is concerned.
///
/// CoreBluetooth is not available on every platform this package builds for, and
/// the decisions below are about *what to do*, not about talking to a radio.
/// Mirroring the handful of states we actually branch on keeps them testable
/// without a trainer, a fan, or an iPhone in the room.
public enum LinkState: Equatable, Sendable {
    case absent
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// When to try again after a Bluetooth link drops, and how long to wait.
///
/// Three services — trainer, fan and shifter — each used to carry their own copy
/// of this, including three separate spellings of the same delay table. They now
/// share one, so a change to how patient the app is cannot reach one device and
/// miss the other two.
public enum ReconnectPolicy {
    /// How long to wait before each attempt, in seconds. The last entry repeats
    /// for every attempt after it, so the app keeps trying indefinitely rather
    /// than giving up on a rider mid-ride.
    public static let delaysSeconds: [UInt64] = [1, 2, 4, 8, 15]

    /// The wait before the attempt after `attemptsSoFar` previous ones.
    public static func delaySeconds(afterAttempts attemptsSoFar: Int) -> UInt64 {
        let index = min(max(attemptsSoFar, 0), delaysSeconds.count - 1)
        return delaysSeconds[index]
    }

    /// Whether a reconnect is worth scheduling at all.
    ///
    /// - Parameters:
    ///   - wantsConnection: whether the app is still trying to be connected. A
    ///     rider who pressed disconnect is not waiting for us to come back.
    ///   - radioIsOn: whether Bluetooth is available. Scheduling against a radio
    ///     that is off only burns the attempt count; the radio coming back is
    ///     what restarts this.
    public static func shouldSchedule(
        wantsConnection: Bool,
        radioIsOn: Bool
    ) -> Bool {
        wantsConnection && radioIsOn
    }

    /// Whether the attempt should still go ahead once its wait is over.
    ///
    /// Checked again after the sleep because the world moves during it: the
    /// rider may have disconnected, or the link may have come back on its own.
    public static func shouldProceed(
        wantsConnection: Bool,
        link: LinkState
    ) -> Bool {
        guard wantsConnection else { return false }
        return link != .connected && link != .connecting
    }
}

/// Whether to open a saved device's connection now, later, or not at all.
public enum SavedConnectionPolicy {
    public enum Decision: Equatable, Sendable {
        /// Connect now.
        case connect
        /// Something else is already seeing to it. A connection in flight will
        /// arrive on its own, and a link on its way down reconnects from its own
        /// disconnect callback — starting another attempt here would only let
        /// that callback tear this one down.
        case leaveAlone
        /// There is nothing saved, or the app is deliberately holding off.
        case doNothing
    }

    /// The decision behind reconnecting to the device the rider already chose,
    /// without being asked to.
    public static func decide(
        hasSavedDevice: Bool,
        isSuspendedForDemo: Bool,
        isScanning: Bool,
        link: LinkState
    ) -> Decision {
        guard !isSuspendedForDemo, hasSavedDevice else { return .doNothing }
        // Scanning is the rider choosing a device. Reconnecting underneath that
        // would take the choice away from them.
        guard !isScanning else { return .doNothing }
        switch link {
        case .connected, .connecting, .disconnecting: return .leaveAlone
        case .absent, .disconnected: return .connect
        }
    }
}

/// How long a connection may sit making no visible progress before the rider is
/// told something is wrong.
public enum StallWatchPolicy {
    /// Long enough that an ordinary connection never trips it, short enough that
    /// a rider is not left staring at a spinner.
    public static let patienceSeconds: Double = 5

    public enum Decision: Equatable, Sendable {
        /// Start the clock.
        case beginWatching
        /// A watch is already running. Deliberately *not* restarted: one clock
        /// runs across connecting, discovering and preparing, so ordinary
        /// progress between those steps cannot keep pushing the deadline back
        /// and hide a connection that never finishes.
        case keepWatching
        /// Nothing is in progress, so there is nothing to be stalled.
        case stopWatching
    }

    public static func decide(
        state: ProductConnectionState,
        isAlreadyWatching: Bool
    ) -> Decision {
        guard state.isConnectionInProgress else { return .stopWatching }
        return isAlreadyWatching ? .keepWatching : .beginWatching
    }
}

/// The device the rider chose, as it is written to and read from storage.
///
/// The reading half deserves to be tested: it is the one path that has to cope
/// with whatever is already on a rider's phone, including values written by an
/// older version of the app or corrupted to something that is not a UUID at all.
public struct SavedDeviceIdentity: Equatable, Sendable {
    public let id: UUID
    public let name: String?

    public init(id: UUID, name: String?) {
        self.id = id
        self.name = name
    }

    /// What gets stored.
    public var stored: [String: String] {
        var value = ["id": id.uuidString]
        if let name { value["name"] = name }
        return value
    }

    /// Reads back what was stored, refusing anything it cannot trust.
    ///
    /// A missing or unreadable identifier means there is no saved device, not a
    /// device with a blank one: connecting to a wrong or empty identifier is
    /// worse than asking the rider to choose again.
    public static func from(stored value: [String: Any]?) -> SavedDeviceIdentity? {
        guard let value,
              let idString = value["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        return SavedDeviceIdentity(id: id, name: value["name"] as? String)
    }
}

/// What to do when the trainer has not finished answering a command in time.
///
/// Every timeout used to hang up on the trainer and reconnect, which costs the
/// rider roughly ten seconds of no resistance changes and cancels everything
/// queued behind the stuck command — including virtual shifts. A RealVelo ride
/// on a KICKR V5 hit this eight times, every time on a hill update.
///
/// Hill updates (FTMS simulation parameters) are replaced by the riding app
/// about once a second, so losing one is harmless. When the link is plainly
/// still alive — the trainer confirmed the write and is still sending riding
/// data — skipping that one update is far kinder than a reconnect. Anything
/// that looks like a real link problem still reconnects exactly as before.
public enum CommandTimeoutPolicy {
    /// How recent the trainer's last riding data must be for the link to count
    /// as alive. The KICKR sends it several times a second while connected.
    public static let liveDataWindowSeconds: Double = 3

    /// How many timed-out hill updates in a row may be skipped before the app
    /// stops trusting the link and reconnects.
    public static let maximumConsecutiveSkips = 1

    public enum Decision: Equatable, Sendable {
        /// Fail only this command and carry on with the next one.
        case skipCommand
        /// Hang up and let the reconnect policy bring the trainer back.
        case reconnect
    }

    /// - Parameters:
    ///   - isHillUpdate: whether the command is an FTMS simulation-parameters
    ///     write, which the riding app supersedes continuously.
    ///   - writeConfirmed: whether the trainer acknowledged receiving the
    ///     write. Without that, the link itself is suspect, and a write still in
    ///     flight could be mistaken for the next command's.
    ///   - consecutiveSkips: hill updates already skipped since the last
    ///     command that completed.
    ///   - secondsSinceTrainerData: time since the trainer last sent riding
    ///     data, or `nil` if it has sent none on this connection.
    public static func decide(
        isHillUpdate: Bool,
        writeConfirmed: Bool,
        consecutiveSkips: Int,
        secondsSinceTrainerData: Double?
    ) -> Decision {
        guard isHillUpdate,
              writeConfirmed,
              consecutiveSkips < maximumConsecutiveSkips,
              let age = secondsSinceTrainerData,
              age <= liveDataWindowSeconds else {
            return .reconnect
        }
        return .skipCommand
    }
}

/// What the app knew about the link when a trainer command timed out.
///
/// The old log said only that a command timed out, which cannot tell a dead
/// Bluetooth link from a trainer that quietly dropped one reply. These fields
/// are the ones that separate those cases.
public struct CommandTimeoutReport: Equatable, Sendable {
    public var commandName: String
    public var writeConfirmed: Bool
    public var replyReceived: Bool
    public var commandsQueuedBehind: Int
    public var secondsSinceTrainerData: Double?
    public var secondsSinceControlReply: Double?
    public var consecutiveSkips: Int
    public var decision: CommandTimeoutPolicy.Decision

    public init(
        commandName: String,
        writeConfirmed: Bool,
        replyReceived: Bool,
        commandsQueuedBehind: Int,
        secondsSinceTrainerData: Double?,
        secondsSinceControlReply: Double?,
        consecutiveSkips: Int,
        decision: CommandTimeoutPolicy.Decision
    ) {
        self.commandName = commandName
        self.writeConfirmed = writeConfirmed
        self.replyReceived = replyReceived
        self.commandsQueuedBehind = commandsQueuedBehind
        self.secondsSinceTrainerData = secondsSinceTrainerData
        self.secondsSinceControlReply = secondsSinceControlReply
        self.consecutiveSkips = consecutiveSkips
        self.decision = decision
    }

    public var summary: String {
        func age(_ value: Double?) -> String {
            guard let value else { return "never" }
            return String(format: "%.1f s ago", value)
        }
        let action = switch decision {
        case .skipCommand: "skipping it and staying connected"
        case .reconnect: "reconnecting"
        }
        return "Timeout detail for \(commandName): "
            + "write confirmed \(writeConfirmed ? "yes" : "no"), "
            + "reply received \(replyReceived ? "yes" : "no"), "
            + "\(commandsQueuedBehind) queued behind, "
            + "last trainer data \(age(secondsSinceTrainerData)), "
            + "last control reply \(age(secondsSinceControlReply)), "
            + "\(consecutiveSkips) skipped in a row; \(action)"
    }
}

/// Remembers FTMS commands that were given up on, so a reply that turns up
/// afterwards is recognised as late rather than credited to the next command.
public struct LateReplyTracker: Equatable, Sendable {
    /// How long an abandoned command's reply is still worth waiting for.
    public static let expirySeconds: Double = 30

    private var abandoned: [(opcode: UInt8, at: Double)] = []

    public init() {}

    public var isEmpty: Bool { abandoned.isEmpty }

    public mutating func abandon(opcode: UInt8, at time: Double) {
        abandoned.append((opcode, time))
    }

    public mutating func clear() { abandoned.removeAll() }

    /// Whether a reply to `opcode` should be treated as late.
    ///
    /// A reply that arrives before the current command's write has even been
    /// confirmed cannot be the current command's answer, so it is consumed as
    /// the oldest matching abandoned one. Once the write is confirmed the two
    /// cannot be told apart, so the reply is left for the current command.
    ///
    /// - Returns: how long ago the matching command was abandoned, or `nil`
    ///   if the reply is not late.
    public mutating func consumeLateReply(
        opcode: UInt8,
        currentWriteConfirmed: Bool,
        now: Double
    ) -> Double? {
        abandoned.removeAll { now - $0.at > Self.expirySeconds }
        guard !currentWriteConfirmed,
              let index = abandoned.firstIndex(where: { $0.opcode == opcode })
        else { return nil }
        let entry = abandoned.remove(at: index)
        return now - entry.at
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.abandoned.elementsEqual(rhs.abandoned) {
            $0.opcode == $1.opcode && $0.at == $1.at
        }
    }
}
