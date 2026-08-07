import CoreBluetooth
import Foundation
import Observation
import VirtualGearsCore

@MainActor
@Observable
final class KickrCentralService: NSObject {
    private(set) var state: ProductConnectionState = .unavailable("Starting Bluetooth…") {
        didSet {
            stateHandler?(state)
            updateStallWatch()
        }
    }
    private(set) var candidates: [BluetoothCandidate] = []
    private(set) var scanGeneration = 0
    private(set) var selectedID: UUID?
    private(set) var selectedName: String?
    private(set) var capabilities = KickrCapabilities()
    private(set) var latestBikeData: IndoorBikeData?
    private(set) var latestStatus: FitnessMachineStatus?
    private(set) var latestEvent: KickrEvent?
    private(set) var events: [KickrEvent] = []
    private(set) var hasFTMSControl = false
    var eventHandler: ((KickrEvent) -> Void)?
    var stateHandler: ((ProductConnectionState) -> Void)?

    var isScanning: Bool { state == .scanning }
    var isReady: Bool { state == .ready }

    // CoreBluetooth never times out a connect(), so a device that is asleep
    // leaves the screen spinning forever with no advice. After a few seconds of
    // no progress we say plainly how to wake it up.
    private(set) var connectionIsStalled = false
    private var stallTask: Task<Void, Never>?

    private func updateStallWatch() {
        guard state.isConnectionInProgress else {
            stallTask?.cancel()
            stallTask = nil
            connectionIsStalled = false
            return
        }
        // Keep one timer running across connecting, discovering and preparing so
        // ordinary progress does not reset the clock.
        guard stallTask == nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.connectionIsStalled = true
        }
    }

    private let diagnostics: ProductDiagnosticsStore
    private let defaults: UserDefaults
    private let identityKey = "VirtualGears.kickrIdentity"
    private let timeoutNanoseconds: UInt64 = 5_000_000_000
    private let reconnectDelays: [UInt64] = [1, 2, 4, 8, 15]

    private let ftmsService = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let wahooService = CBUUID(
        string: WahooKickrProtocol.cyclingPowerServiceUUID
    )
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let resistanceUUID = CBUUID(string: FTMSUUID.supportedResistanceLevelRange)
    private let controlUUID = CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)
    private let wahooUUID = CBUUID(string: WahooKickrProtocol.controlCharacteristicUUID)

    private var central: CBCentralManager!
    private var scanWhenPoweredOn = false
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var desiredConnection = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingServiceCount = 0
    private var requiredSubscriptions: Set<CBUUID> = []
    private var subscribed: Set<CBUUID> = []
    private var initialCommandsQueued = false

    private enum CommandKind {
        case ftms(FitnessMachineControlPointRequest)
        case wahoo(data: Data, circumference: Double?)

        var data: Data {
            get throws {
                switch self {
                case let .ftms(request): try request.encode()
                case let .wahoo(data, _): data
                }
            }
        }

        var characteristic: CBUUID {
            switch self {
            case .ftms: CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
            case .wahoo: CBUUID(string: WahooKickrProtocol.controlCharacteristicUUID)
            }
        }
    }

    private struct Command {
        let id = UUID()
        let kind: CommandKind
        let name: String
        let disconnectAfterCompletion: Bool
        let continuation: CheckedContinuation<KickrCommandResult, Error>?
    }

    private var queue: [Command] = []
    private var active: Command?
    private var writeConfirmed = false
    private var indicationConfirmed = false
    private var disconnectOnCommandFailure = false
    private var activeResult: KickrCommandResult?

    init(
        diagnostics: ProductDiagnosticsStore,
        defaults: UserDefaults = .standard
    ) {
        self.diagnostics = diagnostics
        self.defaults = defaults
        super.init()
        loadIdentity()
        // A remembered trainer should reconnect as soon as Bluetooth is ready,
        // without waiting for the rider to tap anything.
        desiredConnection = selectedID != nil
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startScanning() {
        desiredConnection = false
        reconnectTask?.cancel()
        scanWhenPoweredOn = true
        guard central.state == .poweredOn else {
            state = .unavailable(central.state.productDescription)
            return
        }
        beginScanning()
    }

    private func beginScanning() {
        scanGeneration += 1
        scanWhenPoweredOn = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        candidates.removeAll()
        discovered.removeAll()
        // Ask for trainers, rather than being told about every Bluetooth
        // device in the building. A trainer only has to name one of these two
        // to be found: Bluetooth matches any entry in the list, not all of
        // them.
        //
        // A KICKR V5 was measured naming both before anything connected to it,
        // and every riding app finds trainers this same way - which is far
        // better evidence than one measurement, because a trainer that named
        // neither could not be found by Zwift or FulGaz either.
        central.scanForPeripherals(
            withServices: [ftmsService, wahooService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        state = .scanning
        log("Scanning for KICKR trainers")
    }

    func stopScanning(reconnectSavedDevice: Bool = true) {
        scanWhenPoweredOn = false
        central.stopScan()
        if state == .scanning { state = .disconnected }
        if reconnectSavedDevice { autoConnectSavedDevice() }
    }

    var hasSavedDevice: Bool { selectedID != nil }

    var isAutoConnecting: Bool {
        hasSavedDevice && state.isConnectionInProgress
    }

    func autoConnectSavedDevice() {
        guard hasSavedDevice, !isScanning else { return }
        guard peripheral?.state != .connected,
              peripheral?.state != .connecting,
              peripheral?.state != .disconnecting else { return }
        resumeSavedConnection()
    }

    func selectAndConnect(_ id: UUID) {
        guard let peripheral = discovered[id] else {
            fail("Selected trainer is no longer available")
            return
        }
        // Guarded here as well as in the list, so an unsuitable trainer cannot
        // be reached by a saved choice or a future caller either.
        if case let .unsupported(model, reason) = candidates
            .first(where: { $0.id == id })?.compatibility {
            fail("\(model): \(reason)")
            return
        }
        persistIdentity(
            id: id,
            name: candidates.first(where: { $0.id == id })?.name
                ?? peripheral.name ?? "KICKR"
        )
        desiredConnection = true
        reconnectAttempt = 0
        connect(peripheral)
    }

    func resumeSavedConnection() {
        guard let selectedID else { return }
        desiredConnection = true
        if peripheral?.state == .connected
            || peripheral?.state == .connecting {
            return
        }
        // A pending backoff retry would otherwise reconnect underneath this
        // attempt and reset an in-progress discovery.
        reconnectTask?.cancel()
        reconnectAttempt = 0
        retrieveAndConnect(selectedID)
    }

    func forgetSelection() {
        disconnect()
        selectedID = nil
        selectedName = nil
        defaults.removeObject(forKey: identityKey)
    }

    func requestControl() {
        enqueue(.ftms(.requestControl), name: "Request FTMS control")
    }

    func execute(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> FitnessMachineControlPointResponse {
        guard VirtualTrainerFTMSProfile.supports(request) else {
            throw ProductBluetoothError.commandFailed(
                "Target-power control is not supported"
            )
        }
        let result = try await withCheckedThrowingContinuation { continuation in
            enqueue(
                .ftms(request),
                name: "FTMS opcode 0x\(String(format: "%02X", request.opcode))",
                continuation: continuation
            )
        }
        guard case let .ftms(response) = result else {
            throw ProductBluetoothError.commandFailed("Unexpected trainer response")
        }
        return response
    }

    func executeWahoo(_ data: Data) async throws -> WahooKickrResponse {
        let result = try await withCheckedThrowingContinuation { continuation in
            enqueue(
                .wahoo(data: data, circumference: nil),
                name: "Wahoo command 0x\(String(format: "%02X", data.first ?? 0))",
                continuation: continuation
            )
        }
        guard case let .wahoo(response) = result else {
            throw ProductBluetoothError.commandFailed("Unexpected trainer response")
        }
        return response
    }

    func setTargetResistance(tenths: Int16) {
        enqueue(
            .ftms(.setTargetResistanceLevel(tenths: tenths)),
            name: "Set target resistance"
        )
    }

    func setWheelCircumference(millimeters: Double) {
        do {
            let data = try WahooKickrCommand.setWheelCircumference(
                millimeters: millimeters
            )
            enqueue(
                .wahoo(data: data, circumference: millimeters),
                name: "Set wheel circumference"
            )
        } catch {
            commandFailed("Invalid wheel circumference: \(error)")
        }
    }

    func disconnect(
        restoringCircumferenceMillimeters: Double? = nil
    ) {
        desiredConnection = false
        reconnectTask?.cancel()
        central.stopScan()
        guard let peripheral else {
            resetConnection()
            state = .disconnected
            return
        }
        let controlsAreReady = isReady
        let cancellation = ProductBluetoothError.unavailable(
            "Trainer is disconnecting"
        )
        for command in queue {
            command.continuation?.resume(throwing: cancellation)
        }
        queue.removeAll()
        guard let value = restoringCircumferenceMillimeters, controlsAreReady else {
            state = .disconnecting
            central.cancelPeripheralConnection(peripheral)
            return
        }
        do {
            let data = try WahooKickrCommand.setWheelCircumference(
                millimeters: value
            )
            state = .disconnecting
            disconnectOnCommandFailure = true
            enqueue(
                .wahoo(data: data, circumference: value),
                name: "Restore neutral circumference",
                disconnectAfterCompletion: true
            )
        } catch {
            log("Could not restore neutral circumference: \(error)", level: .error)
            state = .disconnecting
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        resetConnection(keepingPeripheral: true)
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting(name: candidateName(for: peripheral))
        central.connect(peripheral)
    }

    private func retrieveAndConnect(_ id: UUID) {
        guard central.state == .poweredOn else { return }
        guard let restored = central.retrievePeripherals(
            withIdentifiers: [id]
        ).first else {
            state = .failed("Your KICKR is not answering")
            scheduleReconnect()
            return
        }
        connect(restored)
    }

    private func scheduleReconnect() {
        guard desiredConnection, central.state == .poweredOn else { return }
        reconnectTask?.cancel()
        let index = min(reconnectAttempt, reconnectDelays.count - 1)
        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)
        let delay = reconnectDelays[index]
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                return
            }
            guard let self, self.desiredConnection, let id = self.selectedID else {
                return
            }
            guard self.peripheral?.state != .connected,
                  self.peripheral?.state != .connecting else { return }
            self.retrieveAndConnect(id)
        }
    }

    private func finishDiscovery() {
        let required = [
            featureUUID, bikeDataUUID, resistanceUUID, controlUUID,
            statusUUID, wahooUUID,
        ]
        let missing = required.filter { characteristics[$0] == nil }
        guard missing.isEmpty else {
            fail("KICKR is missing required controls: "
                + missing.map(\.uuidString).joined(separator: ", "))
            return
        }
        guard characteristics[controlUUID]!.properties.contains(.write),
              characteristics[wahooUUID]!.properties.contains(.write)
        else {
            fail("KICKR control characteristics are not writable")
            return
        }
        capabilities.supportsWahooControl = true

        for uuid in [featureUUID, resistanceUUID] {
            peripheral?.readValue(for: characteristics[uuid]!)
        }
        requiredSubscriptions = [bikeDataUUID, statusUUID, controlUUID, wahooUUID]
        for uuid in requiredSubscriptions {
            let characteristic = characteristics[uuid]!
            guard characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) else {
                fail("\(uuid.uuidString) cannot notify or indicate")
                return
            }
            peripheral?.setNotifyValue(true, for: characteristic)
        }
        state = .preparing
    }

    private func prepareControlIfSubscribed() {
        guard subscribed == requiredSubscriptions, !initialCommandsQueued else {
            return
        }
        initialCommandsQueued = true
        enqueue(.ftms(.requestControl), name: "Request FTMS control")
        enqueue(
            .wahoo(data: WahooKickrCommand.unlock, circumference: nil),
            name: "Unlock Wahoo control"
        )
    }

    private func enqueue(
        _ kind: CommandKind,
        name: String,
        disconnectAfterCompletion: Bool = false,
        continuation: CheckedContinuation<KickrCommandResult, Error>? = nil
    ) {
        guard peripheral?.state == .connected,
              characteristics[kind.characteristic] != nil else {
            commandFailed("\(name): trainer control is unavailable")
            continuation?.resume(throwing: ProductBluetoothError.unavailable(
                "\(name): trainer control is unavailable"
            ))
            return
        }
        queue.append(.init(
            kind: kind,
            name: name,
            disconnectAfterCompletion: disconnectAfterCompletion,
            continuation: continuation
        ))
        processNext()
    }

    private func processNext() {
        guard active == nil, !queue.isEmpty, let peripheral else { return }
        let command = queue.removeFirst()
        guard let characteristic = characteristics[command.kind.characteristic] else {
            command.continuation?.resume(
                throwing: ProductBluetoothError.unavailable(
                    "\(command.name): characteristic disappeared"
                )
            )
            commandFailed("\(command.name): characteristic disappeared")
            processNext()
            return
        }
        do {
            active = command
            activeResult = nil
            writeConfirmed = false
            indicationConfirmed = false
            peripheral.writeValue(
                try command.kind.data,
                for: characteristic,
                type: .withResponse
            )
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 0)
                } catch {
                    return
                }
                guard let self, self.active?.id == command.id else { return }
                self.failActive(
                    "\(command.name) timed out after 5 seconds",
                    forceDisconnect: true
                )
            }
        } catch {
            active = nil
            // Nobody else resumes this one. Without it, whoever is awaiting the
            // command waits for ever and the ride silently stops responding.
            command.continuation?.resume(throwing: error)
            commandFailed("\(command.name): \(error)")
            processNext()
        }
    }

    private func handleFTMSResponse(_ data: Data) {
        do {
            let response = try FitnessMachineControlPointResponse.decode(data)
            emit(.controlResponse(response))
            guard let active,
                  case let .ftms(request) = active.kind,
                  response.requestOpcode == request.opcode else {
                log("Ignored unmatched FTMS indication", level: .warning)
                return
            }
            guard response.result == .success else {
                if request == .requestControl
                    || response.result == .controlNotPermitted {
                    hasFTMSControl = false
                }
                if active.continuation == nil {
                    failActive("\(active.name) was rejected: \(response.result)")
                } else {
                    activeResult = .ftms(response)
                    indicationConfirmed = true
                    completeIfConfirmed()
                }
                return
            }
            if request == .requestControl { hasFTMSControl = true }
            if request == .reset { hasFTMSControl = false }
            activeResult = .ftms(response)
            indicationConfirmed = true
            completeIfConfirmed()
        } catch {
            log("Invalid FTMS control indication: \(error)", level: .error)
        }
    }

    private func handleWahooResponse(_ data: Data) {
        do {
            let response = try WahooKickrResponse.decode(data)
            emit(.wahooResponse(response))
            guard let active,
                  case let .wahoo(commandData, _) = active.kind,
                  response.verifies(command: commandData) else {
                log("Ignored unmatched Wahoo indication", level: .warning)
                return
            }
            guard response.confirmsSuccess(for: commandData) else {
                failActive(
                    "\(active.name) was rejected: \(response.summary)",
                    forceDisconnect: true
                )
                return
            }
            activeResult = .wahoo(response)
            indicationConfirmed = true
            completeIfConfirmed()
        } catch {
            log("Invalid Wahoo indication: \(error)", level: .error)
        }
    }

    private func completeIfConfirmed() {
        guard writeConfirmed, indicationConfirmed, let command = active else {
            return
        }
        timeoutTask?.cancel()
        active = nil
        if let result = activeResult {
            command.continuation?.resume(returning: result)
        } else {
            command.continuation?.resume(throwing:
                ProductBluetoothError.commandFailed("\(command.name): missing response"))
        }
        activeResult = nil
        if initialCommandsQueued, queue.isEmpty {
            state = .ready
        }
        if command.disconnectAfterCompletion, let peripheral {
            disconnectOnCommandFailure = false
            central.cancelPeripheralConnection(peripheral)
        } else {
            processNext()
        }
    }

    private func failActive(
        _ message: String,
        forceDisconnect: Bool = false
    ) {
        timeoutTask?.cancel()
        let shouldDisconnect = forceDisconnect
            || disconnectOnCommandFailure
            || active?.disconnectAfterCompletion == true
        disconnectOnCommandFailure = false
        let failed = active
        active = nil
        activeResult = nil
        let queued = queue
        queue.removeAll()
        let error = ProductBluetoothError.commandFailed(message)
        failed?.continuation?.resume(throwing: error)
        for command in queued {
            command.continuation?.resume(throwing: error)
        }
        commandFailed(message)
        if shouldDisconnect, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func commandFailed(_ message: String) {
        emit(.commandFailed(message))
        log(message, level: .error)
        if state == .preparing {
            state = .failed(message)
            if desiredConnection, let peripheral {
                central.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func resetConnection(keepingPeripheral: Bool = false) {
        timeoutTask?.cancel()
        let error = ProductBluetoothError.unavailable("Trainer disconnected")
        active?.continuation?.resume(throwing: error)
        for command in queue {
            command.continuation?.resume(throwing: error)
        }
        queue.removeAll()
        active = nil
        activeResult = nil
        characteristics.removeAll()
        pendingServiceCount = 0
        requiredSubscriptions.removeAll()
        subscribed.removeAll()
        initialCommandsQueued = false
        disconnectOnCommandFailure = false
        hasFTMSControl = false
        capabilities = .init()
        latestBikeData = nil
        latestStatus = nil
        if !keepingPeripheral { peripheral = nil }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        log(message, level: .error)
        if desiredConnection, let peripheral, peripheral.state == .connected {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func emit(_ event: KickrEvent) {
        latestEvent = event
        events.append(event)
        if events.count > 100 {
            events.removeFirst(events.count - 100)
        }
        eventHandler?(event)
    }

    /// Ride data arrives several times a second for hours. Putting it through
    /// `emit` would fill the 100-entry diagnostic buffer with telemetry in
    /// about ten seconds, throwing away the shift and reconnection entries that
    /// are the whole reason the buffer exists, and would tell SwiftUI something
    /// changed at packet rate. It is handed straight to the listener instead.
    private func relay(_ event: KickrEvent) {
        eventHandler?(event)
    }

    private func candidateName(for peripheral: CBPeripheral) -> String {
        selectedID == peripheral.identifier ? (selectedName ?? peripheral.name ?? "KICKR")
            : (peripheral.name ?? "KICKR")
    }

    private func persistIdentity(id: UUID, name: String) {
        selectedID = id
        selectedName = name
        defaults.set(["id": id.uuidString, "name": name], forKey: identityKey)
    }

    private func loadIdentity() {
        guard let value = defaults.dictionary(forKey: identityKey),
              let idString = value["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        selectedID = id
        selectedName = value["name"] as? String
    }

    private func log(
        _ message: String,
        level: ProductDiagnosticLevel = .info
    ) {
        diagnostics.record(message, source: "KICKR", level: level)
    }
}

extension KickrCentralService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if scanWhenPoweredOn {
                beginScanning()
                return
            }
            state = .disconnected
            if desiredConnection { resumeSavedConnection() }
        } else {
            resetConnection()
            state = .unavailable(central.state.productDescription)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        let advertised = advertisementData[
            CBAdvertisementDataLocalNameKey
        ] as? String
        let name = advertised ?? peripheral.name ?? "Unnamed trainer"
        guard TrainerModel.isKickr(advertisedName: name) else { return }
        discovered[peripheral.identifier] = peripheral
        let item = BluetoothCandidate(
            id: peripheral.identifier,
            name: name,
            compatibility: TrainerModel
                .compatibility(forAdvertisedName: name)
        )
        candidates.absorb(item)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        reconnectAttempt = 0
        state = .discovering
        peripheral.discoverServices([ftmsService, wahooService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        resetConnection()
        log(error?.localizedDescription ?? "Connection failed", level: .error)
        scheduleReconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        resetConnection()
        state = central.isScanning ? .scanning : .disconnected
        if let error { log(error.localizedDescription, level: .warning) }
        if desiredConnection { scheduleReconnect() }
    }
}

extension KickrCentralService: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            fail("Service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            fail("KICKR returned no services")
            return
        }
        pendingServiceCount = services.count
        for service in services {
            if service.uuid == ftmsService {
                peripheral.discoverCharacteristics(
                    [
                        featureUUID, bikeDataUUID, resistanceUUID,
                        controlUUID, statusUUID,
                    ],
                    for: service
                )
            } else if service.uuid == wahooService {
                peripheral.discoverCharacteristics([wahooUUID], for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        pendingServiceCount -= 1
        if let error {
            fail("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }
        if pendingServiceCount == 0 { finishDiscovery() }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            fail("Could not subscribe to \(characteristic.uuid): "
                + error.localizedDescription)
            return
        }
        guard characteristic.isNotifying else {
            fail("\(characteristic.uuid) subscription was disabled")
            return
        }
        subscribed.insert(characteristic.uuid)
        prepareControlIfSubscribed()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let active,
              active.kind.characteristic == characteristic.uuid else { return }
        if let error {
            failActive("\(active.name) write failed: \(error.localizedDescription)")
            return
        }
        writeConfirmed = true
        completeIfConfirmed()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            log("\(characteristic.uuid) update failed: "
                + error.localizedDescription, level: .error)
            return
        }
        guard let data = characteristic.value else {
            log("\(characteristic.uuid) returned no value", level: .error)
            return
        }
        if characteristic.uuid == bikeDataUUID {
            relay(.rawBikeData(data))
        }
        do {
            switch characteristic.uuid {
            case featureUUID:
                capabilities.feature = try .decode(data)
            case resistanceUUID:
                capabilities.resistanceRange = try .decode(data)
            case bikeDataUUID:
                let value = try IndoorBikeData.decode(data)
                latestBikeData = value
                relay(.bikeData(value))
            case statusUUID:
                let value = try FitnessMachineStatus.decode(data)
                latestStatus = value
                emit(.status(value))
                if value == .controlPermissionLost { hasFTMSControl = false }
            case controlUUID:
                handleFTMSResponse(data)
            case wahooUUID:
                capabilities.supportsWahooControl = true
                handleWahooResponse(data)
            default:
                break
            }
        } catch {
            log("Could not decode \(characteristic.uuid): \(error)", level: .error)
        }
    }
}
