import CoreBluetooth
import Foundation
import VirtualShiftCore

struct ClickCandidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

@MainActor
final class ClickBluetoothManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothStatus = "Starting Bluetooth..."
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var candidates: [ClickCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var gear = 6
    @Published private(set) var lastShift = "No shift yet"
    @Published private(set) var entries: [DiagnosticEntry] = []

    let gearRange = 1...12

    private let serviceUUID = CBUUID(string: ZwiftClickProtocol.serviceUUID)
    private let asyncUUID = CBUUID(
        string: ZwiftClickProtocol.asyncCharacteristicUUID
    )
    private let syncReceiveUUID = CBUUID(
        string: ZwiftClickProtocol.syncReceiveCharacteristicUUID
    )
    private let syncTransmitUUID = CBUUID(
        string: ZwiftClickProtocol.syncTransmitCharacteristicUUID
    )
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var asyncCharacteristic: CBCharacteristic?
    private var syncReceiveCharacteristic: CBCharacteristic?
    private var syncTransmitCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var asyncSubscribed = false
    private var syncTransmitSubscribed = false
    private var handshakeSent = false
    private var handshakeWriteType: CBCharacteristicWriteType?
    private var edgeTracker = ZwiftClickEdgeTracker()
    private var heldButton: ZwiftClickButton?
    private var repeatTask: Task<Void, Never>?
    private let soundPlayer = ShiftSoundPlayer()

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        log("Independent Click proof started")
    }

    var diagnosticText: String {
        entries.map(\.text).joined(separator: "\n")
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            reportError("Bluetooth is not ready")
            return
        }
        guard !isConnected && !isConnecting else {
            reportError("Disconnect the current Click first")
            return
        }

        candidates = []
        peripherals = [:]
        central.scanForPeripherals(withServices: [serviceUUID])
        isScanning = true
        connectionStatus = "Scanning for original Zwift Click..."
        log("Scanning for service \(serviceUUID.uuidString)")
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        log("Click scan stopped")
    }

    func connect(to id: UUID) {
        guard let candidate = peripherals[id] else {
            reportError("The selected Click is no longer available")
            return
        }
        guard !isConnected && !isConnecting else { return }

        stopScanning()
        peripheral = candidate
        candidate.delegate = self
        isConnecting = true
        connectionStatus = "Connecting to \(candidate.name ?? "Zwift Click")..."
        central.connect(candidate)
        log("Connecting to \(candidate.name ?? id.uuidString)")
    }

    func disconnect() {
        if isScanning {
            stopScanning()
        }
        stopRepeat()
        isReady = false
        guard let peripheral else {
            connectionStatus = "Not connected"
            return
        }
        connectionStatus = "Disconnecting Click..."
        central.cancelPeripheralConnection(peripheral)
    }

    func resetGear() {
        gear = 6
        lastShift = "Reset to gear 6"
        log("Gear display reset to 6")
    }

    private func subscribeIfReady() {
        guard asyncSubscribed,
              syncTransmitSubscribed,
              !handshakeSent,
              let peripheral,
              let syncReceiveCharacteristic,
              let handshakeWriteType
        else { return }

        handshakeSent = true
        let mode = handshakeWriteType == .withoutResponse
            ? "without response"
            : "with response"
        log("Writing Click RideOn handshake \(mode)")
        peripheral.writeValue(
            ZwiftClickProtocol.rideOn,
            for: syncReceiveCharacteristic,
            type: handshakeWriteType
        )
        if handshakeWriteType == .withoutResponse {
            log("Click handshake sent; waiting for reply")
        }
    }

    private func processAsyncMessage(_ data: Data) {
        do {
            switch try ZwiftClickMessageDecoder.decode(data) {
            case let .buttons(plusPressed, minusPressed):
                if plusPressed && minusPressed {
                    _ = edgeTracker.update(plus: true, minus: true)
                    stopRepeat()
                    log("Ignored ambiguous press of both Click buttons")
                    return
                }

                let events = edgeTracker.update(
                    plus: plusPressed,
                    minus: minusPressed
                )
                for event in events {
                    process(event)
                }
            case let .batteryLevel(percent):
                // The Click repeats this every few seconds, which is the only
                // way the reading stays current: the standard Bluetooth battery
                // characteristic is readable once on connect and this device
                // does not announce changes to it.
                if batteryLevel != percent {
                    batteryLevel = percent
                    log("Click battery \(percent)%")
                }
            case .keepAlive:
                break
            case let .other(type) where type == 0x19:
                break
            case let .other(type):
                log(
                    "Ignored Click message type 0x"
                        + String(format: "%02X", type)
                )
            }
        } catch {
            reportError("Could not read Click packet \(data.hexString): \(error)")
        }
    }

    private func process(_ event: ZwiftClickButtonEvent) {
        switch event {
        case let .pressed(button):
            guard heldButton == nil else {
                stopRepeat()
                log("Ignored overlapping Click button press")
                return
            }
            heldButton = button
            guard shift(button, kind: .single) else {
                stopRepeat()
                return
            }
            startRepeat(for: button)
        case let .released(button):
            if heldButton == button {
                stopRepeat()
                log("\(button.label) released")
            }
        }
    }

    private func startRepeat(for button: ZwiftClickButton) {
        repeatTask?.cancel()
        repeatTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }

            while !Task.isCancelled, self.heldButton == button {
                guard self.shift(button, kind: .multiple) else {
                    self.stopRepeat()
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        heldButton = nil
    }

    @discardableResult
    private func shift(
        _ button: ZwiftClickButton,
        kind: ShiftSoundPlayer.Kind
    ) -> Bool {
        let requested = gear + (button == .plus ? 1 : -1)
        let next = min(max(requested, gearRange.lowerBound), gearRange.upperBound)
        guard next != gear else {
            log("Ignored \(button.label) at gear \(gear) boundary")
            return false
        }

        gear = next
        let shiftType = kind == .single ? "single" : "multi"
        lastShift = "Gear \(next) - \(shiftType) shift"
        log("\(button.label) changed display to gear \(next) (\(shiftType))")

        do {
            try soundPlayer.play(kind)
        } catch {
            log("ERROR: Could not play shift sound: \(error)")
        }
        return true
    }

    private func resetConnectionState() {
        stopRepeat()
        isConnecting = false
        isConnected = false
        isReady = false
        asyncCharacteristic = nil
        syncReceiveCharacteristic = nil
        syncTransmitCharacteristic = nil
        batteryCharacteristic = nil
        batteryLevel = nil
        asyncSubscribed = false
        syncTransmitSubscribed = false
        handshakeSent = false
        handshakeWriteType = nil
        edgeTracker = ZwiftClickEdgeTracker()
    }

    private func reportError(_ message: String) {
        connectionStatus = "Error"
        log("ERROR: \(message)")
    }

    private func log(_ message: String) {
        entries.append(DiagnosticEntry(date: Date(), message: message))
    }
}

extension ClickBluetoothManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothStatus = central.state.description
        log("Bluetooth state: \(central.state.description)")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName =
            advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed Click"
        guard name.localizedCaseInsensitiveContains("Zwift Click") else {
            return
        }

        peripherals[peripheral.identifier] = peripheral
        let candidate = ClickCandidate(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
        if let index = candidates.firstIndex(where: {
            $0.id == candidate.id
        }) {
            candidates[index] = candidate
        } else {
            candidates.append(candidate)
            log("Found \(name), signal \(RSSI)")
        }
        candidates.sort { $0.rssi > $1.rssi }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        isConnecting = false
        isConnected = true
        connectionStatus = "Discovering Click controls..."
        log("Connected to \(peripheral.name ?? peripheral.identifier.uuidString)")
        peripheral.discoverServices([serviceUUID, batteryServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnectionState()
        self.peripheral = nil
        reportError(
            "Click connection failed: "
                + (error?.localizedDescription ?? "unknown error")
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnectionState()
        self.peripheral = nil
        if let error {
            connectionStatus = "Click connection lost"
            log("Click disconnected with error: \(error.localizedDescription)")
        } else {
            connectionStatus = "Click disconnected"
            log("Click disconnected")
        }
    }
}

extension ClickBluetoothManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            reportError("Click service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == serviceUUID
        }) else {
            reportError("Zwift Accessory service was not found")
            return
        }

        log("Found Zwift Accessory service")
        peripheral.discoverCharacteristics(
            [asyncUUID, syncReceiveUUID, syncTransmitUUID],
            for: service
        )
        if let batteryService = peripheral.services?.first(where: {
            $0.uuid == batteryServiceUUID
        }) {
            peripheral.discoverCharacteristics(
                [batteryLevelUUID],
                for: batteryService
            )
        } else {
            log("Battery service was not found")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            reportError(
                "Click characteristic discovery failed: "
                    + error.localizedDescription
            )
            return
        }
        if service.uuid == batteryServiceUUID {
            guard let battery = service.characteristics?.first(where: {
                $0.uuid == batteryLevelUUID
            }) else {
                log("Battery level control was not found")
                return
            }

            batteryCharacteristic = battery
            log(
                "Found battery level, properties: "
                    + battery.properties.description
            )
            if battery.properties.contains(.read) {
                peripheral.readValue(for: battery)
            }
            if battery.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: battery)
            }
            return
        }
        guard let characteristics = service.characteristics,
              let async = characteristics.first(where: {
                  $0.uuid == asyncUUID
              }),
              let syncReceive = characteristics.first(where: {
                  $0.uuid == syncReceiveUUID
              }),
              let syncTransmit = characteristics.first(where: {
                  $0.uuid == syncTransmitUUID
              })
        else {
            reportError("One or more required Click controls were not found")
            return
        }

        asyncCharacteristic = async
        syncReceiveCharacteristic = syncReceive
        syncTransmitCharacteristic = syncTransmit
        log(
            "Found Click write control, properties: "
                + syncReceive.properties.description
        )
        if syncReceive.properties.contains(.writeWithoutResponse) {
            handshakeWriteType = .withoutResponse
        } else if syncReceive.properties.contains(.write) {
            handshakeWriteType = .withResponse
        } else {
            reportError("The Click handshake control is not writable")
            return
        }
        log("Found all required Click controls")
        peripheral.setNotifyValue(true, for: async)
        peripheral.setNotifyValue(true, for: syncTransmit)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if characteristic.uuid == batteryLevelUUID {
            if let error {
                log(
                    "Battery notification setup failed: "
                        + error.localizedDescription
                )
            } else if characteristic.isNotifying {
                log("Click battery notifications enabled")
            }
            return
        }

        if let error {
            reportError(
                "Click notification setup failed: \(error.localizedDescription)"
            )
            return
        }
        guard characteristic.isNotifying else {
            reportError("Click notification was not enabled")
            return
        }

        if characteristic.uuid == asyncUUID {
            asyncSubscribed = true
            log("Click button notifications enabled")
        } else if characteristic.uuid == syncTransmitUUID {
            syncTransmitSubscribed = true
            log("Click handshake replies enabled")
        }
        subscribeIfReady()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == syncReceiveUUID else { return }
        if let error {
            reportError("Click handshake write failed: \(error.localizedDescription)")
        } else {
            log("Click handshake write confirmed; waiting for reply")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            if characteristic.uuid == batteryLevelUUID {
                log("Battery read failed: \(error.localizedDescription)")
            } else {
                reportError(
                    "Click notification failed: \(error.localizedDescription)"
                )
            }
            return
        }
        let data = characteristic.value ?? Data()

        if characteristic.uuid == batteryLevelUUID {
            guard let level = data.first, level <= 100 else {
                log("ERROR: Click returned an invalid battery level")
                return
            }
            batteryLevel = Int(level)
            log("Click battery: \(level)%")
        } else if characteristic.uuid == syncTransmitUUID {
            guard data.starts(with: ZwiftClickProtocol.rideOn) else {
                reportError("Click returned an unexpected handshake reply")
                return
            }
            isReady = true
            connectionStatus = "Click ready - press + or −"
            log("Click RideOn handshake confirmed")
        } else if characteristic.uuid == asyncUUID, isReady {
            processAsyncMessage(data)
        }
    }
}

private extension ZwiftClickButton {
    var label: String {
        switch self {
        case .plus: "Plus"
        case .minus: "Minus"
        }
    }
}
