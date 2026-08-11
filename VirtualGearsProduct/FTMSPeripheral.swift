import CoreBluetooth
import Foundation
import Observation
import VirtualGearsCore

@MainActor
@Observable
final class FTMSPeripheral: NSObject {
    private(set) var isAdvertising = false
    /// Every app that has asked for ride data. A riding app is counted here as
    /// soon as it subscribes, whether or not it also asks to steer the trainer.
    private(set) var subscribedAppCount = 0
    /// The app that currently steers the trainer, if any.
    private(set) var controllingAppID: UUID?
    private(set) var latestEvent: FTMSPeripheralEvent?
    var commandHandler: ((
        FitnessMachineControlPointRequest,
        RidingAppCommandSource
    ) async -> FTMSPeripheralCommandResult)?

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

    private var manager: CBPeripheralManager!
    private var featureCharacteristic: CBMutableCharacteristic!
    private var bikeDataCharacteristic: CBMutableCharacteristic!
    private var resistanceCharacteristic: CBMutableCharacteristic!
    private var controlCharacteristic: CBMutableCharacteristic!
    private var powerRangeCharacteristic: CBMutableCharacteristic!
    private var statusCharacteristic: CBMutableCharacteristic!
    private var startRequested = false
    /// Whether a ride still wants the phone advertising as a trainer. Kept
    /// separate from `startRequested` so a Bluetooth reset can tear the service
    /// down and put it back, while a deliberate stop stays stopped.
    private var wantsAdvertising = false
    private var servicePublished = false
    private var acceptingCommands = false
    private var subscriptions: [UUID: Set<CBUUID>] = [:]
    private var controlSubscriptionIDs: [UUID: UUID] = [:]
    private var centrals: [UUID: CBCentral] = [:]
    private var controlOwnerID: UUID?

    private struct ControlCommand {
        let request: FitnessMachineControlPointRequest
        let source: RidingAppCommandSource
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
    private lazy var featureData = VirtualTrainerFTMSProfile.feature.encode()

    @ObservationIgnored
    @ObservationIgnored
    private lazy var powerRangeData =
        VirtualTrainerFTMSProfile.powerRange.encode()

    @ObservationIgnored
    private lazy var resistanceData = try! SupportedResistanceLevelRange(
        minimumTenths: 0,
        maximumTenths: 1_000,
        incrementTenths: 5
    ).encode()

    override init() {
        super.init()
        // Intentionally foreground-only. Supplying a restoration identifier without
        // reconstructing services in willRestoreState can crash during relaunch.
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising() {
        // A failure left over from an earlier attempt must not be read as this
        // one's verdict, or a perfectly good ride start aborts on stale news.
        latestEvent = nil
        // Set before the guard below, not after. A ride that asks to advertise
        // while the Bluetooth stack happens to be resetting used to have the
        // request dropped for good, because the recovery in
        // `peripheralManagerDidUpdateState` keys off exactly this flag.
        wantsAdvertising = true
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
            let centralID = command.source.centralID
            let response = FitnessMachineControlPointResponse(
                requestOpcode: command.request.opcode,
                result: .operationFailed
            )
            send(response.encode(), on: controlCharacteristic, to: centralID)
            emit(.controlResponse(centralID, response))
        }
    }

    func stopAdvertising() {
        wantsAdvertising = false
        teardownAdvertising()
    }

    /// The teardown itself, without disturbing whether a ride still wants to be
    /// advertising. A Bluetooth reset uses this so `.poweredOn` can restore it.
    private func teardownAdvertising() {
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
        controlSubscriptionIDs.removeAll()
        centrals.removeAll()
        subscribedAppCount = 0
        controlOwnerID = nil
        controllingAppID = nil
        emit(.advertisingStopped)
    }

    func isControlSubscriber(_ source: RidingAppCommandSource) -> Bool {
        subscriptions[source.centralID]?.contains(controlUUID) == true
            && controlSubscriptionIDs[source.centralID] == source.subscriptionID
    }

    /// Whether a control claim still belongs to a riding app that is actually
    /// here. A dropped link does not reliably produce an unsubscribe, so this is
    /// what tells a live claim apart from the ghost of a finished one.
    private func isLiveControlSubscriber(_ centralID: UUID) -> Bool {
        centrals[centralID] != nil
            && subscriptions[centralID]?.contains(controlUUID) == true
    }

    /// Sent to every subscribed app. A riding app that only reads ride data,
    /// without ever asking to steer, still gets the full stream.
    func relayIndoorBikeData(_ data: Data) {
        for id in subscribers(of: bikeDataUUID) {
            send(data, on: bikeDataCharacteristic, to: id)
        }
    }

    func notifyControlLost() {
        guard let owner = controlOwnerID else { return }
        controlOwnerID = nil
        controllingAppID = nil
        send(
            FitnessMachineStatus.controlPermissionLost.encode(),
            on: statusCharacteristic,
            to: owner
        )
    }

    private func subscribers(of characteristic: CBUUID) -> [UUID] {
        subscriptions.filter { $0.value.contains(characteristic) }.map(\.key)
    }

    private func refreshSubscribedAppCount() {
        subscribedAppCount = subscriptions.count { !$0.value.isEmpty }
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
        controlCharacteristic = CBMutableCharacteristic(
            type: controlUUID,
            properties: [.write, .indicate],
            value: nil,
            permissions: [.writeable]
        )
        powerRangeCharacteristic = CBMutableCharacteristic(
            type: powerRangeUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
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
            resistanceCharacteristic, powerRangeCharacteristic,
            controlCharacteristic, statusCharacteristic,
        ]
        manager.add(service)
    }

    private func advertise() {
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "Virtual Gears",
        ])
    }

    private func enqueue(
        _ request: FitnessMachineControlPointRequest,
        from source: RidingAppCommandSource
    ) {
        commands.append(.init(request: request, source: source))
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
        let centralID = command.source.centralID
        emit(.controlRequest(centralID, request))
        let decision = FTMSControlOwnership.decide(
            FTMSControlRequest(
                request: request,
                requesterID: centralID,
                ownerID: controlOwnerID,
                ownerIsPresent: controlOwnerID.map(isLiveControlSubscriber) ?? false,
                requesterSubscriptionIsCurrent: isControlSubscriber(command.source),
                requesterIsSubscribed: subscriptions[centralID]?
                    .contains(controlUUID) == true,
                isAcceptingCommands: acceptingCommands
            )
        )
        if case let .refuse(result) = decision {
            return .init(result: result, status: nil)
        }
        guard let commandHandler else {
            return .init(result: .operationFailed, status: nil)
        }
        return await commandHandler(request, command.source)
    }

    private func finish(
        _ command: ControlCommand,
        result: FTMSPeripheralCommandResult
    ) {
        guard isControlSubscriber(command.source) else {
            processingCommand = false
            processNextCommand()
            return
        }
        let centralID = command.source.centralID
        controlOwnerID = FTMSControlOwnership.owner(
            after: command.request,
            result: result.result,
            currentOwner: controlOwnerID,
            requesterID: centralID
        )
        if result.result == .success {
            controllingAppID = controlOwnerID
        }
        let response = FitnessMachineControlPointResponse(
            requestOpcode: command.request.opcode,
            result: result.result
        )
        send(response.encode(), on: controlCharacteristic, to: centralID)
        if let status = result.status, result.result == .success {
            send(status.encode(), on: statusCharacteristic, to: centralID)
        }
        emit(.controlResponse(centralID, response))
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
        case powerRangeUUID: powerRangeData
        default: nil
        }
    }

    private func emit(_ event: FTMSPeripheralEvent) {
        latestEvent = event
        ProductLogger.record(String(describing: event), source: "FTMS Peripheral")
    }

    private func fail(_ message: String) {
        emit(.failed(message))
        ProductLogger.record(message, source: "FTMS Peripheral", level: .error)
    }
}

#if DEBUG
extension FTMSPeripheral {
    func stageScreenshotConnection() {
        isAdvertising = true
        subscribedAppCount = 1
        controllingAppID = ScreenshotFixture.ridingAppID
    }
}
#endif

extension FTMSPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            // iOS restarts the BLE stack on its own. Without this the riding
            // app loses the trainer for the rest of the ride.
            if wantsAdvertising, !isAdvertising, !startRequested {
                startAdvertising()
            }
        } else if isAdvertising || startRequested {
            teardownAdvertising()
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
                    if let subscriptionID = controlSubscriptionIDs[id] {
                        result = .success
                        enqueue(
                            decoded,
                            from: .init(
                                centralID: id,
                                subscriptionID: subscriptionID
                            )
                        )
                    } else {
                        result = .writeNotPermitted
                    }
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
        if characteristic.uuid == controlUUID {
            controlSubscriptionIDs[central.identifier] = UUID()
        }
        refreshSubscribedAppCount()
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
        // An app that drops the control channel gives up control with it, so a
        // later riding app is never locked out by a stale claim.
        if characteristic.uuid == controlUUID,
           controlOwnerID == central.identifier {
            controlOwnerID = nil
            controllingAppID = nil
        }
        if characteristic.uuid == controlUUID {
            controlSubscriptionIDs.removeValue(forKey: central.identifier)
        }
        if subscriptions[central.identifier]?.isEmpty == true {
            subscriptions.removeValue(forKey: central.identifier)
            centrals.removeValue(forKey: central.identifier)
        }
        refreshSubscribedAppCount()
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
