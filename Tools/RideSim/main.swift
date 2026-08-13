import CoreBluetooth
import Foundation
import ToolSupport
import VirtualGearsCore

/// Pretends to be the riding app on the PC, so the phone's side of the
/// conversation can be checked against a real link instead of a test double.
///
/// The app's own tests stop at the edge of CoreBluetooth. Everything past that
/// edge - what a riding app actually sees when it subscribes, asks for
/// control, steers, and comes back after a drop - has only ever been checked
/// by riding. This connects to the phone exactly as a riding app does and
/// answers those questions on demand.
///
/// What it can prove:
///
///  1. The phone advertises as a fitness machine under the right name.
///  2. Its characteristics have the properties the spec requires, so a riding
///     app can subscribe to what it needs.
///  3. Asking for control is granted, and steering is accepted.
///  4. Ride data actually arrives, at what rate, and with what worst gap.
///  5. A riding app that vanished without unsubscribing can come back and take
///     control again. This is the lock-out bug, and it is the one fault worth
///     causing on purpose.
///
/// What it cannot prove, and will not pretend to: the stall behind an
/// unacknowledged indication that ended the ride on 10 August. A central does
/// not choose when to confirm an indication - the Bluetooth stack does - so
/// that fault cannot be caused from here. This tool can only measure how long
/// answers take, and report a stall if one happens to occur.
///
/// Run it with the app open and shifting on the phone. It never speaks to the
/// trainer or the fan.
let log = ToolLog(environmentKey: "RIDE_SIM_LOG", defaultPath: "/tmp/ride-sim.log")
let logPath = log.path

func say(_ text: String) { log.say(text) }

/// One thing that was checked, so a run ends with a verdict rather than a wall
/// of prose.
struct Check {
    let name: String
    let passed: Bool
    let detail: String
}

enum SimError: Error, CustomStringConvertible {
    case timedOut(String)
    case missing(String)

    var description: String {
        switch self {
        case let .timedOut(what): "timed out waiting for \(what)"
        case let .missing(what): "\(what) is missing"
        }
    }
}

@MainActor
final class RideSim: NSObject {
    private var central: CBCentralManager!
    private var target: CBPeripheral? { finder.peripheral }

    private let serviceUUID = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let controlPointUUID = CBUUID(
        string: FTMSUUID.fitnessMachineControlPoint
    )
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)

    private lazy var finder = PeripheralFinder(
        scanServices: [serviceUUID], discoveryServices: [serviceUUID], say: say,
        matches: { [weak self] in $0.advertisedName().localizedCaseInsensitiveContains(self?.name ?? "") },
        foundMessage: { "Found \"\($0.advertisedName())\" at \($0.rssi) dBm. Connecting." }
    )

    private var controlPoint: CBCharacteristic?
    private var bikeData: CBCharacteristic?
    private var status: CBCharacteristic?
    private var feature: CBCharacteristic?

    private var checks: [Check] = []
    private var bikeDataArrivals: [Date] = []
    private var statusMessages: [String] = []
    private var hasStarted = false

    /// The answer to the request currently in flight. Only one may be
    /// outstanding at a time, which is the whole reason a slow answer is
    /// dangerous.
    private let responseWaiter = CharacteristicWaiter<FitnessMachineControlPointResponse>()
    private var pendingSentAt: Date?
    private var responseTimes: [TimeInterval] = []

    /// Set while the link is dropped on purpose, so it is not reported as a
    /// failure.
    private var isDroppingOnPurpose = false
    private var reconnected: CheckedContinuation<Void, Error>?

    private let name: String
    private let dataSeconds: Int

    init(name: String, dataSeconds: Int) {
        self.name = name
        self.dataSeconds = dataSeconds
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(Check(name: name, passed: passed, detail: detail))
        say("\(passed ? "PASS" : "FAIL")  \(name) - \(detail)")
    }

    // MARK: - The run

    func start() {
        say("ride-sim: pretending to be a riding app.")
        say("Looking for a fitness machine called \"\(name)\".")
        say("")
        // A watchdog that does not depend on Bluetooth ever coming up. Without
        // it, a permission prompt left unanswered leaves the tool waiting for
        // a radio that never powers on, and nothing is ever reported.
        scheduleMainActorTimeout(after: .seconds(120)) {
            self.giveUp(
                "Gave up after two minutes. If macOS asked for Bluetooth "
                    + "permission, answer it and run this again."
            )
        }
    }

    private func run() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { @MainActor in
            do {
                try await checkCharacteristics()
                try await checkControlHandshake()
                try await checkSteering()
                try await checkDataStream()
                try await checkReturnAfterADrop()
            } catch {
                record("The run finished", false, "\(error)")
            }
            report()
        }
    }

    private func checkCharacteristics() async throws {
        guard let controlPoint, let bikeData, let status else {
            throw SimError.missing("a characteristic a riding app needs")
        }
        record(
            "The control point takes writes and answers back",
            controlPoint.properties.contains(.write)
                && controlPoint.properties.contains(.indicate),
            controlPoint.properties.toolDescription
        )
        record(
            "Ride data is a notify stream",
            bikeData.properties.contains(.notify),
            bikeData.properties.toolDescription
        )
        record(
            "Machine status is a notify stream",
            status.properties.contains(.notify),
            status.properties.toolDescription
        )
        if let feature {
            target?.readValue(for: feature)
        }
        try await subscribe()
    }

    private func subscribe() async throws {
        guard let target, let controlPoint, let bikeData, let status else {
            throw SimError.missing("the connection")
        }
        target.setNotifyValue(true, for: controlPoint)
        target.setNotifyValue(true, for: bikeData)
        target.setNotifyValue(true, for: status)
        try await Task.sleep(for: .seconds(2))
        record(
            "A riding app can subscribe to all three",
            controlPoint.isNotifying && bikeData.isNotifying
                && status.isNotifying,
            "control point \(controlPoint.isNotifying), "
                + "ride data \(bikeData.isNotifying), "
                + "status \(status.isNotifying)"
        )
    }

    private func checkControlHandshake() async throws {
        let response = try await send(.requestControl)
        record(
            "Asking for control is granted",
            response.result == .success,
            "answered \(response.result) in "
                + milliseconds(responseTimes.last ?? 0)
        )
    }

    private func checkSteering() async throws {
        let hill = try await send(
            .setIndoorBikeSimulationParameters(
                IndoorBikeSimulationParameters(
                    windSpeedThousandthsMetersPerSecond: 0,
                    gradeHundredthsPercent: 300,
                    rollingResistanceCoefficientTenThousandths: 40,
                    windResistanceCoefficientHundredthsKilogramsPerMeter: 51
                )
            )
        )
        record(
            "A hill can be sent to the trainer",
            hill.result == .success,
            "answered \(hill.result) in " + milliseconds(responseTimes.last ?? 0)
        )

        // A riding app never sends this, but the phone must accept it, because
        // rescaling the wheel is how the proxy shifts gear.
        let wheel = try await send(
            .setWheelCircumference(tenthsOfMillimeter: 21000)
        )
        record(
            "A wheel size can be set",
            wheel.result == .success,
            "answered \(wheel.result) in " + milliseconds(responseTimes.last ?? 0)
        )
    }

    private func checkDataStream() async throws {
        say("")
        say("Listening to the ride data for \(dataSeconds) seconds.")
        bikeDataArrivals.removeAll()
        try await Task.sleep(for: .seconds(dataSeconds))

        let count = bikeDataArrivals.count
        guard count > 1 else {
            record(
                "Ride data arrives",
                false,
                "\(count) messages in \(dataSeconds) seconds. Is a ride running?"
            )
            return
        }
        var worstGap: TimeInterval = 0
        for (earlier, later) in zip(bikeDataArrivals, bikeDataArrivals.dropFirst()) {
            worstGap = max(worstGap, later.timeIntervalSince(earlier))
        }
        let rate = Double(count) / Double(dataSeconds)
        record(
            "Ride data arrives steadily",
            worstGap < 3,
            String(
                format: "%.1f per second, worst gap %@",
                rate,
                milliseconds(worstGap)
            )
        )
    }

    /// The lock-out bug, caused on purpose.
    ///
    /// A riding app whose link drops does not reliably get to unsubscribe on
    /// the way out, so its claim on the trainer can outlive it. If the phone
    /// honours that dead claim, the app trying to come back is refused, and
    /// nothing on the PC can clear it. Killing the link without a word is what
    /// a crashed riding app looks like from the phone's side.
    private func checkReturnAfterADrop() async throws {
        say("")
        say("Dropping the link without unsubscribing, the way a crash would.")
        guard let target else { throw SimError.missing("the connection") }

        isDroppingOnPurpose = true
        central.cancelPeripheralConnection(target)
        try await Task.sleep(for: .seconds(3))

        say("Coming back, as a riding app would after being restarted.")
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            reconnected = continuation
            central.connect(target, options: nil)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if let waiting = reconnected {
                    reconnected = nil
                    waiting.resume(throwing: SimError.timedOut("the reconnection"))
                }
            }
        }
        isDroppingOnPurpose = false

        try await subscribe()
        let response = try await send(.requestControl)
        record(
            "A riding app that vanished can take control again",
            response.result == .success,
            response.result == .success
                ? "granted in " + milliseconds(responseTimes.last ?? 0)
                : "answered \(response.result): the trainer is held by a "
                    + "connection that no longer exists"
        )
    }

    // MARK: - Talking to the control point

    private func send(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> FitnessMachineControlPointResponse {
        guard let target, let controlPoint else {
            throw SimError.missing("the control point")
        }
        let payload = try request.encode()
        pendingSentAt = Date()
        return try await responseWaiter.wait(
            timeout: .seconds(10),
            timedOut: SimError.timedOut("an answer to \(request)")
        ) {
            target.writeValue(payload, for: controlPoint, type: .withResponse)
        }
    }

    /// Every way out of this tool goes through here, so the run script is
    /// always told the run is over.
    private func giveUp(_ reason: String) -> Never {
        say(reason)
        ToolSupport.finish(sentinel: "ride-sim finished.", code: 1, say: say)
    }

    private func report() {
        let failed = checks.filter { !$0.passed }
        say("")
        say(String(repeating: "-", count: 60))
        if let slowest = responseTimes.max() {
            say("Slowest answer from the phone: \(milliseconds(slowest)).")
        }
        for message in statusMessages.prefix(10) {
            say("Status message: \(message)")
        }
        if failed.isEmpty {
            say("All \(checks.count) checks passed.")
        } else {
            say("\(failed.count) of \(checks.count) checks failed:")
            for check in failed {
                say("  - \(check.name): \(check.detail)")
            }
        }
        say("Full output is also in \(logPath).")
        // The run script watches for this line so it can stop following the
        // log rather than hanging until it is interrupted.
        ToolSupport.finish(
            sentinel: "ride-sim finished.",
            code: failed.isEmpty ? 0 : 1,
            say: say
        )
    }
}

extension RideSim: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            finder.startScanning(with: central)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if self.target == nil {
                    self.giveUp(
                        "Nothing called \"\(self.name)\" is advertising as a "
                            + "fitness machine. Is the app open and shifting?"
                    )
                }
            }
        case .unauthorized:
            giveUp("macOS refused Bluetooth. Allow it in Privacy settings.")
        case .poweredOff:
            giveUp("Bluetooth is off.")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        if let found = finder.connectFirstMatch(
            from: central, peripheral: peripheral,
            advertisementData: advertisementData, rssi: RSSI, delegate: self
        ) {
            record("The phone advertises as a fitness machine", true, found.advertisedName())
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        finder.discoverServices(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard !isDroppingOnPurpose else { return }
        say(
            "The phone disconnected: "
                + (error?.localizedDescription ?? "no reason given") + "."
        )
        report()
    }
}

extension RideSim: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let service = peripheral.services?.first(where: {
            $0.uuid == serviceUUID
        }) else {
            record(
                "The phone offers a fitness machine service",
                false,
                "not found"
            )
            report()
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case controlPointUUID: controlPoint = characteristic
            case bikeDataUUID: bikeData = characteristic
            case statusUUID: status = characteristic
            case featureUUID: feature = characteristic
            default: break
            }
        }
        // A reconnection rediscovers everything, but the run only starts once.
        if let waiting = reconnected {
            reconnected = nil
            waiting.resume()
            return
        }
        run()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case controlPointUUID:
            guard responseWaiter.isWaiting else { return }
            if let sentAt = pendingSentAt {
                responseTimes.append(Date().timeIntervalSince(sentAt))
            }
            do {
                let response = try FitnessMachineControlPointResponse.decode(data)
                responseWaiter.resume(returning: response)
            } catch {
                responseWaiter.resume(throwing: error)
            }
        case bikeDataUUID:
            bikeDataArrivals.append(Date())
        case statusUUID:
            if let first = data.first {
                statusMessages.append(String(format: "opcode 0x%02X", first))
            }
        case featureUUID:
            let decoded = try? FitnessMachineFeature.decode(data)
            record(
                "The machine says what it can do",
                decoded != nil,
                decoded.map { "\($0.machineFeatures)" } ?? "could not be read"
            )
        default:
            break
        }
    }
}

// MARK: - Starting up

var name = "Virtual Gears"
var dataSeconds = 15
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--name":
        if let value = arguments.first {
            name = value
            arguments.removeFirst()
        }
    case "--seconds":
        if let value = arguments.first.flatMap(Int.init) {
            dataSeconds = value
            arguments.removeFirst()
        }
    default:
        break
    }
}

setvbuf(stdout, nil, _IONBF, 0)
log.clear()
let sim = MainActor.assumeIsolated { RideSim(name: name, dataSeconds: dataSeconds) }
MainActor.assumeIsolated { sim.start() }
RunLoop.main.run()
