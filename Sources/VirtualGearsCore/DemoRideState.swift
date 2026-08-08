import Foundation

/// A stand-in for the trainer, used only by the in-app demonstration.
///
/// It replies in the KICKR's own wire format, so the demo runs the shipping
/// command encoder, the shipping response decoder and the shipping
/// acknowledgement check. Only the radio is missing.
enum DemoTrainer {
    /// The reply a KICKR sends after accepting a wheel-size command: the same
    /// encoded value echoed back, with a success result.
    static func reply(to command: Data) -> Data? {
        let bytes = Array(command)
        guard bytes.count == 3, bytes[0] == 0x48 else { return nil }
        return Data([0x01, 0x48, 0x01, 0x00, bytes[1], bytes[2]])
    }
}

/// A short looping route for the simulated riding app to ride through.
///
/// Fixed rather than random so the demo behaves the same every time and can be
/// tested.
public struct DemoRoute: Equatable, Sendable {
    static let gradesPercent: [Double] = [
        0, 0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6, 5, 4, 3, 2,
        1, 0, -1, -2, -3, -2.5, -1.5, -0.5,
    ]

    public private(set) var step = 0

    public init() {}

    public var gradePercent: Double {
        Self.gradesPercent[step % Self.gradesPercent.count]
    }

    /// What the rider sees the riding app doing to the terrain.
    public var terrainDescription: String {
        let grade = gradePercent
        if grade > 0.75 {
            return "Climbing \(formatted(grade))%"
        }
        if grade < -0.75 {
            return "Descending \(formatted(abs(grade)))%"
        }
        return "Flat"
    }

    public mutating func advance() {
        step += 1
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

/// Local ride state for the in-app demonstration.
///
/// It deliberately knows nothing about Bluetooth, the ride coordinator or
/// persistence. What it does use is the real `ConfirmedGearEngine`, so the
/// wheel sizes and command bytes it shows are the ones a real ride would send,
/// and a gear only appears once the simulated trainer has confirmed it.
public struct DemoRideState: Equatable, Sendable {
    public private(set) var gearSequence: [VirtualGear]
    /// The gear on screen. Only ever a gear the trainer has confirmed.
    public private(set) var selectedIndex: Int
    public private(set) var route = DemoRoute()

    /// The real engine, absent only if a drivetrain cannot be built.
    private var engine: ConfirmedGearEngine?

    public init(configuration: AppConfiguration) {
        let drivetrain = configuration.drivetrain
        gearSequence = drivetrain?.gears ?? []
        selectedIndex = drivetrain?.referenceIndex ?? 0
        engine = drivetrain.flatMap {
            try? ConfirmedGearEngine(
                drivetrain: $0,
                baselineCircumferenceMillimeters:
                    TrainerSafety.referenceCircumferenceMillimeters
            )
        }
    }

    public var displayedGear: VirtualGear? {
        guard gearSequence.indices.contains(selectedIndex) else { return nil }
        return gearSequence[selectedIndex]
    }

    /// The gear the rider has asked for, which may be ahead of the one shown
    /// while the trainer catches up.
    public var requestedIndex: Int {
        engine?.requestedIndex ?? selectedIndex
    }

    /// The wheel size the trainer is currently set to for the displayed gear.
    public var circumferenceMillimeters: Double? {
        engine?.confirmedSetting.circumferenceMillimeters
    }

    /// The wheel size being asked for right now, while it is unconfirmed.
    public var pendingCircumferenceMillimeters: Double? {
        engine?.pendingChange?.circumferenceMillimeters
    }

    /// The bytes that would go to the trainer for the gear in play, shown so
    /// the demo can be honest about what the app actually sends.
    public var commandDescription: String? {
        guard let engine else { return nil }
        let command = engine.pendingChange?.command
            ?? engine.confirmedSetting.command
        return Array(command)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }

    /// The wheel size the gears are built around, as a real riding app would
    /// have left it.
    public var baselineMillimeters: Double {
        engine?.baselineCircumferenceMillimeters
            ?? TrainerSafety.referenceCircumferenceMillimeters
    }

    /// True once the trainer has caught up with every shift asked of it.
    public var isSettled: Bool {
        engine?.isSettled ?? true
    }

    public var isAwaitingTrainer: Bool {
        engine?.pendingChange != nil
    }

    public var canShiftEasier: Bool {
        !gearSequence.isEmpty && requestedIndex > 0
    }

    public var canShiftHarder: Bool {
        requestedIndex + 1 < gearSequence.count
    }

    public mutating func shift(_ direction: ShiftDirection) {
        guard engine != nil else { return }
        switch direction {
        case .easier where canShiftEasier:
            engine?.requestShift(by: -1)
        case .harder where canShiftHarder:
            engine?.requestShift(by: 1)
        default:
            break
        }
    }

    /// The simulated trainer answering the outstanding command. Returns true
    /// when a gear was confirmed, so the caller knows the screen changed.
    @discardableResult
    public mutating func confirmPendingChange() -> Bool {
        guard let pending = engine?.pendingChange,
              let data = DemoTrainer.reply(to: pending.command),
              let response = try? WahooKickrResponse.decode(data)
        else {
            return false
        }

        engine?.acknowledge(response)
        selectedIndex = engine?.confirmedIndex ?? selectedIndex
        return true
    }

    /// Lets the trainer catch up completely, as holding a shift button does.
    public mutating func settle() {
        while confirmPendingChange() {}
    }

    /// The simulated riding app moving on to the next piece of terrain. This
    /// travels on its own channel and never disturbs the gears.
    public mutating func advanceRoute() {
        route.advance()
    }

    public mutating func use(_ configuration: AppConfiguration) {
        let route = route
        self = Self(configuration: configuration)
        self.route = route
    }
}

public extension AppConfiguration {
    /// A complete but unmistakably simulated setup for the in-app demo.
    ///
    /// The app keeps this value in memory only. These stable identifiers exist
    /// solely so ordinary configuration descriptions can be reused.
    static var demo: Self {
        var configuration = Self()
        configuration.rememberKickr(
            named: "Simulated trainer",
            id: UUID(uuidString: "D3000000-0000-0000-0000-000000000001")!
        )
        configuration.rememberClick(
            named: "Simulated Click",
            id: UUID(uuidString: "D3000000-0000-0000-0000-000000000002")!
        )
        configuration.rememberHeadwind(
            named: "Simulated Headwind",
            id: UUID(uuidString: "D3000000-0000-0000-0000-000000000003")!
        )
        return configuration
    }
}
