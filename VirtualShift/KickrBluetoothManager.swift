import CoreBluetooth
import Foundation
import VirtualShiftCore

struct TrainerCandidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

struct DiagnosticEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String

    var text: String {
        "\(date.formatted(date: .omitted, time: .standard))  \(message)"
    }
}

@MainActor
final class KickrBluetoothManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothStatus = "Starting Bluetooth..."
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var trainers: [TrainerCandidate] = []
    @Published private(set) var selectedTrainerID: UUID?
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var safetyWarning: String?
    @Published private(set) var characteristicProperties = "Not discovered"
    @Published private(set) var entries: [DiagnosticEntry] = []
    @Published private(set) var lastConfirmedCircumference: Double?
    @Published private(set) var proofValues: WahooKickrProofValues?
    @Published private(set) var baselineError: String?
    @Published private(set) var powerWatts: Int?
    @Published private(set) var cadenceRPM: Double?
    @Published private(set) var confirmedRangeProbeValues: [Double] = []

    private struct PendingCommand {
        let id = UUID()
        let name: String
        let data: Data
        let circumference: Double?
        let marksUnlocked: Bool
        let makesReady: Bool
        let disconnectAfterWrite: Bool
        let rangeProbeValue: Double?
        let restoreOnFailure: Bool

        init(
            name: String,
            data: Data,
            circumference: Double?,
            marksUnlocked: Bool,
            makesReady: Bool,
            disconnectAfterWrite: Bool,
            rangeProbeValue: Double? = nil,
            restoreOnFailure: Bool = false
        ) {
            self.name = name
            self.data = data
            self.circumference = circumference
            self.marksUnlocked = marksUnlocked
            self.makesReady = makesReady
            self.disconnectAfterWrite = disconnectAfterWrite
            self.rangeProbeValue = rangeProbeValue
            self.restoreOnFailure = restoreOnFailure
        }
    }

    static let rangeProbeValues: [Double] = [
        1_570, 2_570, 1_200, 3_200, 900, 3_800, 646.9, 4_200, 4_735.1, 4_800,
    ]

    private let serviceUUID = CBUUID(
        string: WahooKickrProtocol.cyclingPowerServiceUUID
    )
    private let controlUUID = CBUUID(
        string: WahooKickrProtocol.controlCharacteristicUUID
    )
    private let measurementUUID = CBUUID(
        string: WahooKickrProtocol.cyclingPowerMeasurementUUID
    )

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var pendingPeripheral: CBPeripheral?
    private var connectedPeripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var measurementCharacteristic: CBCharacteristic?
    private var cadenceTracker = CrankCadenceTracker()
    private var lastCrankEventTime: UInt16?
    private var lastCrankEventDate: Date?
    private var commandQueue: [PendingCommand] = []
    private var activeCommand: PendingCommand?
    private var activeWriteConfirmed = false
    private var activeResponse: WahooKickrResponse?
    private var activeResponseFailure: String?
    private var stopping = false
    private var unlockConfirmed = false
    private var safeDisconnectConfirmed = false
    private var cancelledBeforeCommands = false

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        log("Proof app started")
    }

    var diagnosticText: String {
        entries.map(\.text).joined(separator: "\n")
    }

    var nextRangeProbeValue: Double? {
        Self.rangeProbeValues.first {
            !confirmedRangeProbeValues.contains($0)
        }
    }

    func confirmBaseline(_ millimeters: Double) {
        guard !isConnected && !isConnecting else {
            baselineError = "Stop the current session before changing the starting value."
            return
        }

        do {
            let values = try WahooKickrProofValues(baseline: millimeters)
            proofValues = values
            confirmedRangeProbeValues = []
            baselineError = nil
            log(
                "Starting value confirmed: \(values.baseline.formatted()) mm; "
                    + "tests are \(values.easier.formatted()) and "
                    + "\(values.harder.formatted()) mm"
            )
        } catch {
            proofValues = nil
            confirmedRangeProbeValues = []
            baselineError =
                "Enter a starting value above 500 mm and no more than "
                + "\(Int(WahooKickrCommand.maximumCircumferenceMillimeters - 500)) mm."
        }
    }

    func clearBaselineConfirmation() {
        guard !isConnected && !isConnecting else { return }
        proofValues = nil
        baselineError = nil
    }

    func startScanning() {
        guard !isConnected && !isConnecting else {
            reportError("Stop the current session before choosing another trainer")
            return
        }
        guard central.state == .poweredOn else {
            reportError("Bluetooth is not ready: \(central.state.description)")
            return
        }

        trainers = []
        peripherals = [:]
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        log("Scanning for nearby KICKR trainers")
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        log("Scan stopped")
    }

    func connect(to id: UUID) {
        guard proofValues != nil else {
            baselineError = "Confirm the starting value before connecting."
            return
        }
        guard !isConnected && !isConnecting else {
            reportError("Stop the current session before choosing another trainer")
            return
        }
        guard let peripheral = peripherals[id] else {
            reportError("The selected trainer is no longer available")
            return
        }

        stopScanning()
        selectedTrainerID = id
        pendingPeripheral = peripheral
        isConnecting = true
        stopping = false
        safeDisconnectConfirmed = false
        cancelledBeforeCommands = false
        connectionStatus = "Connecting to \(peripheral.name ?? "KICKR")..."
        safetyWarning = nil
        peripheral.delegate = self
        central.connect(peripheral)
        log("Connecting to \(peripheral.name ?? id.uuidString)")
    }

    func send(_ selection: WahooKickrProofSelection) {
        guard isReady else {
            reportError("Wait for unlock and neutral setup to finish")
            return
        }

        guard let values = proofValues else {
            reportError("The starting value is not confirmed")
            return
        }

        do {
            let circumference = values[selection]
            let data = try WahooKickrCommand.setWheelCircumference(
                millimeters: circumference
            )
            enqueue(
                PendingCommand(
                    name: "\(selection.label) \(circumference.formatted()) mm",
                    data: data,
                    circumference: circumference,
                    marksUnlocked: false,
                    makesReady: false,
                    disconnectAfterWrite: false
                )
            )
        } catch {
            reportError(
                "Could not create \(selection.label.lowercased()) command: \(error)"
            )
        }
    }

    func sendNextRangeProbe() {
        guard isReady, !isBusy else {
            reportError("Wait until the trainer is ready before testing the next value")
            return
        }
        guard let baseline = proofValues?.baseline,
              let probe = nextRangeProbeValue else { return }

        do {
            let probeData = try WahooKickrCommand.setWheelCircumference(
                millimeters: probe
            )
            let baselineData = try WahooKickrCommand.setWheelCircumference(
                millimeters: baseline
            )
            enqueue(
                PendingCommand(
                    name: "Range probe \(probe.formatted()) mm",
                    data: probeData,
                    circumference: probe,
                    marksUnlocked: false,
                    makesReady: false,
                    disconnectAfterWrite: false,
                    restoreOnFailure: true
                )
            )
            enqueue(
                PendingCommand(
                    name: "Range probe neutral restore \(baseline.formatted()) mm",
                    data: baselineData,
                    circumference: baseline,
                    marksUnlocked: false,
                    makesReady: true,
                    disconnectAfterWrite: false,
                    rangeProbeValue: probe,
                    restoreOnFailure: true
                )
            )
        } catch {
            reportError("Could not create range probe commands: \(error)")
        }
    }

    func stop(reason: String = "Stop requested") {
        if let peripheral = pendingPeripheral, connectedPeripheral == nil {
            stopping = true
            cancelledBeforeCommands = true
            connectionStatus = "Cancelling connection..."
            log("\(reason); cancelling connection before any trainer command")
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard connectedPeripheral != nil else {
            connectionStatus = "Not connected"
            return
        }
        guard !stopping else { return }
        guard let baseline = proofValues?.baseline else {
            failSafetyRestore("The confirmed starting value is missing")
            return
        }

        stopping = true
        safeDisconnectConfirmed = false
        isReady = false
        commandQueue.removeAll()
        log(
            "\(reason); restoring \(baseline.formatted()) mm before disconnect"
        )

        guard controlCharacteristic != nil else {
            safetyWarning =
                "The control characteristic was not available, so neutral could not "
                + "be confirmed before disconnect."
            if let peripheral = connectedPeripheral {
                central.cancelPeripheralConnection(peripheral)
            }
            return
        }

        if !unlockConfirmed && activeCommand?.marksUnlocked != true {
            enqueue(
                PendingCommand(
                    name: "Safety unlock",
                    data: WahooKickrCommand.unlock,
                    circumference: nil,
                    marksUnlocked: true,
                    makesReady: false,
                    disconnectAfterWrite: false
                )
            )
        }

        do {
            let neutral = try WahooKickrCommand.setWheelCircumference(
                millimeters: baseline
            )
            enqueue(
                PendingCommand(
                    name: "Safety restore \(baseline.formatted()) mm",
                    data: neutral,
                    circumference: baseline,
                    marksUnlocked: false,
                    makesReady: false,
                    disconnectAfterWrite: true
                )
            )
        } catch {
            failSafetyRestore("Could not create the neutral command: \(error)")
        }
    }

    private func beginSafeSession() {
        guard let baseline = proofValues?.baseline else {
            reportError("Confirm the starting value before connecting")
            return
        }
        guard let characteristic = controlCharacteristic else {
            reportError("The Wahoo control characteristic was not found")
            return
        }
        guard characteristic.properties.contains(.write) else {
            characteristicProperties = characteristic.properties.description
            reportError(
                "The Wahoo control characteristic cannot confirm writes. "
                    + "This proof will not use unconfirmed commands."
            )
            return
        }

        commandQueue.removeAll()
        activeCommand = nil
        activeWriteConfirmed = false
        activeResponse = nil
        activeResponseFailure = nil
        stopping = false
        unlockConfirmed = false
        safeDisconnectConfirmed = false
        cancelledBeforeCommands = false
        isReady = false
        safetyWarning = nil

        enqueue(
            PendingCommand(
                name: "Wahoo unlock",
                data: WahooKickrCommand.unlock,
                circumference: nil,
                marksUnlocked: true,
                makesReady: false,
                disconnectAfterWrite: false
            )
        )

        do {
            let neutral = try WahooKickrCommand.setWheelCircumference(
                millimeters: baseline
            )
            enqueue(
                PendingCommand(
                    name: "Initial restore \(baseline.formatted()) mm",
                    data: neutral,
                    circumference: baseline,
                    marksUnlocked: false,
                    makesReady: true,
                    disconnectAfterWrite: false
                )
            )
        } catch {
            reportError("Could not create the initial neutral command: \(error)")
        }
    }

    private func enqueue(_ command: PendingCommand) {
        commandQueue.append(command)
        processNextCommand()
    }

    private func processNextCommand() {
        guard activeCommand == nil,
              !commandQueue.isEmpty,
              let peripheral = connectedPeripheral,
              let characteristic = controlCharacteristic
        else {
            isBusy = activeCommand != nil || !commandQueue.isEmpty
            return
        }

        let command = commandQueue.removeFirst()
        activeCommand = command
        activeWriteConfirmed = false
        activeResponse = nil
        activeResponseFailure = nil
        isBusy = true
        log("Writing \(command.name): \(command.data.hexString)")
        peripheral.writeValue(command.data, for: characteristic, type: .withResponse)
        scheduleCommandTimeout(for: command)
    }

    private func handleWriteResult(error: Error?) {
        guard let command = activeCommand else {
            reportError("Received a write result with no active command")
            return
        }

        if let error {
            failActiveCommand(
                "\(command.name) write failed: \(error.localizedDescription)"
            )
            return
        }

        activeWriteConfirmed = true
        log("Bluetooth write confirmed: \(command.name); waiting for KICKR reply")
        if let activeResponseFailure {
            failActiveCommand(activeResponseFailure)
        } else if activeResponse != nil {
            completeVerifiedCommand()
        }
    }

    private func handleControlResponse(_ data: Data) {
        log("Notification from \(controlUUID.uuidString): \(data.hexString)")

        guard let command = activeCommand else {
            log("ERROR: Received a KICKR reply with no active command")
            return
        }

        do {
            let response = try WahooKickrResponse.decode(data)
            guard response.confirmsSuccess(for: command.data) else {
                holdOrReportResponseFailure(
                    "\(command.name) did not receive a matching successful reply: "
                        + response.summary
                )
                return
            }

            activeResponse = response
            activeResponseFailure = nil
            log("Matching KICKR reply: \(response.summary)")
            if activeWriteConfirmed {
                completeVerifiedCommand()
            }
        } catch {
            holdOrReportResponseFailure(
                "\(command.name) received an unreadable KICKR reply: \(error)"
            )
        }
    }

    private func holdOrReportResponseFailure(_ message: String) {
        if activeWriteConfirmed {
            failActiveCommand(message)
        } else {
            activeResponseFailure = message
            log("KICKR reply failed validation; waiting for Bluetooth write completion")
        }
    }

    private func completeVerifiedCommand() {
        guard let command = activeCommand, activeResponse != nil else { return }
        activeCommand = nil
        activeWriteConfirmed = false
        activeResponse = nil
        activeResponseFailure = nil
        log("KICKR verified: \(command.name)")

        if command.marksUnlocked {
            unlockConfirmed = true
        }
        if let circumference = command.circumference {
            lastConfirmedCircumference = circumference
        }
        if let rangeProbeValue = command.rangeProbeValue,
           !confirmedRangeProbeValues.contains(rangeProbeValue) {
            confirmedRangeProbeValues.append(rangeProbeValue)
            log("RANGE PROBE PASSED: \(rangeProbeValue.formatted()) mm")
        }
        if command.makesReady {
            isReady = true
            connectionStatus = "Ready for proof commands"
            log("Starting value is confirmed; test controls are enabled")
        }
        if command.disconnectAfterWrite {
            finishSafeDisconnect()
            return
        }

        processNextCommand()
    }

    private func scheduleCommandTimeout(for command: PendingCommand) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.activeCommand?.id == command.id else { return }
            self.failActiveCommand(
                "\(command.name) did not complete its write and matching reply "
                    + "within 5 seconds",
                canAttemptRestore: self.activeWriteConfirmed
            )
        }
    }

    private func failActiveCommand(
        _ message: String,
        canAttemptRestore: Bool = true
    ) {
        let command = activeCommand
        activeCommand = nil
        activeWriteConfirmed = false
        activeResponse = nil
        activeResponseFailure = nil
        commandQueue.removeAll()
        isBusy = false

        if stopping || command?.disconnectAfterWrite == true {
            failSafetyRestore(message)
        } else if command?.rangeProbeValue != nil {
            failSafetyRestore(message)
        } else if command?.restoreOnFailure == true {
            isReady = false
            if canAttemptRestore {
                log("Range probe failed; starting safety restore")
                stop(reason: message)
            } else {
                failSafetyRestore(
                    "\(message). The Bluetooth write state is unknown; "
                        + "reconnect to restore the starting value."
                )
            }
        } else {
            isReady = false
            reportError(message)
        }
    }

    private func finishSafeDisconnect() {
        guard let peripheral = connectedPeripheral else { return }
        safeDisconnectConfirmed = true
        isBusy = false
        log("Starting value restore confirmed; disconnecting")
        connectionStatus = "Disconnecting safely..."
        central.cancelPeripheralConnection(peripheral)
    }

    private func failSafetyRestore(_ message: String) {
        stopping = true
        isBusy = false
        safetyWarning = "NEUTRAL RESTORE FAILED: \(message)"
        connectionStatus = "Disconnecting after restore failure"
        log("SAFETY ERROR: \(message); disconnecting")
        if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func reportError(_ message: String) {
        connectionStatus = "Error"
        log("ERROR: \(message)")
    }

    private func log(_ message: String) {
        entries.append(DiagnosticEntry(date: Date(), message: message))
    }
}

extension KickrBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothStatus = central.state.description
            log("Bluetooth state: \(central.state.description)")
            if central.state != .poweredOn {
                isScanning = false
                isReady = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            let advertisedName =
                advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = advertisedName ?? peripheral.name ?? "Unnamed trainer"
            guard name.localizedCaseInsensitiveContains("KICKR") else { return }

            peripherals[peripheral.identifier] = peripheral
            let candidate = TrainerCandidate(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue
            )
            if let index = trainers.firstIndex(where: { $0.id == candidate.id }) {
                trainers[index] = candidate
            } else {
                trainers.append(candidate)
                log("Found \(name), signal \(RSSI)")
            }
            trainers.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        MainActor.assumeIsolated {
            connectedPeripheral = peripheral
            pendingPeripheral = nil
            isConnecting = false
            isConnected = true
            if stopping {
                cancelledBeforeCommands = true
                connectionStatus = "Cancelling connection..."
                log("Connection completed after Stop; disconnecting without sending commands")
                central.cancelPeripheralConnection(peripheral)
                return
            }
            connectionStatus = "Discovering trainer controls..."
            log("Connected to \(peripheral.name ?? peripheral.identifier.uuidString)")
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            pendingPeripheral = nil
            isConnecting = false
            connectedPeripheral = nil
            isConnected = false
            if stopping {
                stopping = false
                safeDisconnectConfirmed = false
                cancelledBeforeCommands = false
                connectionStatus = "Connection cancelled"
                log("Connection cancelled before any trainer command")
            } else {
                reportError(
                    "Connection failed: \(error?.localizedDescription ?? "unknown error")"
                )
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let wasSafe = stopping && safeDisconnectConfirmed
            let wasCancelledBeforeCommands = stopping && cancelledBeforeCommands
            pendingPeripheral = nil
            isConnecting = false
            connectedPeripheral = nil
            isConnected = false
            controlCharacteristic = nil
            commandQueue.removeAll()
            activeCommand = nil
            activeWriteConfirmed = false
            activeResponse = nil
            activeResponseFailure = nil
            isReady = false
            isBusy = false
            stopping = false
            unlockConfirmed = false
            safeDisconnectConfirmed = false
            cancelledBeforeCommands = false
            characteristicProperties = "Not discovered"
            measurementCharacteristic = nil
            powerWatts = nil
            cadenceRPM = nil
            cadenceTracker = CrankCadenceTracker()
            lastCrankEventTime = nil
            lastCrankEventDate = nil

            if wasCancelledBeforeCommands {
                safetyWarning = nil
                connectionStatus = "Connection cancelled"
                log("Disconnected without sending trainer commands")
            } else if let error {
                safetyWarning =
                    "Connection was lost. Neutral could not be confirmed at disconnect; "
                    + "it will be restored first on reconnect."
                connectionStatus = "Connection lost"
                log("Disconnected with error: \(error.localizedDescription)")
            } else if wasSafe {
                safetyWarning = nil
                connectionStatus = "Stopped safely"
                log("Disconnected after confirmed starting-value restore")
            } else {
                if safetyWarning == nil {
                    safetyWarning =
                        "Disconnected without a confirmed neutral restore. "
                        + "Reconnect before riding."
                }
                connectionStatus = "Disconnected without confirmed restore"
                log("WARNING: disconnect occurred without confirmed neutral restore")
            }
        }
    }
}

extension KickrBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        MainActor.assumeIsolated {
            if let error {
                reportError("Service discovery failed: \(error.localizedDescription)")
                return
            }
            guard let service = peripheral.services?.first(where: {
                $0.uuid == serviceUUID
            }) else {
                reportError("Cycling Power service 1818 was not found")
                return
            }

            log("Found Cycling Power service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(
                [controlUUID, measurementUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            if let error {
                reportError(
                    "Characteristic discovery failed: \(error.localizedDescription)"
                )
                return
            }
            guard let characteristic = service.characteristics?.first(where: {
                $0.uuid == controlUUID
            }) else {
                reportError(
                    "Wahoo control characteristic \(controlUUID.uuidString) was not found"
                )
                return
            }

            controlCharacteristic = characteristic
            characteristicProperties = characteristic.properties.description
            log(
                "Found control characteristic \(characteristic.uuid.uuidString), "
                    + "properties: \(characteristic.properties.description)"
            )

            if characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate)
            {
                peripheral.setNotifyValue(true, for: characteristic)
                log("Requested control notifications")
            } else {
                reportError(
                    "The Wahoo control characteristic cannot return command replies"
                )
            }

            if let measurement = service.characteristics?.first(where: {
                $0.uuid == measurementUUID
            }) {
                measurementCharacteristic = measurement
                log(
                    "Found power measurement \(measurement.uuid.uuidString), "
                        + "properties: \(measurement.properties.description)"
                )
                if measurement.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: measurement)
                    log("Requested live power and cadence")
                } else {
                    log("ERROR: Power measurement does not support notifications")
                }
            } else {
                log("ERROR: Cycling Power Measurement 2A63 was not found")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            handleWriteResult(error: error)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            if let error {
                if characteristic.uuid == controlUUID, activeCommand != nil {
                    holdOrReportResponseFailure(
                        "KICKR reply failed: \(error.localizedDescription)"
                    )
                } else {
                    reportError(
                        "Notification failed: \(error.localizedDescription)"
                    )
                }
                return
            }
            let value = characteristic.value ?? Data()
            if characteristic.uuid == measurementUUID {
                do {
                    let measurement = try CyclingPowerMeasurement.decode(value)
                    powerWatts = measurement.powerWatts
                    if let eventTime = measurement.lastCrankEventTime {
                        if eventTime != lastCrankEventTime {
                            lastCrankEventTime = eventTime
                            lastCrankEventDate = Date()
                        } else if let lastCrankEventDate,
                                  Date().timeIntervalSince(lastCrankEventDate) > 2
                        {
                            cadenceRPM = 0
                        }
                    }
                    if let cadence = cadenceTracker.update(with: measurement) {
                        cadenceRPM = cadence
                    }
                } catch {
                    log("ERROR: Could not read power measurement: \(error)")
                }
                return
            }
            if characteristic.uuid == controlUUID {
                handleControlResponse(value)
                return
            }
            log(
                "Notification from \(characteristic.uuid.uuidString): "
                    + value.hexString
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            if characteristic.uuid == measurementUUID {
                if let error {
                    log(
                        "ERROR: Live power notification setup failed: "
                            + error.localizedDescription
                    )
                } else {
                    log(
                        "Live power and cadence "
                            + (characteristic.isNotifying ? "enabled" : "disabled")
                    )
                }
                return
            }

            if let error {
                reportError(
                    "Notification setup failed: \(error.localizedDescription)"
                )
            } else {
                log(
                    "Notifications \(characteristic.isNotifying ? "enabled" : "disabled") "
                        + "for \(characteristic.uuid.uuidString)"
                )
                if characteristic.isNotifying {
                    beginSafeSession()
                } else {
                    reportError(
                        "The trainer did not enable control notifications"
                    )
                }
            }
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: "Unknown"
        case .resetting: "Resetting"
        case .unsupported: "Unsupported"
        case .unauthorized: "Not authorized"
        case .poweredOff: "Powered off"
        case .poweredOn: "Powered on"
        @unknown default: "Unknown future state"
        }
    }
}

extension CBCharacteristicProperties {
    var description: String {
        var names: [String] = []
        if contains(.broadcast) { names.append("broadcast") }
        if contains(.read) { names.append("read") }
        if contains(.writeWithoutResponse) { names.append("write without response") }
        if contains(.write) { names.append("write with response") }
        if contains(.notify) { names.append("notify") }
        if contains(.indicate) { names.append("indicate") }
        if contains(.authenticatedSignedWrites) {
            names.append("authenticated signed writes")
        }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}
