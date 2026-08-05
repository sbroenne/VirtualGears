import CoreBluetooth
import Foundation
import VirtualShiftCore

/// Measures how a real KICKR behaves, so the app's timing and lifecycle rules
/// can be checked against the trainer instead of assumed.
///
/// It answers two questions the app's own logs cannot:
///
/// 1. How long does the trainer take to confirm a gear change? A held shift
///    button is now paced by that confirmation, so the answer says whether the
///    old fixed 300 ms repeat was ever slow enough to keep up.
/// 2. Does the trainer take control away when it is told to stop? The app now
///    refuses to recover control during a stop, which only matters if the
///    trainer really does drop it there.
///
/// It shifts through real gears using the same engine the app uses, so what is
/// measured is what a rider would actually experience.
///
/// Every run puts the wheel size back before it exits, including after a
/// failure, because the trainer works out speed and distance from it.
///
/// Run with the iPhone app closed: a KICKR takes one controlling connection.
let logPath = ProcessInfo.processInfo.environment["KICKR_PROBE_LOG"]
    ?? "/tmp/kickr-probe.log"

func say(_ text: String) {
    print(text)
    guard let data = (text + "\n").data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
}

func milliseconds(_ interval: TimeInterval) -> String {
    String(format: "%.0f ms", interval * 1000)
}

enum ProbeError: Error {
    case notReady
    case timedOut
    case noGearsLeft
}

@MainActor
final class KickrProbe: NSObject {
    private var central: CBCentralManager!
    private var kickr: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var subscribed = Set<CBUUID>()
    private var hasStarted = false
    private var ignored = Set<String>()
    private var settleTask: Task<Void, Never>?

    private let ftmsService = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let powerService = CBUUID(
        string: WahooKickrProtocol.cyclingPowerServiceUUID
    )
    private let controlUUID = CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)
    private let wahooUUID = CBUUID(
        string: WahooKickrProtocol.controlCharacteristicUUID
    )

    /// One waiter per characteristic, which is all the protocol allows: a
    /// control point carries one outstanding request at a time.
    private var ftmsWaiter: CheckedContinuation<Data, Error>?
    private var wahooWaiter: CheckedContinuation<Data, Error>?

    private var statusMessages: [Data] = []
    private let neutral = TrainerSafety.referenceCircumferenceMillimeters

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - The experiment

    private func run() async {
        do {
            _ = try await sendFTMS(.requestControl)
            say("Trainer handed over control.")
            let times = try await measureGearConfirmations()
            let heldControl = try await measureControlAfterStop()
            report(times: times, heldControl: heldControl)
        } catch {
            say("\nThe probe stopped early: \(error)")
        }
        await restoreNeutral()
        say("\nDone. Full log in \(logPath)")
        exit(0)
    }

    /// Shifts up one gear at a time, exactly as holding the button does, and
    /// times how long the trainer takes to confirm each one.
    private func measureGearConfirmations() async throws -> [TimeInterval] {
        say("\n== How long does one gear change take to confirm? ==")
        var engine = try ConfirmedGearEngine(
            drivetrain: try Drivetrain.virtualLadder(),
            baselineCircumferenceMillimeters: neutral
        )
        var times: [TimeInterval] = []
        for _ in 0..<8 {
            guard let change = engine.requestShift(by: 1) else {
                throw ProbeError.noGearsLeft
            }
            let began = Date()
            let raw = try await sendWahoo(change.command)
            let elapsed = Date().timeIntervalSince(began)
            let response = try WahooKickrResponse.decode(raw)
            guard engine.acknowledge(response) != nil
                    || engine.confirmedIndex == change.index else {
                say("Gear \(change.index + 1): the trainer did not confirm.")
                continue
            }
            times.append(elapsed)
            say(
                "Gear \(change.index + 1) "
                    + "(\(String(format: "%.1f", change.circumferenceMillimeters)) mm) "
                    + "confirmed in \(milliseconds(elapsed))"
            )
        }
        return times
    }

    /// Sends Stop the way ending a ride does, then asks for something that
    /// needs control, to see whether the trainer still grants it.
    private func measureControlAfterStop() async throws -> Bool {
        say("\n== Does the trainer keep control through a stop? ==")
        statusMessages.removeAll()
        _ = try await sendFTMS(.stopOrPause(.stop))
        say("Stop accepted.")
        // A message announcing lost control can arrive just after the reply to
        // Stop, so there is a moment for it to land.
        try? await Task.sleep(nanoseconds: 800_000_000)
        for data in statusMessages {
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            let decoded = (try? FitnessMachineStatus.decode(data))
                .map { "\($0)" } ?? "not recognised"
            say("Trainer announced: [\(hex)] — \(decoded)")
        }
        do {
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: neutral
            )
            let raw = try await sendWahoo(command)
            let held = try WahooKickrResponse.decode(raw)
                .confirmsSuccess(for: command)
            say(
                held
                    ? "A command after Stop was accepted, so control was kept."
                    : "A command after Stop was refused, so control was lost."
            )
            return held
        } catch {
            say("A command after Stop failed outright: \(error)")
            return false
        }
    }

    private func restoreNeutral() async {
        say("\n== Putting the wheel size back ==")
        do {
            _ = try? await sendFTMS(.requestControl)
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: neutral
            )
            let raw = try await sendWahoo(command)
            if try WahooKickrResponse.decode(raw).confirmsSuccess(for: command) {
                say("Wheel size back to \(Int(neutral)) mm. The trainer is as it was.")
            } else {
                say("WARNING: the trainer did not confirm the wheel size going back.")
            }
        } catch {
            say("WARNING: could not put the wheel size back: \(error)")
        }
    }

    private func report(times: [TimeInterval], heldControl: Bool) {
        say("\n== What this means for the app ==")
        guard !times.isEmpty else {
            say("Nothing was confirmed, so nothing can be concluded.")
            return
        }
        let slowest = times.max() ?? 0
        let average = times.reduce(0, +) / Double(times.count)
        say(
            "Confirmations: fastest \(milliseconds(times.min() ?? 0)), "
                + "average \(milliseconds(average)), "
                + "slowest \(milliseconds(slowest))"
        )
        if slowest > 0.3 {
            say(
                "At least one gear took longer than the 300 ms the app used to "
                    + "leave between repeats, so holding a button really could "
                    + "ask for gears faster than the trainer applies them."
            )
        } else {
            say(
                "Every gear confirmed inside 300 ms on this connection, so the "
                    + "old repeat rate was not outrunning the trainer here. "
                    + "Pacing by confirmation still cannot overshoot."
            )
        }
        say(
            heldControl
                ? "Control survived Stop this time. Refusing to recover during "
                    + "a stop costs nothing, and still covers the case where "
                    + "control is dropped."
                : "Control was lost at Stop, which is exactly when the app used "
                    + "to start recovering and re-apply a gear behind the "
                    + "stop's back."
        )
    }

    // MARK: - Talking to the trainer

    private func sendFTMS(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> Data {
        try await write(try request.encode(), to: controlUUID, isWahoo: false)
    }

    private func sendWahoo(_ command: Data) async throws -> Data {
        try await write(command, to: wahooUUID, isWahoo: true)
    }

    private func write(
        _ payload: Data,
        to uuid: CBUUID,
        isWahoo: Bool
    ) async throws -> Data {
        guard let kickr, let characteristic = characteristics[uuid] else {
            throw ProbeError.notReady
        }
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.failWaiter(isWahoo: isWahoo)
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            if isWahoo {
                wahooWaiter = continuation
            } else {
                ftmsWaiter = continuation
            }
            kickr.writeValue(payload, for: characteristic, type: .withResponse)
        }
    }

    private func failWaiter(isWahoo: Bool) {
        if isWahoo {
            wahooWaiter?.resume(throwing: ProbeError.timedOut)
            wahooWaiter = nil
        } else {
            ftmsWaiter?.resume(throwing: ProbeError.timedOut)
            ftmsWaiter = nil
        }
    }
}

@MainActor
extension KickrProbe: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            say("Looking for a KICKR. Wake it, and close the phone app first.")
            central.scanForPeripherals(withServices: [ftmsService])
        case .unauthorized:
            say("macOS refused Bluetooth. Allow it for this tool and run again.")
            exit(1)
        case .poweredOff:
            say("Bluetooth is off.")
            exit(1)
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
        guard kickr == nil else { return }
        // The iPhone running VirtualShift also advertises as a fitness machine,
        // so the trainer has to be picked by name rather than by service.
        let name = peripheral.name ?? ""
        guard name.uppercased().contains("KICKR") else {
            if !ignored.contains(name) {
                ignored.insert(name)
                say("Ignoring \(name.isEmpty ? "an unnamed device" : name).")
            }
            return
        }
        say("Found \(name) at \(RSSI) dBm. Connecting.")
        kickr = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([ftmsService, powerService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        say("The trainer disconnected.")
        exit(1)
    }
}

@MainActor
extension KickrProbe: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
            if [controlUUID, statusUUID, wahooUUID].contains(characteristic.uuid) {
                say("Found the \(label(characteristic.uuid)) channel.")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        startWhenSettled()
    }

    private func label(_ uuid: CBUUID) -> String {
        switch uuid {
        case controlUUID: return "standard control"
        case statusUUID: return "status"
        case wahooUUID: return "Wahoo gear"
        default: return uuid.uuidString
        }
    }

    /// Discovery arrives in pieces, so this waits for a quiet moment rather
    /// than guessing which channel reports itself last.
    private func startWhenSettled() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, !self.hasStarted else { return }
            guard self.characteristics[self.controlUUID] != nil,
                  self.characteristics[self.wahooUUID] != nil else {
                say("The trainer is missing a channel this probe needs.")
                exit(1)
            }
            self.hasStarted = true
            say("Connected and listening.")
            await self.run()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        subscribed.insert(characteristic.uuid)
        startWhenSettled()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case controlUUID:
            ftmsWaiter?.resume(returning: data)
            ftmsWaiter = nil
        case wahooUUID:
            wahooWaiter?.resume(returning: data)
            wahooWaiter = nil
        case statusUUID:
            statusMessages.append(data)
        default:
            break
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
let probe = MainActor.assumeIsolated { KickrProbe() }
MainActor.assumeIsolated { probe.start() }
RunLoop.main.run()
