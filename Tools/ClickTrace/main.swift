import CoreBluetooth
import Foundation
import ToolSupport
import VirtualGearsCore

/// Everything is written to a file as well as to the console.
///
/// macOS will only give Bluetooth to a signed program that declares why it
/// wants it, and it judges that by the program that *started* the process. Run
/// from a terminal, the terminal is judged, and it does not declare Bluetooth,
/// so the tool is killed the moment it asks. Launching the bundle with `open`
/// makes the tool answer for itself, but then there is no console left to print
/// to. Hence the file.
let log = ToolLog(
    environmentKey: "CLICK_TRACE_LOG",
    defaultPath: "/tmp/click-trace.log"
)
let logPath = log.path

func say(_ text: String) {
    log.say(text)
}

/// Connects to an original Zwift Click and prints every packet it sends, with
/// the time since the previous one.
///
/// This exists because button behaviour cannot be reasoned about from the app's
/// own logs: by the time a shift is logged, the raw press and release have
/// already been interpreted. Here nothing is interpreted. What the Click
/// actually sends is what gets printed.
///
/// Run it with the iPhone app closed. The Click accepts one connection at a
/// time, so the phone and the Mac cannot both hold it.
final class ClickTrace: NSObject {
    private var central: CBCentralManager!
    private var click: CBPeripheral?
    private var receive: CBCharacteristic?
    private var subscribed = Set<CBUUID>()
    private var handshakeSent = false
    private var started = Date()
    private var lastPacket: Date?
    private var lastState: (plus: Bool, minus: Bool)?
    private var pressedAt: [String: Date] = [:]

    private let service = CBUUID(string: ZwiftClickProtocol.serviceUUID)
    private let asyncUUID = CBUUID(string: ZwiftClickProtocol.asyncCharacteristicUUID)
    private let receiveUUID = CBUUID(string: ZwiftClickProtocol.syncReceiveCharacteristicUUID)
    private let transmitUUID = CBUUID(string: ZwiftClickProtocol.syncTransmitCharacteristicUUID)
    // Read so the standard battery reading can be compared against the
    // unexplained value the Click sends every five seconds.
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryUUID = CBUUID(string: "2A19")

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func stamp() -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(started)
        let gap = lastPacket.map { now.timeIntervalSince($0) }
        lastPacket = now
        let gapText = gap.map { String(format: "+%6.0f ms", $0 * 1000) }
            ?? "         -"
        return String(format: "%7.3fs %@", elapsed, gapText)
    }

    fileprivate func note(_ text: String) {
        say("\(stamp())  \(text)")
    }
}

extension ClickTrace: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            say("Scanning for a Zwift Click. Wake it by pressing a button.")
            central.scanForPeripherals(withServices: [service])
        case .unauthorized:
            say("""
            Bluetooth permission was refused.

            Grant it to whichever program is running this, in
            System Settings > Privacy & Security > Bluetooth, then run it again.
            """)
            exit(1)
        case .poweredOff:
            say("Bluetooth is switched off on this Mac.")
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
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name ?? "Zwift Click"
        say("Found \(name) at \(RSSI) dBm. Connecting.")
        central.stopScan()
        click = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([service, batteryServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        say("\nThe Click disconnected. \(error?.localizedDescription ?? "")")
        exit(0)
    }
}

extension ClickTrace: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services,
              services.contains(where: { $0.uuid == service }) else {
            say("This device has no Zwift Click service.")
            exit(1)
        }
        for found in services {
            if found.uuid == service {
                peripheral.discoverCharacteristics(
                    [asyncUUID, receiveUUID, transmitUUID],
                    for: found
                )
            } else {
                peripheral.discoverCharacteristics([batteryUUID], for: found)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case receiveUUID:
                receive = characteristic
            case asyncUUID, transmitUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case batteryUUID:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.isNotifying else { return }
        subscribed.insert(characteristic.uuid)
        guard subscribed.contains(asyncUUID),
              subscribed.contains(transmitUUID),
              !handshakeSent,
              let receive else { return }
        handshakeSent = true
        let type: CBCharacteristicWriteType =
            receive.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(ZwiftClickProtocol.rideOn, for: receive, type: type)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == batteryUUID {
            say("Standard Bluetooth battery reading: \(data.first.map(Int.init) ?? -1)%")
            return
        }
        if characteristic.uuid == transmitUUID {
            started = Date()
            lastPacket = nil
            say("""

            Connected. Every packet from the Click is printed below.

            Do this, pausing a second between each:
              1. One firm press of + , exactly as you would on the bike.
              2. Three quick taps of + .
              3. Press and hold + for about two seconds.

            Press Control-C when you are done.

            """)
            say("   time    since last  packet")
            say("   ----    ----------  ------")
            return
        }
        guard characteristic.uuid == asyncUUID else { return }

        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        do {
            switch try ZwiftClickMessageDecoder.decode(data) {
            case let .buttons(plus, minus):
                var changes: [String] = []
                let previous = lastState ?? (plus: false, minus: false)
                for (name, was, now) in [
                    ("+", previous.plus, plus),
                    ("-", previous.minus, minus),
                ] where was != now {
                    if now {
                        pressedAt[name] = Date()
                        changes.append("\(name) PRESSED")
                    } else {
                        let held = pressedAt[name].map {
                            String(
                                format: " after %.0f ms",
                                Date().timeIntervalSince($0) * 1000
                            )
                        } ?? ""
                        changes.append("\(name) RELEASED\(held)")
                    }
                }
                lastState = (plus: plus, minus: minus)
                let summary = changes.isEmpty
                    ? "buttons unchanged (+:\(plus ? 1 : 0) -:\(minus ? 1 : 0))"
                    : changes.joined(separator: ", ")
                note("\(summary)   [\(hex)]")
            case let .batteryLevel(percent):
                note("battery \(percent)%   [\(hex)]")
            case .keepAlive:
                note("keep-alive   [\(hex)]")
            case let .other(type):
                note("other message type 0x\(String(type, radix: 16))   [\(hex)]")
            }
        } catch {
            note("undecodable   [\(hex)]")
        }
    }
}

// Printed as it happens, so a trace stays useful if the tool is stopped
// partway through.
setvbuf(stdout, nil, _IONBF, 0)

let trace = ClickTrace()
trace.start()
RunLoop.main.run()
