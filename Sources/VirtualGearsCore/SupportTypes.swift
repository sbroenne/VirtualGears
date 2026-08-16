import Foundation
import Observation
import OSLog

/// How a list of found devices takes in a fresh sighting.
///
/// Bluetooth reports the same device many times a second. Devices keep the
/// order they were first found so rows cannot move while somebody reaches for
/// one, and repeated advertisements are ignored unless visible details change.
extension Array where Element == BluetoothCandidate {
    /// Returns whether the list changed.
    @discardableResult
    public mutating func absorb(_ sighting: BluetoothCandidate) -> Bool {
        guard let index = firstIndex(where: { $0.id == sighting.id }) else {
            append(sighting)
            return true
        }
        let known = self[index]
        guard known.name != sighting.name
                || known.compatibility != sighting.compatibility
        else { return false }
        self[index] = sighting
        return true
    }
}

public struct BluetoothCandidate: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public var compatibility: TrainerCompatibility = .untested

    public init(
        id: UUID,
        name: String,
        compatibility: TrainerCompatibility = .untested
    ) {
        self.id = id
        self.name = name
        self.compatibility = compatibility
    }
}

public enum ProductConnectionState: Equatable {
    case unavailable(String)
    case disconnected
    case scanning
    case reconnecting(attempt: Int)
    case connecting(name: String)
    case discovering
    case preparing
    case ready
    case disconnecting
    case failed(String)

    /// True while a connection attempt is actively in progress.
    public var isConnectionInProgress: Bool {
        switch self {
        case .connecting, .reconnecting, .discovering, .preparing: true
        default: false
        }

    }

    /// What the rider sees. These reach the ride screen footer, so they say what
    /// is happening rather than what the Bluetooth layer is doing. An attempt
    /// count in particular only tells a rider how long it has been going wrong.
    public var label: String {
        switch self {
        case let .unavailable(reason): reason
        case .disconnected: "Not connected"
        case .scanning: "Looking for it…"
        case .reconnecting: "Reconnecting…"
        case let .connecting(name): "Connecting to \(name)…"
        case .discovering: "Getting ready…"
        case .preparing: "Almost ready…"
        case .ready: "Ready"
        case .disconnecting: "Disconnecting…"
        case let .failed(message): message
        }
    }

    /// A short form for rows that already show the device name beside it.
    public var shortLabel: String {
        switch self {
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case let .failed(message): message
        default: label
        }
    }
}

public enum EquipmentDisplayState: Equatable, Sendable {
    case connected
    case connecting
    case disconnected
    case notAdded

    public init(
        isConfigured: Bool,
        connectionState: ProductConnectionState,
        isRequired: Bool
    ) {
        guard isConfigured else {
            self = isRequired ? .disconnected : .notAdded
            return
        }
        switch connectionState {
        case .ready:
            self = .connected
        case _ where connectionState.isConnectionInProgress
            || connectionState == .scanning:
            self = .connecting
        default:
            self = .disconnected
        }
    }

    public var label: String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Not connected"
        case .notAdded: "Not added"
        }
    }
}

public struct DeviceDiscoveryState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case searching
        case showingResults
        case timedOut
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func start() {
        phase = .searching
    }

    public mutating func observe(candidateCount: Int) {
        guard phase == .searching || phase == .showingResults
                || phase == .timedOut else { return }
        if candidateCount > 0 {
            phase = .showingResults
        } else if phase != .timedOut {
            phase = .searching
        }
    }

    public mutating func finish(candidateCount: Int) {
        phase = candidateCount > 0 ? .showingResults : .timedOut
    }

    public mutating func reset() {
        phase = .idle
    }
}

public enum DeviceDiscoveryPolicy {
    /// How long a one-shot search waits before deciding what it found.
    ///
    /// Three seconds was too short to be honest. A Zwift Click and a HEADWIND
    /// both sleep and only advertise for a moment after they are woken, so a
    /// three-second look usually ended before the device had said anything, and
    /// the rider was told nothing was there while holding a device that was.
    public static let searchDuration = Duration.seconds(8)

    /// How often a search that keeps looking checks what has turned up.
    public static let pollInterval = Duration.milliseconds(500)
}

/// Both devices go to sleep on their own, and CoreBluetooth waits for them
/// forever without complaining. Every screen that can be left waiting shows the
/// same words, so the rider only has to learn them once.
///
/// There is deliberately no retry button anywhere: the pending connection
/// completes the moment the device wakes, and a failed attempt is retried on its
/// own every fifteen seconds. Waking the device really is the only thing left to
/// do, so that is the only thing we ask for.
public enum WakeInstruction {
    public static let trainer =
        "Turn the trainer on and give the pedals half a turn. Virtual Gears "
            + "connects on its own as soon as it wakes up."
    public static let click =
        "The Click sleeps to save its battery. Press either of its buttons "
            + "once. Virtual Gears connects on its own as soon as it wakes up."
    public static let headwind =
        "Keep the Headwind plugged in. It advertises even when the fan is stopped."
}

public enum ProductBluetoothError: Error, LocalizedError {    case unavailable(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .commandFailed(message):
            message
        }
    }
}

public enum ProductLogLevel: Sendable {
    case info
    case warning
    case error
}

public enum ProductLogger {
    private static let logger = Logger(
        subsystem: "com.sbroenne.VirtualGears",
        category: "Product"
    )

    public static func record(
        _ message: String,
        source: String,
        level: ProductLogLevel = .info
    ) {
        let safeMessage = sanitized(message)
        switch level {
        case .info:
            // Deliberately `notice`, not `info`. On iOS, `info` lives only in a
            // memory buffer and is gone by the time anyone collects a log, so a
            // whole ride used to leave no trace to diagnose a fault with. These
            // are low-rate ride milestones, not chatter, so they are worth the
            // disk.
            logger.notice(
                "\(source, privacy: .public): \(safeMessage, privacy: .public)"
            )
        case .warning:
            logger.notice(
                "\(source, privacy: .public): \(safeMessage, privacy: .public)"
            )
        case .error:
            logger.error(
                "\(source, privacy: .public): \(safeMessage, privacy: .public)"
            )
        }
    }

    private static func sanitized(_ value: String) -> String {
        let pattern =
            #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        let redacted = value.replacingOccurrences(
            of: pattern,
            with: "<device>",
            options: .regularExpression
        )
        let singleLine = redacted
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return String(singleLine.prefix(500))
    }
}
