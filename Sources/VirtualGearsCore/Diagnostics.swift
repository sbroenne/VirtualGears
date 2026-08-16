import Foundation

public struct AppIdentity: Equatable, Sendable {
    public let displayName: String
    public let marketingVersion: String
    public let buildNumber: String

    public init(
        displayName: String,
        marketingVersion: String,
        buildNumber: String
    ) {
        self.displayName = displayName
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    public init(infoDictionary: [String: Any]) {
        displayName = Self.value(
            for: "CFBundleDisplayName",
            fallbackKey: "CFBundleName",
            in: infoDictionary,
            fallback: "Virtual Gears"
        )
        marketingVersion = Self.value(
            for: "CFBundleShortVersionString",
            in: infoDictionary,
            fallback: "Unknown"
        )
        buildNumber = Self.value(
            for: "CFBundleVersion",
            in: infoDictionary,
            fallback: "Unknown"
        )
    }

    public var versionAndBuild: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    private static func value(
        for key: String,
        fallbackKey: String? = nil,
        in dictionary: [String: Any],
        fallback: String
    ) -> String {
        let candidates = [key, fallbackKey].compactMap { $0 }
        for candidate in candidates {
            if let value = dictionary[candidate] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return fallback
    }
}

public struct DiagnosticsState: Equatable {
    public let trainerConnection: ProductConnectionState
    public let isProxyAdvertising: Bool
    public let subscriberCount: Int
    public let isControlledByRidingApp: Bool
    public let latestPeripheralEvent: FTMSPeripheralEvent?

    public init(
        trainerConnection: ProductConnectionState,
        isProxyAdvertising: Bool,
        subscriberCount: Int,
        isControlledByRidingApp: Bool,
        latestPeripheralEvent: FTMSPeripheralEvent?
    ) {
        self.trainerConnection = trainerConnection
        self.isProxyAdvertising = isProxyAdvertising
        self.subscriberCount = max(0, subscriberCount)
        self.isControlledByRidingApp = isControlledByRidingApp
        self.latestPeripheralEvent = latestPeripheralEvent
    }

    public var trainerSummary: String {
        let summary = switch trainerConnection {
        case .ready:
            "Connected and ready"
        case .disconnected:
            "Not connected"
        case .scanning:
            "Looking for trainer"
        case .reconnecting:
            "Reconnecting"
        case .connecting:
            "Connecting"
        case .discovering, .preparing:
            "Connected, getting ready"
        case .disconnecting:
            "Disconnecting"
        case let .unavailable(reason), let .failed(reason):
            reason
        }
        return DiagnosticsReport.redactingIdentifiers(in: summary)
    }

    public var advertisingSummary: String {
        isProxyAdvertising ? "Advertising" : "Not advertising"
    }

    public var subscribersSummary: String {
        switch subscriberCount {
        case 0: "No riding apps subscribed"
        case 1: "1 riding app subscribed"
        default: "\(subscriberCount) riding apps subscribed"
        }
    }

    public var controlSummary: String {
        isControlledByRidingApp
            ? "A riding app has control"
            : "No riding app has control"
    }

    public var latestEventSummary: String {
        DiagnosticsReport.redactingIdentifiers(
            in: latestPeripheralEvent?.diagnosticsDescription
                ?? "No peripheral event yet"
        )
    }
}

public enum DiagnosticsReport {
    public static let clipboardLifetime: TimeInterval = 10 * 60
    public static let serviceContract =
        "FTMS 0x1826 + CPS 0x1818; Indoor Bike Data and Cycling Power "
            + "Measurement are readable and notifiable"

    public static func make(
        timestamp: Date,
        app: AppIdentity,
        operatingSystem: String,
        device: String,
        state: DiagnosticsState
    ) -> String {
        return redactingIdentifiers(in: [
            "\(app.displayName) diagnostics",
            "Timestamp: \(timestampString(timestamp))",
            "App: \(app.versionAndBuild)",
            "OS: \(operatingSystem)",
            "Device: \(device)",
            "KICKR: \(state.trainerSummary)",
            "Trainer proxy: \(state.advertisingSummary)",
            "Subscribers: \(state.subscribersSummary)",
            "Control: \(state.controlSummary)",
            "Latest FTMS event: \(state.latestEventSummary)",
            "Bluetooth contract: \(serviceContract)",
            "Privacy: Generated on-device and copied only when requested.",
        ].joined(separator: "\n"))
    }

    public static func clipboardExpiration(after date: Date) -> Date {
        date.addingTimeInterval(clipboardLifetime)
    }

    static func redactingIdentifiers(in value: String) -> String {
        let pattern =
            #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        return value.replacingOccurrences(
            of: pattern,
            with: "[identifier removed]",
            options: .regularExpression
        )
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public extension FTMSPeripheralEvent {
    var diagnosticsDescription: String {
        switch self {
        case .advertisingStarted:
            "Trainer proxy started advertising"
        case .advertisingStopped:
            "Trainer proxy stopped advertising"
        case let .centralSubscribed(_, characteristic):
            "A riding app subscribed to \(Self.characteristicName(characteristic))"
        case let .centralUnsubscribed(_, characteristic):
            "A riding app unsubscribed from \(Self.characteristicName(characteristic))"
        case let .controlRequest(_, request):
            "A riding app requested \(request.diagnosticsDescription)"
        case let .controlResponse(_, response):
            "Control request 0x\(Self.hex(response.requestOpcode)) returned "
                + response.result.diagnosticsDescription
        case let .failed(message):
            "Trainer proxy error: \(message)"
        }
    }

    private static func characteristicName(_ value: String) -> String {
        switch value.uppercased() {
        case FTMSUUID.indoorBikeData:
            "FTMS Indoor Bike Data"
        case FTMSUUID.fitnessMachineControlPoint:
            "the FTMS Control Point"
        case CyclingPowerUUID.measurement:
            "Cycling Power Measurement"
        default:
            "Bluetooth characteristic 0x\(value.uppercased())"
        }
    }

    private static func hex(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }
}

private extension FitnessMachineControlPointRequest {
    var diagnosticsDescription: String {
        switch self {
        case .requestControl: "control"
        case .reset: "a reset"
        case let .setTargetResistanceLevel(tenths):
            "resistance \(Double(tenths) / 10)%"
        case let .setTargetPower(watts):
            "target power \(watts) W"
        case .startOrResume: "start or resume"
        case let .stopOrPause(action):
            action == .stop ? "stop" : "pause"
        case let .setIndoorBikeSimulationParameters(parameters):
            "simulation grade \(Double(parameters.gradeHundredthsPercent) / 100)%"
        case let .setWheelCircumference(tenths):
            "wheel circumference \(Double(tenths) / 10) mm"
        }
    }
}

private extension FTMSControlPointResult {
    var diagnosticsDescription: String {
        switch self {
        case .success: "success"
        case .opcodeNotSupported: "opcode not supported"
        case .invalidParameter: "invalid parameter"
        case .operationFailed: "operation failed"
        case .controlNotPermitted: "control not permitted"
        }
    }
}
