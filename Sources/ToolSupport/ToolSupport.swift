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
