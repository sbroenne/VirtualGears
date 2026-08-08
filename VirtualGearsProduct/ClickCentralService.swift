import CoreBluetooth
import Foundation
import Observation
import VirtualGearsCore

@MainActor
@Observable
final class ClickCentralService: NSObject {
    private(set) var state: ProductConnectionState = .unavailable("Starting Bluetooth…") {
        didSet { updateStallWatch() }
    }
    private(set) var candidates: [BluetoothCandidate] = []
    private(set) var scanGeneration = 0
    private(set) var selectedID: UUID?
    private(set) var selectedName: String?
    private(set) var batteryLevel: Int?

    /// A Click runs on a coin cell that cannot be recharged, only replaced, so
    /// the useful moment to say anything is while the rider is still near a
    /// drawer rather than clipped in. Below this the ride screen speaks up;
    /// above it the level stays in Settings, where it informs without nagging.
    static let lowBatteryPercent = 20

    var batteryIsLow: Bool {
        guard let batteryLevel else { return false }
        return batteryLevel <= Self.lowBatteryPercent
    }
    private(set) var latestButtonEvent: ZwiftClickButtonEvent?
    private(set) var identificationCandidateID: UUID?
    private(set) var latestShiftRequest: ShiftRequest?
    private(set) var shiftRequests: [ShiftRequest] = []
    var shiftHandler: ((ShiftRequest) -> Void)?

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

    private let defaults: UserDefaults
    private let identityKey = "VirtualGears.clickIdentity"
    private let reconnectDelays: [UInt64] = [1, 2, 4, 8, 15]

    private let serviceUUID = CBUUID(string: ZwiftClickProtocol.serviceUUID)
    private let asyncUUID = CBUUID(string: ZwiftClickProtocol.asyncCharacteristicUUID)
    private let receiveUUID = CBUUID(
        string: ZwiftClickProtocol.syncReceiveCharacteristicUUID
    )
    private let transmitUUID = CBUUID(
        string: ZwiftClickProtocol.syncTransmitCharacteristicUUID
    )
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryUUID = CBUUID(string: "2A19")

    private var central: CBCentralManager!
    private var scanWhenPoweredOn = false
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var asyncCharacteristic: CBCharacteristic?
    private var receiveCharacteristic: CBCharacteristic?
    private var transmitCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType?
    private var subscribed: Set<CBUUID> = []
    private var servicesPending = 0
    private var handshakeSent = false
    private var desiredConnection = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var repeatTask: Task<Void, Never>?
    private var isSuspendedForDemo = false
    private var resumesAfterDemoDisconnect = false
    private var edgeTracker = ZwiftClickEdgeTracker()
    private var heldButton: ZwiftClickButton?
    private var isHolding = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        candidates.removeAll()
        discovered.removeAll()
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        state = .scanning
        log("Scanning for original Zwift Click")
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
        guard !isSuspendedForDemo else { return }
        guard hasSavedDevice, !isScanning else { return }
        guard peripheral?.state != .connected,
              peripheral?.state != .connecting,
              peripheral?.state != .disconnecting else { return }
        resumeSavedConnection()
    }

    func selectAndConnect(_ id: UUID) {
        guard let peripheral = discovered[id] else {
            fail("Selected Click is no longer available")
            return
        }
        persistIdentity(
            id: id,
            name: candidates.first(where: { $0.id == id })?.name
                ?? peripheral.name ?? "Zwift Click"
        )
        desiredConnection = true
        reconnectAttempt = 0
        connect(peripheral)
    }

    func connectForIdentification(_ id: UUID) {
        guard let candidate = discovered[id] else {
            fail("That Click is no longer available")
            return
        }
        if let peripheral, peripheral.identifier != id {
            central.cancelPeripheralConnection(peripheral)
        }
        desiredConnection = false
        identificationCandidateID = id
        latestButtonEvent = nil
        connect(candidate)
    }

    func confirmIdentification() {
        guard let id = identificationCandidateID,
              let candidate = candidates.first(where: { $0.id == id })
        else { return }
        persistIdentity(id: id, name: candidate.name)
        desiredConnection = true
        identificationCandidateID = nil
    }

    func cancelIdentification() {
        identificationCandidateID = nil
        latestButtonEvent = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
        state = .disconnected
    }

    func resumeSavedConnection() {
        guard !isSuspendedForDemo else { return }
        guard let selectedID else { return }
        desiredConnection = true
        if peripheral?.state == .connected
            || peripheral?.state == .connecting {
            return
        }
        // The disconnect callback has not landed yet. Connecting now would let
        // that callback tear this attempt down; it reconnects for us instead.
        if peripheral?.state == .disconnecting {
            reconnectTask?.cancel()
            reconnectAttempt = 0
            return
        }
        // A pending backoff retry would otherwise reconnect underneath this
        // attempt and reset an in-progress discovery.
        reconnectTask?.cancel()
        reconnectAttempt = 0
        guard central.state == .poweredOn else { return }
        retrieveAndConnect(selectedID)
    }

    func disconnect() {
        desiredConnection = false
        reconnectTask?.cancel()
        central.stopScan()
        stopRepeat()
        guard let peripheral else {
            resetConnection()
            state = central.isScanning ? .scanning : .disconnected
            return
        }
        state = .disconnecting
        central.cancelPeripheralConnection(peripheral)
    }

    func suspendForDemo() {
        isSuspendedForDemo = true
        resumesAfterDemoDisconnect = false
        scanWhenPoweredOn = false
        disconnect()
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

    func forgetSelection() {
        disconnect()
        selectedID = nil
        selectedName = nil
        defaults.removeObject(forKey: identityKey)
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard !isSuspendedForDemo else { return }
        central.stopScan()
        resetConnection(keepingPeripheral: true)
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting(
            name: selectedID == peripheral.identifier
                ? (selectedName ?? peripheral.name ?? "Zwift Click")
                : (peripheral.name ?? "Zwift Click")
        )
        central.connect(peripheral)
    }

    private func retrieveAndConnect(_ id: UUID) {
        guard let restored = central.retrievePeripherals(
            withIdentifiers: [id]
        ).first else {
            state = .failed("Your Click is not answering")
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
        guard let asyncCharacteristic,
              let receiveCharacteristic,
              let transmitCharacteristic else {
            fail("Click is missing one or more required controls")
            return
        }
        if receiveCharacteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if receiveCharacteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            fail("Click RideOn control is not writable")
            return
        }
        for characteristic in [asyncCharacteristic, transmitCharacteristic] {
            guard characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) else {
                fail("\(characteristic.uuid) cannot notify or indicate")
                return
            }
            peripheral?.setNotifyValue(true, for: characteristic)
        }
        if let batteryCharacteristic {
            if batteryCharacteristic.properties.contains(.read) {
                peripheral?.readValue(for: batteryCharacteristic)
            }
            if batteryCharacteristic.properties.contains(.notify)
                || batteryCharacteristic.properties.contains(.indicate) {
                peripheral?.setNotifyValue(true, for: batteryCharacteristic)
            }
        }
        state = .preparing
    }

    private func sendHandshakeIfReady() {
        guard !isSuspendedForDemo,
              subscribed.contains(asyncUUID),
              subscribed.contains(transmitUUID),
              !handshakeSent,
              let peripheral,
              let receiveCharacteristic,
              let writeType else { return }
        handshakeSent = true
        peripheral.writeValue(
            ZwiftClickProtocol.rideOn,
            for: receiveCharacteristic,
            type: writeType
        )
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let self, self.handshakeSent, !self.isReady else { return }
            self.fail("Click handshake timed out after 5 seconds")
        }
    }

    private func processAsync(_ data: Data) {
        do {
            switch try ZwiftClickMessageDecoder.decode(data) {
            case let .buttons(plus, minus):
                if plus && minus {
                    for event in edgeTracker.update(plus: true, minus: true) {
                        latestButtonEvent = event
                    }
                    stopRepeat()
                    log("Ignored simultaneous plus/minus press", level: .warning)
                    return
                }
                for event in edgeTracker.update(plus: plus, minus: minus) {
                    latestButtonEvent = event
                    if identificationCandidateID == nil {
                        process(event)
                    }
                }
            case let .batteryLevel(percent):
                // The Click repeats this every few seconds, so it keeps the
                // reading current during a ride. The standard Bluetooth
                // characteristic is only guaranteed to be readable once on
                // connect, and this device does not always announce changes to
                // it, so without this the level would be frozen at whatever it
                // was when the Click connected.
                if batteryLevel != percent {
                    batteryLevel = percent
                }
            case .keepAlive:
                break
            case let .other(type):
                log("Ignored Click message type \(type)")
            }
        } catch {
            log("Invalid Click packet: \(error)", level: .error)
        }
    }

    private func process(_ event: ZwiftClickButtonEvent) {
        switch event {
        case let .pressed(button):
            guard heldButton == nil else {
                stopRepeat()
                log("Ignored overlapping Click press", level: .warning)
                return
            }
            heldButton = button
            emit(.single(direction(for: button)))
            startRepeat(button)
        case let .released(button):
            if heldButton == button { stopRepeat() }
        }
    }

    private func startRepeat(_ button: ZwiftClickButton) {
        repeatTask?.cancel()
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard let self, self.heldButton == button else { return }
            // Said once, not on a timer. The trainer confirms one gear at a
            // time, and a timer that fires faster than that either queues up
            // gears that arrive after the rider lets go, or has its beats
            // dropped and sweeps in fits and starts. Handing over to the
            // trainer's own pace avoids both.
            self.isHolding = true
            self.emit(.holdBegan(self.direction(for: button)))
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        heldButton = nil
        if isHolding {
            isHolding = false
            emit(.holdEnded)
        }
    }

    private func direction(for button: ZwiftClickButton) -> ShiftDirection {
        button == .plus ? .harder : .easier
    }

    private func emit(_ request: ShiftRequest) {
        latestShiftRequest = request
        shiftRequests.append(request)
        if shiftRequests.count > 50 {
            shiftRequests.removeFirst(shiftRequests.count - 50)
        }
        shiftHandler?(request)
    }

    private func resetConnection(keepingPeripheral: Bool = false) {
        handshakeTimeoutTask?.cancel()
        stopRepeat()
        asyncCharacteristic = nil
        receiveCharacteristic = nil
        transmitCharacteristic = nil
        batteryCharacteristic = nil
        writeType = nil
        subscribed.removeAll()
        servicesPending = 0
        handshakeSent = false
        edgeTracker = ZwiftClickEdgeTracker()
        batteryLevel = nil
        if !keepingPeripheral { peripheral = nil }
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

    private func fail(_ message: String) {
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
        ProductLogger.record(message, source: "Click", level: level)
    }
}

#if DEBUG
extension ClickCentralService {
    func stageScreenshot(name: String, batteryLevel: Int) {
        selectedID = ScreenshotFixture.clickID
        selectedName = name
        self.batteryLevel = batteryLevel
        state = .ready
    }
}
#endif

extension ClickCentralService: @preconcurrency CBCentralManagerDelegate {
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
        let name = advertised ?? peripheral.name ?? "Zwift Click"
        discovered[peripheral.identifier] = peripheral
        let item = BluetoothCandidate(
            id: peripheral.identifier,
            name: name
        )
        candidates.absorb(item)
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
        peripheral.discoverServices([serviceUUID, batteryServiceUUID])
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
        if desiredConnection { scheduleReconnect() }
    }
}

extension ClickCentralService: @preconcurrency CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        if let error {
            fail("Click service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services,
              services.contains(where: { $0.uuid == serviceUUID }) else {
            fail("Original Zwift Click service was not found")
            return
        }
        servicesPending = services.count
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics(
                    [asyncUUID, receiveUUID, transmitUUID],
                    for: service
                )
            } else {
                peripheral.discoverCharacteristics([batteryUUID], for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        servicesPending -= 1
        if let error {
            if service.uuid == batteryServiceUUID {
                log("Battery discovery unavailable: "
                    + error.localizedDescription, level: .warning)
                if servicesPending == 0 { finishDiscovery() }
            } else {
                fail("Click control discovery failed: \(error.localizedDescription)")
            }
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case asyncUUID: asyncCharacteristic = characteristic
            case receiveUUID: receiveCharacteristic = characteristic
            case transmitUUID: transmitCharacteristic = characteristic
            case batteryUUID: batteryCharacteristic = characteristic
            default: break
            }
        }
        if servicesPending == 0 { finishDiscovery() }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        if let error {
            if characteristic.uuid == batteryUUID {
                log("Battery notification unavailable: "
                    + error.localizedDescription, level: .warning)
            } else {
                fail("Click subscription failed: \(error.localizedDescription)")
            }
            return
        }
        if characteristic.isNotifying {
            subscribed.insert(characteristic.uuid)
            sendHandshakeIfReady()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        guard characteristic.uuid == receiveUUID, let error else { return }
        handshakeTimeoutTask?.cancel()
        fail("Click handshake write failed: \(error.localizedDescription)")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !isSuspendedForDemo else { return }
        if let error {
            log("\(characteristic.uuid) update failed: "
                + error.localizedDescription, level: .error)
            return
        }
        guard let data = characteristic.value else {
            log("\(characteristic.uuid) returned no value", level: .error)
            return
        }
        if characteristic.uuid == batteryUUID {
            guard let value = data.first, value <= 100 else {
                log("Click returned an invalid battery level", level: .error)
                return
            }
            batteryLevel = Int(value)
        } else if characteristic.uuid == transmitUUID {
            guard data.starts(with: ZwiftClickProtocol.rideOn) else {
                fail("Click returned an unexpected handshake reply")
                return
            }
            handshakeTimeoutTask?.cancel()
            state = .ready
        } else if characteristic.uuid == asyncUUID, isReady {
            processAsync(data)
        }
    }
}
