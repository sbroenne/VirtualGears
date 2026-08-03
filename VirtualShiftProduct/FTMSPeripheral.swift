import CoreBluetooth
import Foundation
import Observation
import VirtualShiftCore

enum FTMSPeripheralEvent: Equatable, Sendable {
    case advertisingStarted
    case advertisingStopped
    case centralSubscribed(UUID, characteristic: String)
    case centralUnsubscribed(UUID, characteristic: String)
    case controlRequest(UUID, FitnessMachineControlPointRequest)
    case controlResponse(UUID, FitnessMachineControlPointResponse)
    case failed(String)
}

struct FTMSPeripheralCommandResult: Sendable {
    let result: FTMSControlPointResult
    let status: FitnessMachineStatus?

    static func success(
        status: FitnessMachineStatus? = nil
    ) -> Self {
        .init(result: .success, status: status)
    }
}

@MainActor
@Observable
final class FTMSPeripheral: NSObject {
    private(set) var isAdvertising = false
    private(set) var activeCentralID: UUID?
    private(set) var latestEvent: FTMSPeripheralEvent?
    var commandHandler: ((
        FitnessMachineControlPointRequest,
        UUID
    ) async -> FTMSPeripheralCommandResult)?

    private let diagnostics: ProductDiagnosticsStore
    private let serviceUUID = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let resistanceUUID = CBUUID(
        string: FTMSUUID.supportedResistanceLevelRange
    )
    private let powerUUID = CBUUID(string: FTMSUUID.supportedPowerRange)
    private let controlUUID = CBUUID(
        string: FTMSUUID.fitnessMachineControlPoint
    )
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)

    private var manager: CBPeripheralManager!
    private var featureCharacteristic: CBMutableCharacteristic!
    private var bikeDataCharacteristic: CBMutableCharacteristic!
    private var resistanceCharacteristic: CBMutableCharacteristic!
    private var powerCharacteristic: CBMutableCharacteristic!
    private var controlCharacteristic: CBMutableCharacteristic!
    private var statusCharacteristic: CBMutableCharacteristic!
    private var startRequested = false
    private var servicePublished = false
    private var acceptingCommands = false
    private var subscriptions: [UUID: Set<CBUUID>] = [:]
    private var centrals: [UUID: CBCentral] = [:]
    private var controlOwnerID: UUID?

    private struct ControlCommand {
        let request: FitnessMachineControlPointRequest
        let centralID: UUID
    }

    private struct Update {
        let data: Data
        let characteristic: CBMutableCharacteristic
        let centralID: UUID?
    }

    private var commands: [ControlCommand] = []
    private var processingCommand = false
    private var updates: [Update] = []

    @ObservationIgnored
    private lazy var featureData = FitnessMachineFeature(
        machineFeatures: [
            .cadence, .resistanceLevel, .elapsedTime, .powerMeasurement,
        ],
        targetSettingFeatures: [
            .resistanceLevel, .power,
            .indoorBikeSimulationParameters, .wheelCircumference,
        ]
    ).encode()

    @ObservationIgnored
    private lazy var resistanceData = try! SupportedResistanceLevelRange(
        minimumTenths: 0,
        maximumTenths: 1_000,
        incrementTenths: 5
    ).encode()

    @ObservationIgnored
    private lazy var powerData = try! SupportedPowerRange(
        minimumWatts: 0,
        maximumWatts: 2_500,
        incrementWatts: 1
    ).encode()

    init(diagnostics: ProductDiagnosticsStore) {
        self.diagnostics = diagnostics
        super.init()
        // Intentionally foreground-only. Supplying a restoration identifier without
        // reconstructing services in willRestoreState can crash during relaunch.
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising() {
        guard manager.state == .poweredOn else {
            fail("Bluetooth peripheral mode is unavailable")
            return
        }
        guard !startRequested, !isAdvertising else { return }
        startRequested = true
        acceptingCommands = true
        if servicePublished {
            advertise()
        } else {
            publishService()
        }
    }

    func stopAcceptingCommands() {
        acceptingCommands = false
        let rejected = commands
        commands.removeAll()
        for command in rejected {
            let response = FitnessMachineControlPointResponse(
                requestOpcode: command.request.opcode,
                result: .operationFailed
            )
            send(response.encode(), on: controlCharacteristic, to: command.centralID)
            emit(.controlResponse(command.centralID, response))
        }
    }

    func stopAdvertising() {
        startRequested = false
        acceptingCommands = false
        commands.removeAll()
        processingCommand = false
        updates.removeAll()
        manager.stopAdvertising()
        manager.removeAllServices()
        servicePublished = false
        isAdvertising = false
        subscriptions.removeAll()
        centrals.removeAll()
        activeCentralID = nil
        controlOwnerID = nil
        emit(.advertisingStopped)
    }

    func relayIndoorBikeData(_ data: Data) {
        guard let activeCentralID,
              subscriptions[activeCentralID]?.contains(bikeDataUUID) == true
        else { return }
        send(data, on: bikeDataCharacteristic, to: activeCentralID)
    }

    func notifyControlLost() {
        guard controlOwnerID != nil else { return }
        controlOwnerID = nil
        send(
            FitnessMachineStatus.controlPermissionLost.encode(),
            on: statusCharacteristic,
            to: activeCentralID
        )
    }

    private func publishService() {
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
        resistanceCharacteristic = CBMutableCharacteristic(
            type: resistanceUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        powerCharacteristic = CBMutableCharacteristic(
            type: powerUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
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
            featureCharacteristic, bikeDataCharacteristic,
            resistanceCharacteristic, powerCharacteristic,
            controlCharacteristic, statusCharacteristic,
        ]
        manager.add(service)
    }

    private func advertise() {
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "VirtualShift",
        ])
    }

    private func enqueue(
        _ request: FitnessMachineControlPointRequest,
        from centralID: UUID
    ) {
        commands.append(.init(request: request, centralID: centralID))
        processNextCommand()
    }

    private func processNextCommand() {
        guard !processingCommand, !commands.isEmpty else { return }
        processingCommand = true
        let command = commands.removeFirst()
        Task { [weak self] in
            guard let self else { return }
            let result = await self.execute(command)
            self.finish(command, result: result)
        }
    }

    private func execute(
        _ command: ControlCommand
    ) async -> FTMSPeripheralCommandResult {
        let request = command.request
        let centralID = command.centralID
        emit(.controlRequest(centralID, request))
        guard acceptingCommands else {
            return .init(result: .operationFailed, status: nil)
        }
        guard activeCentralID == centralID,
              subscriptions[centralID]?.contains(controlUUID) == true else {
            return .init(result: .controlNotPermitted, status: nil)
        }
        if request != .requestControl, controlOwnerID != centralID {
            return .init(result: .controlNotPermitted, status: nil)
        }
        guard let commandHandler else {
            return .init(result: .operationFailed, status: nil)
        }
        return await commandHandler(request, centralID)
    }

    private func finish(
        _ command: ControlCommand,
        result: FTMSPeripheralCommandResult
    ) {
        if result.result == .success {
            if command.request == .requestControl {
                controlOwnerID = command.centralID
            } else if command.request == .reset {
                controlOwnerID = nil
            }
        }
        let response = FitnessMachineControlPointResponse(
            requestOpcode: command.request.opcode,
            result: result.result
        )
        send(response.encode(), on: controlCharacteristic, to: command.centralID)
        if let status = result.status, result.result == .success {
            send(status.encode(), on: statusCharacteristic, to: command.centralID)
        }
        emit(.controlResponse(command.centralID, response))
        processingCommand = false
        processNextCommand()
    }

    private func send(
        _ data: Data,
        on characteristic: CBMutableCharacteristic,
        to centralID: UUID?
    ) {
        if !updates.isEmpty {
            let update = Update(
                data: data,
                characteristic: characteristic,
                centralID: centralID
            )
            if characteristic.uuid == bikeDataUUID {
                updates.removeAll {
                    $0.characteristic.uuid == bikeDataUUID
                        && $0.centralID == centralID
                }
                updates.append(update)
            } else if let firstTelemetry = updates.firstIndex(where: {
                $0.characteristic.uuid == bikeDataUUID
            }) {
                updates.insert(update, at: firstTelemetry)
            } else {
                updates.append(update)
            }
            return
        }
        let central = centralID.flatMap { centrals[$0] }
        if centralID != nil, central == nil { return }
        guard manager.updateValue(
            data,
            for: characteristic,
            onSubscribedCentrals: central.map { [$0] }
        ) else {
            updates.append(.init(
                data: data,
                characteristic: characteristic,
                centralID: centralID
            ))
            return
        }
    }

    private func flushUpdates() {
        while let update = updates.first {
            let central = update.centralID.flatMap { centrals[$0] }
            if update.centralID != nil, central == nil {
                updates.removeFirst()
                continue
            }
            guard manager.updateValue(
                update.data,
                for: update.characteristic,
                onSubscribedCentrals: central.map { [$0] }
            ) else { return }
            updates.removeFirst()
        }
    }

    private func readValue(for uuid: CBUUID) -> Data? {
        switch uuid {
        case featureUUID: featureData
        case resistanceUUID: resistanceData
        case powerUUID: powerData
        default: nil
        }
    }

    private func emit(_ event: FTMSPeripheralEvent) {
        latestEvent = event
        diagnostics.record(String(describing: event), source: "FTMS Peripheral")
    }

    private func fail(_ message: String) {
        emit(.failed(message))
        diagnostics.record(message, source: "FTMS Peripheral", level: .error)
    }
}

extension FTMSPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != .poweredOn {
            if isAdvertising || startRequested { stopAdvertising() }
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            startRequested = false
            fail(error!.localizedDescription)
            return
        }
        servicePublished = true
        if startRequested { advertise() }
    }

    func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: Error?
    ) {
        guard error == nil else {
            startRequested = false
            fail(error!.localizedDescription)
            return
        }
        isAdvertising = true
        emit(.advertisingStarted)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        guard let value = readValue(for: request.characteristic.uuid) else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            return
        }
        guard request.offset >= 0, request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset..<value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        let result: CBATTError.Code
        if requests.count != 1 {
            result = .requestNotSupported
        } else if let request = requests.first,
                  request.characteristic.uuid == controlUUID,
                  request.offset == 0,
                  let data = request.value {
            let id = request.central.identifier
            if subscriptions[id]?.contains(controlUUID) != true {
                result = .writeNotPermitted
            } else {
                do {
                    let decoded = try FitnessMachineControlPointRequest.decode(data)
                    result = .success
                    enqueue(decoded, from: id)
                } catch let FTMSCodecError.unsupportedOpcode(opcode) {
                    result = .success
                    let response = FitnessMachineControlPointResponse(
                        requestOpcode: opcode,
                        result: .opcodeNotSupported
                    )
                    send(response.encode(), on: controlCharacteristic, to: id)
                } catch {
                    result = .success
                    let response = FitnessMachineControlPointResponse(
                        requestOpcode: data.first ?? 0,
                        result: .invalidParameter
                    )
                    send(response.encode(), on: controlCharacteristic, to: id)
                }
            }
        } else {
            result = .writeNotPermitted
        }
        for request in requests {
            peripheral.respond(to: request, withResult: result)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        centrals[central.identifier] = central
        subscriptions[central.identifier, default: []].insert(characteristic.uuid)
        if characteristic.uuid == controlUUID, activeCentralID == nil {
            activeCentralID = central.identifier
        }
        emit(.centralSubscribed(
            central.identifier,
            characteristic: characteristic.uuid.uuidString
        ))
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscriptions[central.identifier]?.remove(characteristic.uuid)
        if characteristic.uuid == controlUUID,
           activeCentralID == central.identifier {
            activeCentralID = nil
            controlOwnerID = nil
            activeCentralID = subscriptions
                .filter { $0.value.contains(controlUUID) }
                .map(\.key)
                .sorted { $0.uuidString < $1.uuidString }
                .first
        }
        if subscriptions[central.identifier]?.isEmpty == true {
            subscriptions.removeValue(forKey: central.identifier)
            centrals.removeValue(forKey: central.identifier)
        }
        emit(.centralUnsubscribed(
            central.identifier,
            characteristic: characteristic.uuid.uuidString
        ))
    }

    func peripheralManagerIsReady(
        toUpdateSubscribers peripheral: CBPeripheralManager
    ) {
        flushUpdates()
    }
}
