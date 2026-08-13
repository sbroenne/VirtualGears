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
