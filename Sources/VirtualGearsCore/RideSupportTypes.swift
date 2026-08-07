import Foundation
import Observation

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
    public static let searchDuration = Duration.seconds(3)
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

public enum ProductDiagnosticLevel: String, Sendable {
    case info
    case warning
    case error
}

public struct ProductDiagnosticEntry: Identifiable, Sendable {
    public let id = UUID()
    public let date = Date()
    public let source: String
    public let level: ProductDiagnosticLevel
    public let message: String
}

@MainActor
@Observable
public final class ProductDiagnosticsStore {
    public private(set) var entries: [ProductDiagnosticEntry] = []
    public let capacity: Int

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public func record(
        _ message: String,
        source: String,
        level: ProductDiagnosticLevel = .info
    ) {
        entries.append(.init(
            source: source,
            level: level,
            message: Self.sanitized(message)
        ))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func exportText(
        appVersion: String,
        deviceDescription: String
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let lines = entries.map {
            "\(formatter.string(from: $0.date)) [\($0.level.rawValue.uppercased())] "
                + "\($0.source): \($0.message)"
        }
        return ([
            "Virtual Gears diagnostics",
            "App: \(appVersion)",
            "Device: \(deviceDescription)",
            "Events retained: \(entries.count)/\(capacity)",
            "---",
        ] + lines).joined(separator: "\n")
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
