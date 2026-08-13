import CoreBluetooth
import Foundation
import ToolSupport
import VirtualGearsCore

// A riding app picks a trainer out of a list of names. Virtual Gears asks to be
// called "Virtual Gears", but a rider reported seeing their iPhone's own name
// instead. A name can reach a riding app by two different routes, and this tool
// reads both so the two can be told apart:
//
//   1. The local name inside the advertisement, which is what CoreBluetooth is
//      asked to broadcast and what a scanner sees before connecting.
//   2. The Device Name characteristic (0x2A00), read after connecting. On iOS
//      this is the name of the phone itself and an app cannot change it.
//
// If the advertisement says "Virtual Gears" but the riding app shows the phone's
// name, the app is reading the second one and no change to advertising fixes it.

let log = ToolLog(
    environmentKey: "NAME_SCAN_LOG",
    defaultPath: "/tmp/name-scan.log"
)
let logPath = log.path

func say(_ message: String) {
    log.say(message)
}

@MainActor
final class NameScan: NSObject {
    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var advertisedName: String?
    private var reported = false

    private let deviceNameUUID = CBUUID(string: "2A00")
    private let genericAccessUUID = CBUUID(string: "1800")
    private let deviceInfoUUID = CBUUID(string: "180A")
    private let modelNumberUUID = CBUUID(string: "2A24")
    private let manufacturerUUID = CBUUID(string: "2A29")

    /// Only look at things claiming to be a fitness machine, which is what a
    /// riding app scans for.
    private let ftmsService = CBUUID(string: FTMSUUID.fitnessMachineService)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func describe(_ data: [String: Any]) -> String {
        var parts: [String] = []
        if let name = data[CBAdvertisementDataLocalNameKey] as? String {
            parts.append("local name \"\(name)\"")
        } else {
            parts.append("no local name")
        }
        if let services = data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            parts.append(
                "services \(services.map(\.uuidString).joined(separator: ", "))"
            )
        }
        if let overflow =
            data[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID],
            !overflow.isEmpty
        {
            // iOS hides service UUIDs here when the advertising app is in the
            // background, and drops the local name entirely at the same time.
            parts.append(
                "overflow services "
                    + overflow.map(\.uuidString).joined(separator: ", ")
                    + " (the advertiser is in the background)"
            )
        }
        return parts.joined(separator: "; ")
    }

    func finish() {
        guard !reported else { return }
        reported = true
        say("")
        say("What this means")
        switch advertisedName {
        case let name? where name == "Virtual Gears":
            say(
                "  The advertisement carries \"Virtual Gears\" correctly. A"
                    + " riding app showing the phone's own name instead is"
                    + " reading the connected name (0x2A00), which iOS fixes to"
                    + " the name of the phone. An app cannot change that;"
                    + " renaming the iPhone is the only cure."
            )
        case let name?:
            say("  The advertisement carries \"\(name)\", which was not expected.")
        case nil:
            say(
                "  No local name was advertised at all. Either Virtual Gears was"
                    + " in the background when it started advertising, or the"
                    + " name was never set."
            )
        }
        exit(0)
    }

    func scheduleReport() {
        scheduleMainActorTimeout(after: .seconds(4)) {
            self.finish()
        }
    }
}

extension NameScan: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        say("Looking for anything advertising as a fitness machine.")
        say("Start a ride in Virtual Gears so that it begins advertising.")
        central.scanForPeripherals(withServices: [ftmsService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard target == nil else { return }
        let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        // A real KICKR is a fitness machine too. Skip it: this is about what
        // the phone broadcasts.
        let candidate = local ?? peripheral.name ?? ""
        if TrainerModel.isKickr(advertisedName: candidate) {
            say("Ignoring \(candidate), which is the trainer itself.")
            return
        }
        advertisedName = local
        say("")
        say("Found a fitness machine at \(RSSI) dBm.")
        say("  In the advertisement: \(describe(advertisementData))")
        say("  CBPeripheral.name reads: \(peripheral.name ?? "nothing")")
        central.stopScan()
        target = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        say("  Connected. Reading the names it reports once connected.")
        peripheral.discoverServices([
            genericAccessUUID, deviceInfoUUID, ftmsService,
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        say("  Could not connect: \(error?.localizedDescription ?? "unknown")")
        finish()
    }
}

extension NameScan: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let found = peripheral.services ?? []
        say(
            "  Services offered: "
                + found.map(\.uuid.uuidString).joined(separator: ", ")
        )
        if !found.contains(where: { $0.uuid == genericAccessUUID }) {
            // macOS keeps 0x1800 to itself. Say so, rather than looking like
            // the phone failed to publish it.
            say(
                "  Note: macOS does not hand the Generic Access service (0x1800)"
                    + " to apps, so the connected-name check may come up empty"
                    + " here even though a Windows or Android riding app can"
                    + " read it."
            )
        }
        for service in found {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        scheduleReport()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let wanted = [deviceNameUUID, modelNumberUUID, manufacturerUUID]
        for characteristic in service.characteristics ?? []
        where wanted.contains(characteristic.uuid) {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value,
            let text = String(data: data, encoding: .utf8)
        else { return }
        switch characteristic.uuid {
        case deviceNameUUID:
            say("  Device Name (0x2A00) reads: \"\(text)\"")
        case modelNumberUUID:
            say("  Model Number (0x2A24) reads: \"\(text)\"")
        case manufacturerUUID:
            say("  Manufacturer (0x2A29) reads: \"\(text)\"")
        default:
            break
        }
    }
}

let scan = NameScan()
say("name-scan starting.")
RunLoop.main.run()
