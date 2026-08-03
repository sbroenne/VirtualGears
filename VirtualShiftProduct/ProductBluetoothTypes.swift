import CoreBluetooth
import Foundation
import Observation

struct BluetoothCandidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum ProductConnectionState: Equatable {
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

    var label: String {
        switch self {
        case let .unavailable(reason): reason
        case .disconnected: "Not connected"
        case .scanning: "Scanning…"
        case let .reconnecting(attempt): "Reconnecting (attempt \(attempt))…"
        case let .connecting(name): "Connecting to \(name)…"
        case .discovering: "Discovering controls…"
        case .preparing: "Preparing controls…"
        case .ready: "Ready"
        case .disconnecting: "Disconnecting…"
        case let .failed(message): "Error: \(message)"
        }

    }
}

enum ProductBluetoothError: Error, LocalizedError {
    case unavailable(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .commandFailed(message):
            message
        }
    }
}

enum ProductDiagnosticLevel: String, Sendable {
    case info
    case warning
    case error
}

struct ProductDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let date = Date()
    let source: String
    let level: ProductDiagnosticLevel
    let message: String
}

@MainActor
@Observable
final class ProductDiagnosticsStore {
    private(set) var entries: [ProductDiagnosticEntry] = []
    let capacity: Int

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func record(
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

    func exportText(
        appVersion: String,
        deviceDescription: String
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let lines = entries.map {
            "\(formatter.string(from: $0.date)) [\($0.level.rawValue.uppercased())] "
                + "\($0.source): \($0.message)"
        }
        return ([
            "VirtualShift diagnostics",
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

extension CBManagerState {
    var productDescription: String {
        switch self {
        case .unknown: "Bluetooth state is unknown"
        case .resetting: "Bluetooth is resetting"
        case .unsupported: "Bluetooth is unsupported"
        case .unauthorized: "Bluetooth permission is denied"
        case .poweredOff: "Bluetooth is off"
        case .poweredOn: "Bluetooth is on"
        @unknown default: "Bluetooth is unavailable"
        }
    }
}
