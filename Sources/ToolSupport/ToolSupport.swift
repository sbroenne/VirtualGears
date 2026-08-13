import CoreBluetooth
import Foundation

public final class ToolLog: @unchecked Sendable {
    public let path: String

    public init(environmentKey: String, defaultPath: String) {
        path = ProcessInfo.processInfo.environment[environmentKey] ?? defaultPath
    }

    public func say(_ text: String) {
        print(text)
        guard let data = (text + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    public func clear() {
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
    }
}

public func milliseconds(_ interval: TimeInterval) -> String {
    String(format: "%.0f ms", interval * 1000)
}

public func finish(sentinel: String, code: Int32, say: (String) -> Void) -> Never {
    say(sentinel)
    exit(code)
}

@discardableResult
public func scheduleMainActorTimeout(
    after duration: Duration,
    _ action: @escaping @MainActor @Sendable () -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        try? await Task.sleep(for: duration)
        action()
    }
}

public extension CBCharacteristicProperties {
    var toolDescription: String {
        var names: [String] = []
        if contains(.read) { names.append("read") }
        if contains(.write) { names.append("write") }
        if contains(.writeWithoutResponse) { names.append("write without response") }
        if contains(.notify) { names.append("notify") }
        if contains(.indicate) { names.append("indicate") }
        return names.isEmpty ? "nothing" : names.joined(separator: ", ")
    }
}

public final class PeripheralFinder {
    public struct Discovery {
        public let peripheral: CBPeripheral
        public let advertisementData: [String: Any]
        public let rssi: NSNumber

        public var peripheralName: String? { peripheral.name }

        public func advertisedName(default defaultName: String = "") -> String {
            advertisementData[CBAdvertisementDataLocalNameKey] as? String
                ?? peripheral.name ?? defaultName
        }
    }

    public private(set) var peripheral: CBPeripheral?
    public let scanServices: [CBUUID]?

    private let discoveryServices: [CBUUID]?
    private let connectOptions: [String: Any]?
    private let matches: (Discovery) -> Bool
    private let foundMessage: (Discovery) -> String
    private let say: (String) -> Void

    public init(
        scanServices: [CBUUID]?,
        discoveryServices: [CBUUID]?,
        connectOptions: [String: Any]? = nil,
        say: @escaping (String) -> Void,
        matches: @escaping (Discovery) -> Bool,
        foundMessage: @escaping (Discovery) -> String
    ) {
        self.scanServices = scanServices
        self.discoveryServices = discoveryServices
        self.connectOptions = connectOptions
        self.say = say
        self.matches = matches
        self.foundMessage = foundMessage
    }

    public func startScanning(with central: CBCentralManager) {
        central.scanForPeripherals(withServices: scanServices)
    }

    @discardableResult
    public func connectFirstMatch(
        from central: CBCentralManager,
        peripheral candidate: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber,
        delegate: CBPeripheralDelegate
    ) -> Discovery? {
        guard peripheral == nil else { return nil }
        let discovery = Discovery(
            peripheral: candidate,
            advertisementData: advertisementData,
            rssi: rssi
        )
        guard matches(discovery) else { return nil }

        peripheral = candidate
        say(foundMessage(discovery))
        central.stopScan()
        candidate.delegate = delegate
        central.connect(candidate, options: connectOptions)
        return discovery
    }

    public func discoverServices(on peripheral: CBPeripheral) {
        peripheral.discoverServices(discoveryServices)
    }
}

@MainActor
public final class CharacteristicWaiter<Response: Sendable> {
    private var continuation: CheckedContinuation<Response, Error>?

    public var isWaiting: Bool { continuation != nil }

    public init() {}

    public func wait(
        timeout: Duration,
        timedOut: Error,
        start: () -> Void
    ) async throws -> Response {
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            self.resume(throwing: timedOut)
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    public func resume(returning response: Response) {
        continuation?.resume(returning: response)
        continuation = nil
    }

    public func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
