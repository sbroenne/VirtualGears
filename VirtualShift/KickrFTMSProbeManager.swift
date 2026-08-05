import CoreBluetooth
import Foundation
import UIKit
import VirtualShiftCore

struct KickrFTMSCandidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

struct KickrFTMSCharacteristicRecord: Identifiable, Codable {
    var id: String { uuid }
    let uuid: String
    var properties: String
    var rawHex: String?
    var decodedValue: String?
}

struct KickrFTMSProbeEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let event: String
    let characteristic: String?
    let rawHex: String?
    let meaning: String

    init(
        event: String,
        characteristic: String?,
        rawHex: String?,
        meaning: String
    ) {
        id = UUID()
        timestamp = Date()
        self.event = event
        self.characteristic = characteristic
        self.rawHex = rawHex
        self.meaning = meaning
    }

    var displayText: String {
        let time = timestamp.formatted(date: .omitted, time: .standard)
        let uuid = characteristic.map { " \($0)" } ?? ""
        let raw = rawHex.map { " [\($0)]" } ?? ""
        return "\(time) \(event)\(uuid)\(raw): \(meaning)"
    }
}

@MainActor
final class KickrFTMSProbeManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth..."
    @Published private(set) var connectionState = "Not connected"
    @Published private(set) var candidates: [KickrFTMSCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasControl = false
    @Published private(set) var isReadyForControl = false
    @Published private(set) var characteristicRecords: [KickrFTMSCharacteristicRecord] = []
    @Published private(set) var recentEvents: [KickrFTMSProbeEvent] = []
    @Published private(set) var eventCount = 0

    private let ftmsServiceUUID = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let resistanceRangeUUID = CBUUID(string: FTMSUUID.supportedResistanceLevelRange)
    private let powerRangeUUID = CBUUID(string: FTMSUUID.supportedPowerRange)
    private let controlPointUUID = CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)
    private let wahooControlUUID = CBUUID(string: WahooKickrProtocol.controlCharacteristicUUID)
    private lazy var requiredUUIDs: Set<CBUUID> = [
        featureUUID, bikeDataUUID, resistanceRangeUUID, powerRangeUUID,
        controlPointUUID, statusUUID,
    ]

    private var central: CBCentralManager!
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectingPeripheral: CBPeripheral?
    private var connectedPeripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var discoveredServices = 0
    private var processedServices = 0
    private var fullEvents: [KickrFTMSProbeEvent] = []
    private let recentEventLimit = 40
    private let fullEventLimit = 2_000
    private var tracePeripheralName: String?
    private var tracePeripheralIdentifier: String?

    private struct PendingCommand {
        let id = UUID()
        let request: FitnessMachineControlPointRequest
        let name: String
    }

    private var commandQueue: [PendingCommand] = []
    private var activeCommand: PendingCommand?
    private var activeWriteConfirmed = false
    private var activeResponse: FitnessMachineControlPointResponse?

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        log("probe", meaning: "Native KICKR FTMS Hardware Lab probe opened")
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            log("error", meaning: "Bluetooth is not powered on")
            return
        }
        guard !isConnected, !isConnecting else { return }
        candidates.removeAll()
        discoveredPeripherals.removeAll()
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        log("scan", meaning: "Scanning for KICKR devices")
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        log("scan", meaning: "Scan stopped")
    }

    func connect(to id: UUID) {
        guard !isConnected, !isConnecting,
              let peripheral = discoveredPeripherals[id] else { return }
        stopScanning()
        fullEvents.removeAll()
        recentEvents.removeAll()
        eventCount = 0
        resetConnectionState()
        tracePeripheralName = peripheral.name
        tracePeripheralIdentifier = peripheral.identifier.uuidString
        connectingPeripheral = peripheral
        isConnecting = true
        connectionState = "Connecting to \(peripheral.name ?? "KICKR")..."
        peripheral.delegate = self
        central.connect(peripheral)
        log("connect", meaning: "Connecting to \(peripheral.name ?? id.uuidString)")
    }

    func disconnect(reason: String = "Disconnect requested") {
        stopScanning()
        if let peripheral = connectedPeripheral ?? connectingPeripheral {
            log("disconnect", meaning: reason)
            central.cancelPeripheralConnection(peripheral)
            resetConnectionState()
            connectionState = "Not connected"
        } else {
            resetConnectionState()
            connectionState = "Not connected"
        }
    }

    func requestControl() {
        enqueue(.requestControl, name: "Request Control")
    }

    func startOrResume() {
        guard hasControl else { return }
        enqueue(.startOrResume, name: "Start / Resume")
    }

    func stop() {
        guard hasControl else { return }
        enqueue(.stopOrPause(.stop), name: "Stop")
    }

    func clearTrace() {
        fullEvents.removeAll()
        recentEvents.removeAll()
        eventCount = 0
        log("trace", meaning: "Trace cleared")
    }

    func structuredTrace() -> String {
        struct Export: Encodable {
            let formatVersion: Int
            let exportedAt: Date
            let iosVersion: String
            let peripheralName: String?
            let peripheralIdentifier: String?
            let characteristics: [KickrFTMSCharacteristicRecord]
            let events: [KickrFTMSProbeEvent]
        }
        let export = Export(
            formatVersion: 1,
            exportedAt: Date(),
            iosVersion: UIDevice.current.systemVersion,
            peripheralName: tracePeripheralName,
            peripheralIdentifier: tracePeripheralIdentifier,
            characteristics: characteristicRecords,
            events: fullEvents
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Trace encoding failed\"}"
        }
        return text
    }

    private func enqueue(
        _ request: FitnessMachineControlPointRequest,
        name: String
    ) {
        guard isReadyForControl else {
            log("error", characteristic: controlPointUUID, meaning: "Control Point is not ready")
            return
        }
        commandQueue.append(.init(request: request, name: name))
        processNextCommand()
    }

    private func processNextCommand() {
        guard activeCommand == nil, !commandQueue.isEmpty,
              let peripheral = connectedPeripheral,
              let characteristic = characteristics[controlPointUUID] else {
            isBusy = activeCommand != nil || !commandQueue.isEmpty
            return
        }
        let command = commandQueue.removeFirst()
        let data: Data
        do {
            data = try command.request.encode()
        } catch {
            log("error", characteristic: controlPointUUID, meaning: "\(command.name): \(error)")
            processNextCommand()
            return
        }
        activeCommand = command
        activeWriteConfirmed = false
        activeResponse = nil
        isBusy = true
        log("write", characteristic: controlPointUUID, data: data, meaning: command.name)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        scheduleTimeout(for: command)
    }

    private func scheduleTimeout(for command: PendingCommand) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.activeCommand?.id == command.id else { return }
            self.failActive("\(command.name) timed out waiting for a matching response")
        }
    }

    private func handleControlPoint(_ data: Data) {
        let response: FitnessMachineControlPointResponse
        do {
            response = try .decode(data)
        } catch {
            log("decode error", characteristic: controlPointUUID, data: data, meaning: "\(error)")
            return
        }
        log(
            "indication",
            characteristic: controlPointUUID,
            data: data,
            meaning: "response to 0x\(String(format: "%02X", response.requestOpcode)): \(response.result)"
        )
        guard let command = activeCommand else {
            log("unmatched response", characteristic: controlPointUUID, data: data, meaning: "No command is active")
            return
        }
        guard response.requestOpcode == command.request.opcode else {
            failActive(
                "\(command.name) received response for opcode 0x"
                    + String(format: "%02X", response.requestOpcode)
            )
            return
        }
        activeResponse = response
        if activeWriteConfirmed {
            completeActive()
        }
    }

    private func completeActive() {
        guard let command = activeCommand, let response = activeResponse else { return }
        activeCommand = nil
        activeResponse = nil
        activeWriteConfirmed = false
        isBusy = false
        if response.result == .success {
            if command.request == .requestControl {
                hasControl = true
            }
            log("verified", characteristic: controlPointUUID, meaning: "\(command.name): success")
        } else {
            if command.request == .requestControl
                || response.result == .controlNotPermitted {
                hasControl = false
            }
            log("rejected", characteristic: controlPointUUID, meaning: "\(command.name): \(response.result)")
        }
        processNextCommand()
    }

    private func failActive(_ message: String) {
        activeCommand = nil
        activeResponse = nil
        activeWriteConfirmed = false
        commandQueue.removeAll()
        isBusy = false
        log("error", characteristic: controlPointUUID, meaning: message)
    }

    private func finishDiscoveryIfNeeded() {
        guard discoveredServices > 0, processedServices == discoveredServices else { return }
        let missing = requiredUUIDs.subtracting(characteristics.keys)
        if missing.isEmpty {
            connectionState = "FTMS discovered"
        } else {
            connectionState = "FTMS incomplete"
            log(
                "missing",
                meaning: missing.map(\.uuidString).sorted().joined(separator: ", ")
            )
        }
        for uuid in [featureUUID, resistanceRangeUUID, powerRangeUUID] {
            if let characteristic = characteristics[uuid],
               characteristic.properties.contains(.read) {
                connectedPeripheral?.readValue(for: characteristic)
            }
        }
        for uuid in [bikeDataUUID, statusUUID, controlPointUUID] {
            if let characteristic = characteristics[uuid],
               characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) {
                connectedPeripheral?.setNotifyValue(true, for: characteristic)
            }
        }
        updateControlReadiness()
    }

    private func updateControlReadiness() {
        guard let control = characteristics[controlPointUUID] else {
            isReadyForControl = false
            return
        }
        isReadyForControl =
            control.isNotifying
            && control.properties.contains(.write)
            && control.properties.contains(.indicate)
    }

    private func recordDiscovery(_ characteristic: CBCharacteristic) {
        let record = KickrFTMSCharacteristicRecord(
            uuid: characteristic.uuid.uuidString,
            properties: propertiesDescription(characteristic.properties),
            rawHex: nil,
            decodedValue: "Discovered"
        )
        updateRecord(record)
        log(
            characteristic.uuid == wahooControlUUID ? "Wahoo control discovered" : "characteristic",
            characteristic: characteristic.uuid,
            meaning: record.properties
        )
    }

    private func recordValue(_ data: Data, for characteristic: CBCharacteristic) {
        let decoded = decode(data, uuid: characteristic.uuid)
        updateRecord(.init(
            uuid: characteristic.uuid.uuidString,
            properties: propertiesDescription(characteristic.properties),
            rawHex: hex(data),
            decodedValue: decoded
        ))
        log(
            characteristic.uuid == bikeDataUUID ? "notification"
                : characteristic.uuid == statusUUID ? "notification" : "read",
            characteristic: characteristic.uuid,
            data: data,
            meaning: decoded
        )
    }

    private func updateRecord(_ record: KickrFTMSCharacteristicRecord) {
        if let index = characteristicRecords.firstIndex(where: { $0.uuid == record.uuid }) {
            characteristicRecords[index] = record
        } else {
            characteristicRecords.append(record)
            characteristicRecords.sort { $0.uuid < $1.uuid }
        }
    }

    private func decode(_ data: Data, uuid: CBUUID) -> String {
        do {
            switch uuid {
            case featureUUID:
                let value = try FitnessMachineFeature.decode(data)
                return String(
                    format: "machine 0x%08X, targets 0x%08X",
                    value.machineFeatures.rawValue,
                    value.targetSettingFeatures.rawValue
                )
            case resistanceRangeUUID:
                let value = try SupportedResistanceLevelRange.decode(data)
                return "min \(value.minimum), max \(value.maximum), increment \(value.increment)"
            case powerRangeUUID:
                let value = try SupportedPowerRange.decode(data)
                return "min \(value.minimumWatts) W, max \(value.maximumWatts) W, increment \(value.incrementWatts) W"
            case bikeDataUUID:
                let value = try IndoorBikeData.decode(data)
                return [
                    value.instantaneousSpeedKilometersPerHour.map { "speed \($0) km/h" },
                    value.instantaneousCadenceRPM.map { "cadence \($0) rpm" },
                    value.resistanceLevel.map { "resistance \($0)" },
                    value.instantaneousPowerWatts.map { "power \($0) W" },
                    value.heartRateBPM.map { "heart rate \($0) bpm" },
                    value.elapsedTimeSeconds.map { "elapsed \($0) s" },
                ].compactMap { $0 }.joined(separator: ", ")
            case statusUUID:
                let value = try FitnessMachineStatus.decode(data)
                if case .controlPermissionLost = value {
                    hasControl = false
                }
                return String(describing: value)
            case controlPointUUID:
                return String(describing: try FitnessMachineControlPointResponse.decode(data))
            default:
                return "Raw value"
            }
        } catch {
            return "Decode error: \(error)"
        }
    }

    private func resetConnectionState() {
        connectingPeripheral = nil
        connectedPeripheral = nil
        characteristics.removeAll()
        characteristicRecords.removeAll()
        discoveredServices = 0
        processedServices = 0
        commandQueue.removeAll()
        activeCommand = nil
        activeResponse = nil
        activeWriteConfirmed = false
        isConnecting = false
        isConnected = false
        isBusy = false
        hasControl = false
        isReadyForControl = false
    }

    private func propertiesDescription(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("signedWrite") }
        if properties.contains(.extendedProperties) { names.append("extended") }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func log(
        _ event: String,
        characteristic: CBUUID? = nil,
        data: Data? = nil,
        meaning: String
    ) {
        let entry = KickrFTMSProbeEvent(
            event: event,
            characteristic: characteristic?.uuidString,
            rawHex: data.map(hex),
            meaning: meaning
        )
        fullEvents.append(entry)
        if fullEvents.count > fullEventLimit {
            fullEvents.removeFirst(fullEvents.count - fullEventLimit)
        }
        recentEvents.append(entry)
        if recentEvents.count > recentEventLimit {
            recentEvents.removeFirst(recentEvents.count - recentEventLimit)
        }
        eventCount = fullEvents.count
    }
}

extension KickrFTMSProbeManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state.description
        log("bluetooth", meaning: bluetoothState)
        if central.state != .poweredOn {
            disconnect(reason: "Bluetooth is no longer powered on")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed device"
        guard name.localizedCaseInsensitiveContains("KICKR") else { return }
        discoveredPeripherals[peripheral.identifier] = peripheral
        let candidate = KickrFTMSCandidate(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index] = candidate
        } else {
            candidates.append(candidate)
            log("scan result", meaning: "\(name), \(RSSI) dBm")
        }
        candidates.sort { $0.rssi > $1.rssi }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard connectingPeripheral?.identifier == peripheral.identifier else {
            log(
                "stale callback",
                meaning: "Ignored connection from \(peripheral.identifier)"
            )
            central.cancelPeripheralConnection(peripheral)
            return
        }
        connectingPeripheral = nil
        connectedPeripheral = peripheral
        isConnecting = false
        isConnected = true
        connectionState = "Discovering services..."
        log("connected", meaning: peripheral.name ?? peripheral.identifier.uuidString)
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard connectingPeripheral?.identifier == peripheral.identifier else {
            return
        }
        resetConnectionState()
        connectionState = "Connection failed"
        log("error", meaning: error?.localizedDescription ?? "Connection failed")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard connectedPeripheral?.identifier == peripheral.identifier
                || connectingPeripheral?.identifier == peripheral.identifier else {
            return
        }
        resetConnectionState()
        connectionState = error == nil ? "Not connected" : "Connection lost"
        log(
            "disconnected",
            meaning: error?.localizedDescription ?? "Peripheral disconnected"
        )
    }
}

extension KickrFTMSProbeManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil, let services = peripheral.services else {
            connectionState = "Service discovery failed"
            log("error", meaning: error?.localizedDescription ?? "No services returned")
            return
        }
        discoveredServices = services.count
        processedServices = 0
        log(
            "services",
            meaning: services.map(\.uuid.uuidString).joined(separator: ", ")
        )
        if services.isEmpty {
            connectionState = "No services discovered"
        }
        for service in services {
            if service.uuid == ftmsServiceUUID {
                peripheral.discoverCharacteristics(Array(requiredUUIDs), for: service)
            } else {
                peripheral.discoverCharacteristics([wahooControlUUID], for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        processedServices += 1
        if let error {
            log("error", characteristic: service.uuid, meaning: error.localizedDescription)
        }
        for characteristic in service.characteristics ?? [] {
            if requiredUUIDs.contains(characteristic.uuid)
                || characteristic.uuid == wahooControlUUID {
                characteristics[characteristic.uuid] = characteristic
                recordDiscovery(characteristic)
            }
        }
        finishDiscoveryIfNeeded()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        log(
            error == nil ? "subscription" : "subscription error",
            characteristic: characteristic.uuid,
            meaning: error?.localizedDescription
                ?? (characteristic.isNotifying ? "Enabled" : "Disabled")
        )
        updateControlReadiness()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value, error == nil else {
            log(
                "value error",
                characteristic: characteristic.uuid,
                meaning: error?.localizedDescription ?? "No value"
            )
            return
        }
        if characteristic.uuid == controlPointUUID {
            handleControlPoint(data)
            updateRecord(.init(
                uuid: characteristic.uuid.uuidString,
                properties: propertiesDescription(characteristic.properties),
                rawHex: hex(data),
                decodedValue: decode(data, uuid: characteristic.uuid)
            ))
        } else {
            recordValue(data, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == controlPointUUID,
              let command = activeCommand else { return }
        if let error {
            failActive("\(command.name) write failed: \(error.localizedDescription)")
            return
        }
        activeWriteConfirmed = true
        log("write confirmed", characteristic: characteristic.uuid, meaning: command.name)
        if activeResponse != nil {
            completeActive()
        }
    }
}
