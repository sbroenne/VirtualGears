import CoreBluetooth
import Foundation
import UIKit
import VirtualShiftCore

struct FTMSProbeEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let event: String
    let characteristic: String?
    let rawHex: String?
    let meaning: String

    init(
        event: String,
        characteristic: CBUUID? = nil,
        data: Data? = nil,
        meaning: String
    ) {
        id = UUID()
        timestamp = Date()
        self.event = event
        self.characteristic = characteristic?.uuidString
        rawHex = data?.map { String(format: "%02X", $0) }.joined(separator: " ")
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
final class RealVeloProbeManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth..."
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var hasControl = false
    @Published private(set) var entries: [FTMSProbeEntry] = []
    @Published var speedKilometersPerHour = 30.0
    @Published var cadenceRPM = 90.0
    @Published var powerWatts = 200

    private let serviceUUID = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let resistanceRangeUUID = CBUUID(
        string: FTMSUUID.supportedResistanceLevelRange
    )
    private let powerRangeUUID = CBUUID(string: FTMSUUID.supportedPowerRange)
    private let controlPointUUID = CBUUID(
        string: FTMSUUID.fitnessMachineControlPoint
    )
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)

    private var peripheral: CBPeripheralManager!
    private var featureCharacteristic: CBMutableCharacteristic!
    private var bikeDataCharacteristic: CBMutableCharacteristic!
    private var resistanceRangeCharacteristic: CBMutableCharacteristic!
    private var powerRangeCharacteristic: CBMutableCharacteristic!
    private var controlPointCharacteristic: CBMutableCharacteristic!
    private var statusCharacteristic: CBMutableCharacteristic!
    private var ownershipByCentral: [UUID: FTMSControlOwnership] = [:]
    private var subscriptions: Set<String> = []
    private var timer: Timer?
    private var startRequested = false
    private var servicePublished = false

    private struct PendingUpdate {
        let characteristic: CBMutableCharacteristic
        let data: Data
        let meaning: String
        let central: CBCentral?
    }

    private var pendingUpdates: [PendingUpdate] = []

    private lazy var featureData = FitnessMachineFeature(
        machineFeatures: [.cadence, .resistanceLevel, .elapsedTime, .powerMeasurement],
        targetSettingFeatures: [
            .resistanceLevel, .power,
            .indoorBikeSimulationParameters, .wheelCircumference,
        ]
    ).encode()

    private lazy var resistanceRangeData: Data = {
        (try? SupportedResistanceLevelRange(
            minimumTenths: 0,
            maximumTenths: 1_000,
            incrementTenths: 5
        ).encode()) ?? Data()
    }()

    private lazy var powerRangeData: Data = {
        (try? SupportedPowerRange(
            minimumWatts: 0,
            maximumWatts: 2_500,
            incrementWatts: 1
        ).encode()) ?? Data()
    }()

    override init() {
        super.init()
        peripheral = CBPeripheralManager(
            delegate: self,
            queue: .main,
            options: [
                CBPeripheralManagerOptionRestoreIdentifierKey:
                    "com.sbroenne.VirtualShift.HardwareLab.RealVeloProbe"
            ]
        )
        log(event: "probe", meaning: "Independent RealVelo FTMS probe opened")
    }

    func start() {
        guard peripheral.state == .poweredOn else {
            log(event: "error", meaning: "Bluetooth is not powered on")
            return
        }
        guard !isAdvertising, !startRequested else { return }
        startRequested = true
        configureService()
        log(event: "service", meaning: "Publishing deterministic FTMS service")
    }

    func stop() {
        startRequested = false
        timer?.invalidate()
        timer = nil
        peripheral.stopAdvertising()
        peripheral.removeAllServices()
        isAdvertising = false
        servicePublished = false
        subscriptions.removeAll()
        subscriberCount = 0
        ownershipByCentral.removeAll()
        hasControl = false
        pendingUpdates.removeAll()
        log(event: "advertise", meaning: "Stopped FTMS advertising")
    }

    func clearTrace() {
        entries.removeAll()
        log(event: "trace", meaning: "Trace cleared")
    }

    func structuredTrace(realVeloVersion: String, windowsVersion: String) -> String {
        struct Export: Encodable {
            let formatVersion: Int
            let realVeloVersion: String
            let windowsVersion: String
            let iosVersion: String
            let exportedAt: Date
            let events: [FTMSProbeEntry]
        }
        let export = Export(
            formatVersion: 1,
            realVeloVersion: realVeloVersion,
            windowsVersion: windowsVersion,
            iosVersion: UIDevice.current.systemVersion,
            exportedAt: Date(),
            events: entries
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

    private func configureService() {
        featureCharacteristic = CBMutableCharacteristic(
            type: featureUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        bikeDataCharacteristic = CBMutableCharacteristic(
            type: bikeDataUUID,
            properties: [.notify],
            value: nil,
            permissions: []
        )
        resistanceRangeCharacteristic = CBMutableCharacteristic(
            type: resistanceRangeUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        powerRangeCharacteristic = CBMutableCharacteristic(
            type: powerRangeUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        controlPointCharacteristic = CBMutableCharacteristic(
            type: controlPointUUID,
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
            resistanceRangeCharacteristic,
            powerRangeCharacteristic,
            controlPointCharacteristic,
            statusCharacteristic,
        ]
        peripheral.add(service)
    }

    private func publishBikeData() {
        guard isAdvertising, isSubscribed(to: bikeDataUUID) else { return }
        let speed = UInt16(
            max(0, min(Double(UInt16.max), speedKilometersPerHour * 100))
        )
        let cadence = UInt16(max(0, min(Double(UInt16.max), cadenceRPM * 2)))
        let power = Int16(max(Int(Int16.min), min(Int(Int16.max), powerWatts)))
        let data = IndoorBikeData(
            instantaneousSpeedHundredths: speed,
            instantaneousCadenceHalfRPM: cadence,
            resistanceLevel: 0,
            instantaneousPowerWatts: power
        ).encode()
        let sent = peripheral.updateValue(
            data,
            for: bikeDataCharacteristic,
            onSubscribedCentrals: nil
        )
        log(
            event: sent ? "notify" : "back-pressure",
            characteristic: bikeDataUUID,
            data: data,
            meaning: "speed \(speedKilometersPerHour.formatted()) km/h, cadence \(cadenceRPM.formatted()) rpm, power \(powerWatts) W"
        )
    }

    private func send(
        _ data: Data,
        characteristic: CBMutableCharacteristic,
        meaning: String,
        central: CBCentral? = nil
    ) {
        guard central != nil || isSubscribed(to: characteristic.uuid) else {
            log(
                event: "notification skipped",
                characteristic: characteristic.uuid,
                data: data,
                meaning: "No subscribed central for \(meaning)"
            )
            return
        }
        guard peripheral.updateValue(
            data,
            for: characteristic,
            onSubscribedCentrals: central.map { [$0] }
        ) else {
            pendingUpdates.append(.init(
                characteristic: characteristic,
                data: data,
                meaning: meaning,
                central: central
            ))
            log(
                event: "back-pressure",
                characteristic: characteristic.uuid,
                data: data,
                meaning: "Queued \(meaning)"
            )
            return
        }
        log(
            event: characteristic == controlPointCharacteristic ? "indicate" : "notify",
            characteristic: characteristic.uuid,
            data: data,
            meaning: meaning
        )
    }

    private func handleControlPoint(_ data: Data, from central: CBCentral) {
        let request: FitnessMachineControlPointRequest
        do {
            request = try .decode(data)
        } catch let FTMSCodecError.unsupportedOpcode(opcode) {
            send(
                FitnessMachineControlPointResponse(
                    requestOpcode: opcode,
                    result: .opcodeNotSupported
                ).encode(),
                characteristic: controlPointCharacteristic,
                meaning: "Opcode 0x\(String(format: "%02X", opcode)) not supported",
                central: central
            )
            return
        } catch {
            let opcode = data.first ?? 0
            send(
                FitnessMachineControlPointResponse(
                    requestOpcode: opcode,
                    result: .invalidParameter
                ).encode(),
                characteristic: controlPointCharacteristic,
                meaning: "Invalid parameters: \(error)",
                central: central
            )
            return
        }

        var ownership = ownershipByCentral[central.identifier]
            ?? FTMSControlOwnership()
        let response = ownership.handle(request)
        if response.result == .success, request == .requestControl {
            for identifier in ownershipByCentral.keys
                where identifier != central.identifier {
                ownershipByCentral[identifier] = FTMSControlOwnership()
            }
        }
        ownershipByCentral[central.identifier] = ownership
        hasControl = ownershipByCentral.values.contains { $0.hasControl }
        log(
            event: "decoded",
            characteristic: controlPointUUID,
            data: data,
            meaning: String(describing: request)
        )
        send(
            response.encode(),
            characteristic: controlPointCharacteristic,
            meaning: "\(request) -> \(response.result)",
            central: central
        )
        guard response.result == .success,
              let status = status(for: request) else { return }
        send(
            status.encode(),
            characteristic: statusCharacteristic,
            meaning: String(describing: status)
        )
    }

    private func status(
        for request: FitnessMachineControlPointRequest
    ) -> FitnessMachineStatus? {
        switch request {
        case .requestControl:
            nil
        case .reset:
            .reset
        case let .setTargetResistanceLevel(tenths):
            .targetResistanceLevelChanged(tenths: tenths)
        case let .setTargetPower(watts):
            .targetPowerChanged(watts: watts)
        case .startOrResume:
            .startedOrResumed
        case let .stopOrPause(action):
            .stoppedOrPaused(action)
        case let .setIndoorBikeSimulationParameters(parameters):
            .indoorBikeSimulationParametersChanged(parameters)
        case let .setWheelCircumference(circumference):
            .wheelCircumferenceChanged(tenthsOfMillimeter: circumference)
        }
    }

    private func value(for uuid: CBUUID) -> Data? {
        switch uuid {
        case featureUUID: featureData
        case resistanceRangeUUID: resistanceRangeData
        case powerRangeUUID: powerRangeData
        default: nil
        }
    }

    private func isSubscribed(to uuid: CBUUID) -> Bool {
        let suffix = "|\(uuid.uuidString)"
        return subscriptions.contains { $0.hasSuffix(suffix) }
    }

    private func isSubscribed(_ central: CBCentral, to uuid: CBUUID) -> Bool {
        subscriptions.contains(
            "\(central.identifier.uuidString)|\(uuid.uuidString)"
        )
    }

    private func log(
        event: String,
        characteristic: CBUUID? = nil,
        data: Data? = nil,
        meaning: String
    ) {
        entries.append(.init(
            event: event,
            characteristic: characteristic,
            data: data,
            meaning: meaning
        ))
        if entries.count > 2_000 {
            entries.removeFirst(entries.count - 2_000)
        }
    }
}

extension RealVeloProbeManager: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            bluetoothState = "Powered on"
        case .poweredOff:
            bluetoothState = "Powered off"
            stop()
        case .unauthorized:
            bluetoothState = "Not authorized"
        case .unsupported:
            bluetoothState = "Unsupported"
        case .resetting:
            bluetoothState = "Resetting"
        case .unknown:
            bluetoothState = "Unknown"
        @unknown default:
            bluetoothState = "Unknown future state"
        }
        log(event: "bluetooth", meaning: bluetoothState)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        servicePublished = error == nil
        log(
            event: error == nil ? "service" : "error",
            characteristic: service.uuid,
            meaning: error?.localizedDescription ?? "FTMS service published"
        )
        if error != nil {
            startRequested = false
        }
        guard error == nil, startRequested else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "VirtualShift Lab",
        ])
    }

    func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: Error?
    ) {
        isAdvertising = error == nil
        log(
            event: error == nil ? "advertise" : "error",
            meaning: error?.localizedDescription ?? "FTMS advertising active"
        )
        guard error == nil else {
            startRequested = false
            return
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.publishBikeData() }
        }
        publishBikeData()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        guard servicePublished else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        guard let value = value(for: request.characteristic.uuid) else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            log(
                event: "read rejected",
                characteristic: request.characteristic.uuid,
                meaning: "Characteristic is not readable"
            )
            return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset..<value.count)
        peripheral.respond(to: request, withResult: .success)
        log(
            event: "read",
            characteristic: request.characteristic.uuid,
            data: value,
            meaning: "Returned \(value.count) bytes at offset \(request.offset)"
        )
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        guard let first = requests.first else { return }
        guard servicePublished else {
            peripheral.respond(to: first, withResult: .unlikelyError)
            return
        }
        let values = requests.compactMap(\.value)
        guard values.count == requests.count,
              requests.allSatisfy({
                  $0.characteristic.uuid == controlPointUUID
              }) else {
            peripheral.respond(to: first, withResult: .writeNotPermitted)
            return
        }
        guard requests.allSatisfy({
            isSubscribed($0.central, to: controlPointUUID)
        }) else {
            peripheral.respond(
                to: first,
                withResult: .unlikelyError
            )
            log(
                event: "write rejected",
                characteristic: controlPointUUID,
                meaning: "Control Point indications are not subscribed"
            )
            return
        }
        peripheral.respond(to: first, withResult: .success)
        for (request, data) in zip(requests, values) {
            log(
                event: "write",
                characteristic: controlPointUUID,
                data: data,
                meaning: "Control Point request received"
            )
            handleControlPoint(data, from: request.central)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscriptions.insert(
            "\(central.identifier.uuidString)|\(characteristic.uuid.uuidString)"
        )
        subscriberCount = subscriptions.count
        if characteristic.uuid == controlPointUUID {
            var ownership = ownershipByCentral[central.identifier]
                ?? FTMSControlOwnership()
            ownership.setControlPointSubscribed(true)
            ownershipByCentral[central.identifier] = ownership
        }
        log(
            event: "subscribe",
            characteristic: characteristic.uuid,
            meaning: "Central \(central.identifier.uuidString), MTU \(central.maximumUpdateValueLength)"
        )
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscriptions.remove(
            "\(central.identifier.uuidString)|\(characteristic.uuid.uuidString)"
        )
        subscriberCount = subscriptions.count
        if characteristic.uuid == controlPointUUID {
            ownershipByCentral.removeValue(forKey: central.identifier)
            hasControl = ownershipByCentral.values.contains { $0.hasControl }
        }
        log(
            event: "unsubscribe",
            characteristic: characteristic.uuid,
            meaning: "Central \(central.identifier.uuidString)"
        )
    }

    func peripheralManagerIsReady(
        toUpdateSubscribers peripheral: CBPeripheralManager
    ) {
        log(event: "ready", meaning: "CoreBluetooth queue can accept updates")
        while let pending = pendingUpdates.first {
            guard peripheral.updateValue(
                pending.data,
                for: pending.characteristic,
                onSubscribedCentrals: pending.central.map { [$0] }
            ) else { return }
            pendingUpdates.removeFirst()
            log(
                event: "dequeued",
                characteristic: pending.characteristic.uuid,
                data: pending.data,
                meaning: pending.meaning
            )
        }
    }
}
