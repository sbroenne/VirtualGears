import CoreBluetooth
import Foundation
import Observation
import VirtualGearsCore

@MainActor
@Observable
final class HeadwindCentralService: NSObject {
    private enum DeferredAction {
        case remove
        case scan
    }

    private(set) var state: ProductConnectionState = .unavailable("Starting Bluetooth…") {
        didSet { updateStallWatch() }
    }
    private(set) var candidates: [BluetoothCandidate] = []
    private(set) var scanGeneration = 0
    private(set) var selectedID: UUID?
    private(set) var selectedName: String?
    private(set) var mode: HeadwindMode?
    private(set) var manualSpeed = 0
    private(set) var desiredManualSpeed: Int
    private(set) var lastSensorMode: HeadwindMode
    private(set) var commandError: String?
    private(set) var isCommandPending = false
    private(set) var requestedManual: Bool

    var isScanning: Bool {
        state == .scanning || deferredAction == .scan || scansAfterDisconnect
    }
    var isReady: Bool {
        return state == .ready
    }
    var isManual: Bool { mode == .manual }
    var hasSavedDevice: Bool { selectedID != nil }

    private let defaults: UserDefaults
    private let identityKey = "VirtualGears.headwindIdentity"
    private let speedKey = "VirtualGears.headwindManualSpeed"
    private let sensorModeKey = "VirtualGears.headwindSensorMode"
    private let controlPreferenceKey = "VirtualGears.headwindManualControl"
    private let reconnectDelays: [UInt64] = [1, 2, 4, 8, 15]
    private let serviceUUID = CBUUID(
        string: "A026EE0C-0A7D-4AB3-97FA-F1500F9FEB8B"
    )
    private let controlUUID = CBUUID(
        string: "A026E038-0A7D-4AB3-97FA-F1500F9FEB8B"
    )

    private var central: CBCentralManager!
    private var scanWhenPoweredOn = false
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var desiredConnection = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var commandTimeoutTask: Task<Void, Never>?
    private var speedDebounceTask: Task<Void, Never>?
    private var commandQueue: [HeadwindCommand] = []
    private var pendingCommand: HeadwindCommand?
    private var isSuspendedForDemo = false
    private var resumesAfterDemoDisconnect = false
    private var deferredAction: DeferredAction?
    private var scansAfterDisconnect = false
    private var hasReceivedInitialState = false
    private var isIgnoringConflictingHeadwindState = false
    /// Whether a ride is what is asking for the fan. Connecting on its own is
    /// not, so the saved preference stays on the shelf until a ride starts.
    private var isRideDrivingFan = false
    private var hasStoredControlPreference: Bool

    private(set) var connectionIsStalled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedPreference = defaults.object(
            forKey: "VirtualGears.headwindManualControl"
        ) as? Bool
        requestedManual = storedPreference ?? false
        hasStoredControlPreference = storedPreference != nil
        desiredManualSpeed = defaults.object(forKey: speedKey) == nil
            ? 50 : min(100, max(0, defaults.integer(forKey: speedKey)))
        lastSensorMode = HeadwindMode(
            rawValue: UInt8(defaults.integer(forKey: sensorModeKey))
        ).flatMap { $0.isSensorControlled ? $0 : nil } ?? .heartRate
        super.init()
        loadIdentity()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startScanning() {
        guard !isSuspendedForDemo else { return }
        if hasSavedDevice {
            guard isReady else {
                deferredAction = .scan
                commandError = nil
                resumeSavedConnection()
                return
            }
            restoreSensors(then: .scan)
            return
        }
        scanWhenPoweredOn = true
        beginScanning()
    }

    private func beginScanning() {
        scanGeneration += 1
        desiredConnection = false
        reconnectTask?.cancel()
        guard central.state == .poweredOn else {
            state = .unavailable(central.state.productDescription)
            return
        }
        scanWhenPoweredOn = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        candidates.removeAll()
        discovered.removeAll()
        // HEADWIND does not advertise its control service, so filtering by UUID
        // would hide the very device this scan is looking for.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        state = .scanning
        log("Scanning for HEADWIND")
    }

    func stopScanning(reconnectSavedDevice: Bool = true) {
        scanWhenPoweredOn = false
        let cancelledReplacement =
            deferredAction == .scan || scansAfterDisconnect
        if deferredAction == .scan { deferredAction = nil }
        scansAfterDisconnect = false
        central.stopScan()
        if state == .scanning { state = .disconnected }
        if cancelledReplacement { desiredConnection = hasSavedDevice }
        if state == .disconnecting { return }
        if reconnectSavedDevice { autoConnectSavedDevice() }
    }

    func autoConnectSavedDevice() {
        guard !isSuspendedForDemo else { return }
        guard hasSavedDevice, !isScanning else { return }
        guard peripheral?.state != .connected,
              peripheral?.state != .connecting,
              peripheral?.state != .disconnecting else { return }
        resumeSavedConnection()
    }

    func selectAndConnect(_ id: UUID) {
        guard let peripheral = discovered[id] else {
            failConnection("Selected Headwind is no longer available")
            return
        }
        persistIdentity(
            id: id,
            name: candidates.first(where: { $0.id == id })?.name
                ?? peripheral.name ?? "Wahoo HEADWIND"
        )
        desiredConnection = true
        reconnectAttempt = 0
        connect(peripheral)
    }

    func resumeSavedConnection() {
        guard !isSuspendedForDemo else { return }
        guard let selectedID else { return }
        desiredConnection = true
        reconnectTask?.cancel()
        reconnectAttempt = 0
        guard central.state == .poweredOn else { return }
        guard peripheral?.state != .connected,
              peripheral?.state != .connecting,
              peripheral?.state != .disconnecting else { return }
        guard let restored = central.retrievePeripherals(
            withIdentifiers: [selectedID]
        ).first else {
            state = .failed("Your Headwind is not answering")
            scheduleReconnect()
            return
        }
        connect(restored)
    }

    func useManualControl() {
        guard isReady else {
            commandError = "Headwind is not connected."
            autoConnectSavedDevice()
            return
        }
        commandError = nil
        requestedManual = true
        persistControlPreference()
        deferredAction = nil
        commandQueue.removeAll()
        if mode != .manual, pendingCommand != .setMode(.manual) {
            enqueue(.setMode(.manual))
        }
        enqueue(.setManualSpeed(desiredManualSpeed), replacingSpeed: true)
    }

    func useSensorControl() {
        guard isReady else {
            commandError = "Headwind is not connected."
            autoConnectSavedDevice()
            return
        }
        commandError = nil
        requestedManual = false
        persistControlPreference()
        speedDebounceTask?.cancel()
        commandQueue.removeAll()
        enqueue(.setMode(lastSensorMode))
    }

    func setManualSpeed(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        desiredManualSpeed = clamped
        defaults.set(clamped, forKey: speedKey)
        commandError = nil
        speedDebounceTask?.cancel()
        speedDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.useManualControl()
        }
    }

    /// Removing a connected fan is a state change, not just forgetting an ID.
    /// Manual mode survives disconnect, so sensor control must be confirmed first.
    func stopUsing() {
        guard isReady else {
            commandError =
                "Reconnect the Headwind so Virtual Gears can return it to Sensors."
            autoConnectSavedDevice()
            return
        }
        restoreSensors(then: .remove)
    }

    /// Stops Bluetooth activity for Demo Mode without changing the remembered
    /// fan or sending the sensor/manual commands used by normal removal.
    func suspendForDemo() {
        isSuspendedForDemo = true
        resumesAfterDemoDisconnect = false
        desiredConnection = false
        reconnectTask?.cancel()
        speedDebounceTask?.cancel()
        scanWhenPoweredOn = false
        deferredAction = nil
        scansAfterDisconnect = false
        central.stopScan()
        commandQueue.removeAll()
        guard let peripheral else {
            resetConnection()
            state = .disconnected
            return
        }
        state = .disconnecting
        central.cancelPeripheralConnection(peripheral)
    }

    func resumeAfterDemo() {
        if peripheral != nil {
            resumesAfterDemoDisconnect = true
            return
        }
        isSuspendedForDemo = false
        if hasSavedDevice { resumeSavedConnection() }
    }

    private func finishDemoSuspensionIfNeeded() -> Bool {
        guard isSuspendedForDemo, resumesAfterDemoDisconnect else { return false }
        isSuspendedForDemo = false
        resumesAfterDemoDisconnect = false
        if hasSavedDevice { resumeSavedConnection() }
        return true
    }

    private func restoreSensors(then action: DeferredAction) {
        deferredAction = action
        requestedManual = false
        persistControlPreference()
        speedDebounceTask?.cancel()
        // The pending write cannot be recalled. Sensor mode is therefore queued
        // after it and must be acknowledged before the deferred action runs.
        commandQueue.removeAll()
        enqueue(.setMode(lastSensorMode))
    }

    private func enqueue(
        _ command: HeadwindCommand,
        replacingSpeed: Bool = false
    ) {
        guard !isSuspendedForDemo else { return }
        if replacingSpeed {
            commandQueue.removeAll {
                if case .setManualSpeed = $0 { true } else { false }
            }
        }
        commandQueue.append(command)
        sendNextCommand()
    }

    private func sendNextCommand() {
        guard pendingCommand == nil,
              let command = commandQueue.first,
              let peripheral,
              let controlCharacteristic,
              peripheral.state == .connected else { return }
        commandQueue.removeFirst()
        do {
            pendingCommand = command
            isCommandPending = true
            peripheral.writeValue(
                try command.encode(),
                for: controlCharacteristic,
                type: .withoutResponse
            )
            log("Sent \(command)")
            commandTimeoutTask?.cancel()
            commandTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self,
                      self.pendingCommand == command else { return }
                self.commandFailed("Headwind did not confirm the change.")
            }
        } catch {
            commandFailed(error.localizedDescription)
        }
    }

    private func process(_ data: Data) {
        do {
            let message = try HeadwindMessageDecoder.decode(data)
            switch message {
            case let .state(newMode, speed):
                let isInitial = !hasReceivedInitialState
                if !isInitial, hasStoredControlPreference,
                   (newMode == .manual) != requestedManual {
                    // A Headwind reports its state about once a second, so a
                    // disagreement that lasts logs forever and buries every
                    // other line in the log a bug report depends on. Say it
                    // once per disagreement.
                    if !isIgnoringConflictingHeadwindState {
                        isIgnoringConflictingHeadwindState = true
                        log(
                            "Ignored Headwind state that conflicts with confirmed control",
                            level: .warning
                        )
                    }
                    return
                }
                isIgnoringConflictingHeadwindState = false
                apply(mode: newMode, speed: speed)
                if isInitial {
                    hasReceivedInitialState = true
                    state = .ready
                    reconcileControlPreference()
                }
            case let .modeAcknowledged(newMode, succeeded):
                guard pendingCommand == .setMode(newMode) else {
                    log("Ignored a stale mode acknowledgement", level: .warning)
                    return
                }
                guard succeeded else {
                    commandFailed("Headwind refused \(newMode.label) mode.")
                    return
                }
                apply(mode: newMode, speed: manualSpeed)
                commandConfirmed()
                if let deferredAction, newMode.isSensorControlled {
                    self.deferredAction = nil
                    perform(deferredAction)
                    return
                }
            case let .speedAcknowledged(speed, succeeded):
                guard pendingCommand == .setManualSpeed(speed) else {
                    log("Ignored a stale speed acknowledgement", level: .warning)
                    return
                }
                guard succeeded else {
                    commandFailed("Headwind refused \(speed)% fan speed.")
                    return
                }
                manualSpeed = speed
                mode = .manual
                commandConfirmed()
            }
        } catch {
            log("Ignored Headwind packet: \(error)", level: .warning)
        }
    }

    private func apply(
        mode newMode: HeadwindMode,
        speed: Int
    ) {
        mode = newMode
        let adoptsExistingState = !hasStoredControlPreference
        if adoptsExistingState {
            requestedManual = newMode == .manual
            hasStoredControlPreference = true
            persistControlPreference()
        }
        if newMode == .manual {
            manualSpeed = min(100, max(0, speed))
            if adoptsExistingState, defaults.object(forKey: speedKey) == nil {
                desiredManualSpeed = manualSpeed
                defaults.set(manualSpeed, forKey: speedKey)
            }
        } else if newMode.isSensorControlled {
            lastSensorMode = newMode
            defaults.set(Int(newMode.rawValue), forKey: sensorModeKey)
        }
    }

    /// Applies the rider's saved fan preference. Called when a ride starts, not
    /// when the fan connects: simply opening the app must never spin a fan up.
    func applySavedControlPreference() {
        isRideDrivingFan = true
        guard isReady else { return }
        reconcileControlPreference()
    }

    /// Hands the fan back once the ride is over, so a later reconnect is just a
    /// connection again rather than a reason to start blowing.
    func releaseRideFanControl() {
        isRideDrivingFan = false
    }

    private func reconcileControlPreference() {
        let commands = HeadwindControlPolicy.commands(
            for: HeadwindSituation(
                rideIsDrivingFan: isRideDrivingFan,
                isHandingBack: deferredAction != nil,
                wantsManualControl: requestedManual,
                desiredManualSpeed: desiredManualSpeed,
                lastSensorMode: lastSensorMode,
                observedMode: mode,
                observedManualSpeed: manualSpeed
            )
        )
        guard !commands.isEmpty else { return }
        // Handing the fan back replaces whatever was queued, because those are
        // the commands being abandoned.
        if deferredAction != nil { commandQueue.removeAll() }
        for command in commands {
            switch command {
            case .setManualSpeed:
                enqueue(command, replacingSpeed: true)
            case .setMode:
                enqueue(command)
            }
        }
    }

    private func commandConfirmed() {
        commandTimeoutTask?.cancel()
        pendingCommand = nil
        isCommandPending = false
        commandError = nil
        sendNextCommand()
    }

    private func commandFailed(_ message: String) {
        commandTimeoutTask?.cancel()
        pendingCommand = nil
        commandQueue.removeAll()
        isCommandPending = false
        // The action was waiting on a command that never landed. Leaving it
        // armed would fire it against whatever the rider does next.
        deferredAction = nil
        commandError = message
        log(message, level: .error)
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard !isSuspendedForDemo else { return }
        central.stopScan()
        resetConnection(keepingPeripheral: true)
        self.peripheral = peripheral
        hasReceivedInitialState = false
        peripheral.delegate = self
        state = .connecting(
            name: selectedID == peripheral.identifier
                ? (selectedName ?? peripheral.name ?? "Wahoo HEADWIND")
                : (peripheral.name ?? "Wahoo HEADWIND")
        )
        central.connect(peripheral)
    }

    private func scheduleReconnect() {
        guard desiredConnection, central.state == .poweredOn else { return }
        reconnectTask?.cancel()
        let index = min(reconnectAttempt, reconnectDelays.count - 1)
        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)
        let delay = reconnectDelays[index]
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self, self.desiredConnection else { return }
            self.resumeSavedConnection()
        }
    }

    private func updateStallWatch() {
        guard state.isConnectionInProgress else {
            stallTask?.cancel()
            stallTask = nil
            connectionIsStalled = false
            return
        }
        guard stallTask == nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.connectionIsStalled = true
        }
    }

    private func persistIdentity(id: UUID, name: String) {
        selectedID = id
        selectedName = name
        defaults.set(["id": id.uuidString, "name": name], forKey: identityKey)
    }

    private func persistControlPreference() {
        hasStoredControlPreference = true
        defaults.set(requestedManual, forKey: controlPreferenceKey)
    }

    private func loadIdentity() {
        guard let value = defaults.dictionary(forKey: identityKey),
              let idString = value["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        selectedID = id
        selectedName = value["name"] as? String
    }

    private func clearSelection() {
        deferredAction = nil
        desiredConnection = false
        selectedID = nil
        selectedName = nil
        defaults.removeObject(forKey: identityKey)
        commandQueue.removeAll()
        pendingCommand = nil
        isCommandPending = false
        if let peripheral {
            state = .disconnecting
            central.cancelPeripheralConnection(peripheral)
        } else {
            state = .disconnected
        }
    }

    private func resetConnection(keepingPeripheral: Bool = false) {
        commandTimeoutTask?.cancel()
        pendingCommand = nil
        commandQueue.removeAll()
        isCommandPending = false
        controlCharacteristic = nil
        hasReceivedInitialState = false
        if !keepingPeripheral { peripheral = nil }
    }

    private func perform(_ action: DeferredAction) {
        switch action {
        case .remove:
            clearSelection()
        case .scan:
            desiredConnection = false
            scansAfterDisconnect = true
            guard let peripheral else {
                scansAfterDisconnect = false
                beginScanning()
                return
            }
            state = .disconnecting
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func failConnection(_ message: String) {
        state = .failed(message)
        log(message, level: .error)
        if desiredConnection, let peripheral, peripheral.state == .connected {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func log(
        _ message: String,
        level: ProductLogLevel = .info
    ) {
        ProductLogger.record(message, source: "Headwind", level: level)
    }

}

#if DEBUG
extension HeadwindCentralService {
    func stageScreenshot(name: String, speed: Int) {
        selectedID = ScreenshotFixture.headwindID
        selectedName = name
        state = .ready
        mode = .manual
        manualSpeed = speed
        desiredManualSpeed = speed
        requestedManual = true
        lastSensorMode = .heartRate
        commandError = nil
        isCommandPending = false
    }
}
#endif

extension HeadwindCentralService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isSuspendedForDemo else {
            central.stopScan()
            state = .disconnected
            if central.state != .poweredOn {
                resetConnection()
                _ = finishDemoSuspensionIfNeeded()
            }
            return
        }
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
        guard !isSuspendedForDemo else { return }
        let advertised = advertisementData[
            CBAdvertisementDataLocalNameKey
        ] as? String
        let name = advertised ?? peripheral.name ?? ""
        guard name.uppercased().hasPrefix("HEADWIND") else { return }
        discovered[peripheral.identifier] = peripheral
        candidates.absorb(.init(
            id: peripheral.identifier,
            name: name
        ))
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard !isSuspendedForDemo else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard self.peripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        reconnectAttempt = 0
        state = .discovering
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        resetConnection()
        log(error?.localizedDescription ?? "Connection failed", level: .error)
        if finishDemoSuspensionIfNeeded() { return }
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
        if finishDemoSuspensionIfNeeded() { return }
        if scansAfterDisconnect {
            scansAfterDisconnect = false
            self.peripheral = nil
            beginScanning()
            return
        }
        if desiredConnection { scheduleReconnect() }
    }
}

extension HeadwindCentralService: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        if let error {
            failConnection(
                "Headwind service discovery failed: \(error.localizedDescription)"
            )
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == serviceUUID
        }) else {
            failConnection("This fan is missing the Headwind control service")
            return
        }
        peripheral.discoverCharacteristics([controlUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        if let error {
            failConnection(
                "Headwind control discovery failed: \(error.localizedDescription)"
            )
            return
        }
        guard let control = service.characteristics?.first(where: {
            $0.uuid == controlUUID
        }),
        control.properties.contains(.writeWithoutResponse),
        control.properties.contains(.notify),
        control.properties.contains(.read) else {
            failConnection("This Headwind does not expose the expected controls")
            return
        }
        controlCharacteristic = control
        state = .preparing
        peripheral.setNotifyValue(true, for: control)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        guard self.peripheral?.identifier == peripheral.identifier,
              characteristic.uuid == controlUUID else { return }
        if let error {
            failConnection(
                "Headwind notifications failed: \(error.localizedDescription)"
            )
            return
        }
        guard characteristic.isNotifying else {
            failConnection("Headwind notifications are not available")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        guard self.peripheral?.identifier == peripheral.identifier,
              characteristic.uuid == controlUUID else { return }
        if let error {
            log(error.localizedDescription, level: .warning)
            return
        }
        guard let data = characteristic.value else { return }
        process(data)
    }
}
