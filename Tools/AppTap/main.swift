import CoreBluetooth
import Foundation
import ToolSupport
import VirtualGearsCore

// A Mac pretending to be an indoor trainer, so a real riding app can be
// watched without involving the phone, the KICKR, or a bike.
//
// It exists to answer one question the app's design has always assumed the
// answer to: does a riding app set the wheel size, and if it does, does it do
// so once at the start or repeatedly during the ride? Virtual Gears carries a
// good deal of machinery for the repeated case, and nobody has ever seen it
// happen.
//
// The trainer this pretends to be is deliberately the same shape as the one
// the app publishes, down to the declared features, because a riding app
// decides what to send based on what the trainer says it accepts. A simpler
// fake would answer a different question.

let log = ToolLog(
    environmentKey: "APP_TAP_LOG",
    defaultPath: "/tmp/app-tap.log"
)
log.clear()

private func say(_ text: String) { log.say(text) }

private let arguments = CommandLine.arguments
private let advertisedName: String = {
    guard let index = arguments.firstIndex(of: "--name"),
        index + 1 < arguments.count
    else { return "Virtual Gears" }
    return arguments[index + 1]
}()
private let runMinutes: Int = {
    guard let index = arguments.firstIndex(of: "--minutes"),
        index + 1 < arguments.count,
        let value = Int(arguments[index + 1])
    else { return 30 }
    return value
}()
/// Whether to refuse wheel-size commands. A riding app that is told "no" may
/// give up, retry, or carry on regardless, and which of those it does decides
/// whether refusing is a safe thing for the app to do.
private let refuseWheelSize = arguments.contains("--refuse-wheel-size")

@MainActor
final class TrainerTap: NSObject {
    private var manager: CBPeripheralManager!

    private let serviceUUID = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let resistanceUUID = CBUUID(
        string: FTMSUUID.supportedResistanceLevelRange
    )
    private let controlUUID = CBUUID(
        string: FTMSUUID.fitnessMachineControlPoint
    )
    private let powerRangeUUID = CBUUID(string: FTMSUUID.supportedPowerRange)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)

    private var featureCharacteristic: CBMutableCharacteristic!
    private var bikeDataCharacteristic: CBMutableCharacteristic!
    private var resistanceCharacteristic: CBMutableCharacteristic!
    private var controlCharacteristic: CBMutableCharacteristic!
    private var powerRangeCharacteristic: CBMutableCharacteristic!
    private var statusCharacteristic: CBMutableCharacteristic!

    private var published = false
    private var elapsedSeconds: UInt16 = 0
    private var dataTimer: Timer?
    /// Which characteristics each connected app is listening to. Tracked so the
    /// tool can tell that the riding app has gone away and report by itself:
    /// the runner launches it detached, so Ctrl-C in the terminal never reaches
    /// it, and waiting out the whole timeout to read the findings is miserable.
    private var subscriptions: [UUID: Set<CBUUID>] = [:]
    private var farewellTask: Task<Void, Never>?

    /// When the first riding app subscribed. Every command is timed from here,
    /// because "at the start" and "during the ride" is exactly the distinction
    /// this tool exists to draw.
    private var rideStart: Date?
    private var commandCount: [UInt8: Int] = [:]
    private var wheelSizeMoments: [(seconds: TimeInterval, millimetres: Double)] = []
    private var simulationCount = 0
    private var lastSimulationReport = 0

    func start() {
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    private func publish() {
        guard !published else { return }
        published = true

        featureCharacteristic = CBMutableCharacteristic(
            type: featureUUID,
            properties: [.read],
            value: VirtualTrainerFTMSProfile.feature.encode(),
            permissions: [.readable]
        )
        powerRangeCharacteristic = CBMutableCharacteristic(
            type: powerRangeUUID,
            properties: [.read],
            value: VirtualTrainerFTMSProfile.powerRange.encode(),
            permissions: [.readable]
        )
        resistanceCharacteristic = CBMutableCharacteristic(
            type: resistanceUUID,
            properties: [.read],
            value: try! SupportedResistanceLevelRange(
                minimumTenths: 0,
                maximumTenths: 1_000,
                incrementTenths: 5
            ).encode(),
            permissions: [.readable]
        )
        bikeDataCharacteristic = CBMutableCharacteristic(
            type: bikeDataUUID,
            properties: [.notify],
            value: nil,
            permissions: []
        )
        controlCharacteristic = CBMutableCharacteristic(
            type: controlUUID,
            properties: [.write, .indicate],
            value: nil,
            permissions: [.writeable]
        )
        statusCharacteristic = CBMutableCharacteristic(
            type: statusUUID,
            properties: [.notify],
            value: nil,
            permissions: []
        )

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [
            featureCharacteristic,
            bikeDataCharacteristic,
            resistanceCharacteristic,
            controlCharacteristic,
            powerRangeCharacteristic,
            statusCharacteristic,
        ]
        manager.add(service)
    }

    private func advertise() {
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        ])
        say("Pretending to be a trainer called \"\(advertisedName)\".")
        say("Pair this Mac in your riding app, then ride for a few minutes.")
        if refuseWheelSize {
            say("Wheel-size commands will be refused, to see how the app reacts.")
        }
        // Deliberately not "press Ctrl-C": the runner launches this detached, so
        // Ctrl-C in the terminal reaches the runner and never reaches this.
        say("Quit the riding app when you are done and the findings appear here.")
        say("It also stops on its own after \(runMinutes) minutes.")
        say("")
    }

    /// Plausible ride data. A riding app that receives nothing may decide the
    /// trainer is asleep and never get as far as configuring it, which would
    /// look exactly like "it never sends a wheel size".
    private func startSendingRideData() {
        guard dataTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendRideData() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dataTimer = timer
    }

    private func sendRideData() {
        elapsedSeconds &+= 1
        let data = IndoorBikeData(
            instantaneousSpeedHundredths: 3_000,
            instantaneousCadenceHalfRPM: 170,
            resistanceLevel: nil,
            instantaneousPowerWatts: 200,
            heartRateBPM: nil,
            elapsedTimeSeconds: elapsedSeconds
        )
        _ = manager.updateValue(
            data.encode(),
            for: bikeDataCharacteristic,
            onSubscribedCentrals: nil
        )
    }

    private func secondsIntoRide() -> TimeInterval {
        guard let rideStart else { return 0 }
        return Date().timeIntervalSince(rideStart)
    }

    private func stamp() -> String {
        String(format: "%7.1fs", secondsIntoRide())
    }

    fileprivate func record(_ request: FitnessMachineControlPointRequest) {
        commandCount[request.opcode, default: 0] += 1
        let opcode = "0x" + String(format: "%02X", request.opcode)

        switch request {
        case let .setWheelCircumference(tenths):
            let millimetres = Double(tenths) / 10
            wheelSizeMoments.append((secondsIntoRide(), millimetres))
            say(
                "\(stamp())  \(opcode) SET WHEEL SIZE \(millimetres) mm"
                    + "   <- this is the one that matters"
            )
        case .requestControl:
            say("\(stamp())  \(opcode) request control")
        case .reset:
            say("\(stamp())  \(opcode) reset")
        case let .setTargetResistanceLevel(value):
            say("\(stamp())  \(opcode) set resistance \(value)")
        case let .setTargetPower(watts):
            say("\(stamp())  \(opcode) set target power \(watts) W")
        case .startOrResume:
            say("\(stamp())  \(opcode) start or resume")
        case let .stopOrPause(value):
            say("\(stamp())  \(opcode) stop or pause \(value)")
        case .setIndoorBikeSimulationParameters:
            // These arrive several times a second on a hilly course and would
            // bury everything else, so they are counted, not listed.
            simulationCount += 1
            if simulationCount - lastSimulationReport >= 50 {
                lastSimulationReport = simulationCount
                say("\(stamp())  (\(simulationCount) terrain updates so far)")
            }
        }
    }

    fileprivate func reply(to request: FitnessMachineControlPointRequest)
        -> FTMSControlPointResult
    {
        if refuseWheelSize, case .setWheelCircumference = request {
            return .invalidParameter
        }
        return .success
    }

    func report() {
        say("")
        say("=== What the riding app did ===")
        guard rideStart != nil else {
            say("No riding app ever subscribed, so nothing was learned.")
            say("Check the app was searching for a trainer while this ran.")
            return
        }
        say(String(format: "Watched for %.0f seconds.", secondsIntoRide()))
        say("")
        for (opcode, count) in commandCount.sorted(by: { $0.key < $1.key }) {
            let name = "0x" + String(format: "%02X", opcode)
            say("  \(name) sent \(count) time\(count == 1 ? "" : "s")")
        }
        say("")
        if wheelSizeMoments.isEmpty {
            say("The riding app never set a wheel size.")
            say(
                "So the machinery for a wheel size changing mid-ride was not "
                    + "needed here."
            )
            return
        }
        say("Wheel size was set \(wheelSizeMoments.count) time(s):")
        for moment in wheelSizeMoments {
            say(
                String(
                    format: "  at %.1fs into the ride: %.1f mm",
                    moment.seconds,
                    moment.millimetres
                )
            )
        }
        let afterStart = wheelSizeMoments.filter { $0.seconds > 60 }
        say("")
        if afterStart.isEmpty {
            say(
                "All of them arrived in the first minute, so this app sets the "
                    + "wheel size at the start and then leaves it alone."
            )
        } else {
            say(
                "\(afterStart.count) arrived more than a minute in, so this app "
                    + "really does change the wheel size during a ride."
            )
        }
    }
}

extension TrainerTap: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publish()
        case .unauthorized:
            say("macOS has not given this tool permission to use Bluetooth.")
            finish(sentinel: "app-tap finished", code: 1, say: say)
        case .poweredOff:
            say("Bluetooth is switched off.")
        default:
            break
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: (any Error)?
    ) {
        if let error {
            say("Could not publish the trainer: \(error.localizedDescription)")
            finish(sentinel: "app-tap finished", code: 1, say: say)
        }
        advertise()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        if rideStart == nil {
            rideStart = Date()
            say("A riding app connected. Timing starts now.")
        }
        farewellTask?.cancel()
        farewellTask = nil
        subscriptions[central.identifier, default: []].insert(characteristic.uuid)
        if characteristic.uuid == bikeDataUUID {
            startSendingRideData()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscriptions[central.identifier]?.remove(characteristic.uuid)
        if subscriptions[central.identifier]?.isEmpty == true {
            subscriptions[central.identifier] = nil
        }
        guard subscriptions.isEmpty else { return }
        say("\(stamp())  the riding app went away. Reporting shortly.")
        // Not immediately: a riding app that is only changing screens can drop
        // its subscriptions and put them straight back, and reporting on that
        // would end the run in the middle of a ride.
        farewellTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self.report()
            finish(sentinel: "app-tap finished", code: 0, say: say)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            guard request.characteristic.uuid == controlUUID,
                let value = request.value
            else {
                peripheral.respond(to: request, withResult: .success)
                continue
            }
            peripheral.respond(to: request, withResult: .success)

            guard let decoded = try? FitnessMachineControlPointRequest.decode(value)
            else {
                let bytes = value.map { String(format: "%02X", $0) }
                    .joined(separator: " ")
                say("        an unrecognised command arrived: \(bytes)")
                continue
            }
            record(decoded)

            let response = FitnessMachineControlPointResponse(
                requestOpcode: decoded.opcode,
                result: reply(to: decoded)
            )
            _ = manager.updateValue(
                response.encode(),
                for: controlCharacteristic,
                onSubscribedCentrals: nil
            )
        }
    }
}

let tap = TrainerTap()
tap.start()

// Ctrl-C has to be caught rather than left to kill the process, because the
// summary is the entire point of running this and it is only written at the end.
signal(SIGINT, SIG_IGN)
let interrupts = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupts.setEventHandler {
    MainActor.assumeIsolated {
        tap.report()
        finish(sentinel: "app-tap finished", code: 0, say: say)
    }
}
interrupts.resume()

scheduleMainActorTimeout(after: .seconds(runMinutes * 60)) {
    tap.report()
    finish(sentinel: "app-tap finished", code: 0, say: say)
}

RunLoop.main.run()
