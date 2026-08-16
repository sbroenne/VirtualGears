/// Everything the app needs to know before deciding whether to say anything to
/// a fan. Gathered into one value so the decision can be made, and checked,
/// without a fan in the room.
public struct HeadwindSituation: Equatable, Sendable {
    /// Whether a ride is what is asking for the fan. Merely being connected is
    /// not: opening the app to change a setting must never start it blowing.
    public var weAreDrivingTheFan: Bool
    /// Whether the app is on its way out and giving the fan back to its own
    /// sensor, which it must do even when it would otherwise stay quiet.
    public var isHandingBack: Bool
    public var wantsManualControl: Bool
    public var desiredManualSpeed: Int
    public var lastSensorMode: HeadwindMode
    /// What the fan is doing now, as far as the app has been told. Nil before
    /// it has said anything.
    public var observedMode: HeadwindMode?
    public var observedManualSpeed: Int

    public init(
        weAreDrivingTheFan: Bool = false,
        isHandingBack: Bool = false,
        wantsManualControl: Bool = false,
        desiredManualSpeed: Int = 50,
        lastSensorMode: HeadwindMode = .heartRate,
        observedMode: HeadwindMode? = nil,
        observedManualSpeed: Int = 0
    ) {
        self.weAreDrivingTheFan = weAreDrivingTheFan
        self.isHandingBack = isHandingBack
        self.wantsManualControl = wantsManualControl
        self.desiredManualSpeed = desiredManualSpeed
        self.lastSensorMode = lastSensorMode
        self.observedMode = observedMode
        self.observedManualSpeed = observedManualSpeed
    }
}

/// When the app may speak to a fan, and what it may say.
///
/// A fan is not a setting on a screen. Anything sent to one moves real air in
/// the rider's face, so the rule is deliberately narrow: say nothing unless
/// there is a reason, and treat starting a fan as needing a better reason than
/// stopping one.
public enum HeadwindControlPolicy {
    /// The commands to send for a situation, in order. An empty result means
    /// the right thing to do is nothing, which is the common case.
    public static func commands(for situation: HeadwindSituation) -> [HeadwindCommand] {
        // Handing the fan back always wins. Refusing to start a fan must never
        // turn into refusing to stop one, so this is checked before anything
        // that could hold its tongue.
        if situation.isHandingBack {
            return [.setMode(situation.lastSensorMode)]
        }
        // Only a ride speaks for the rider. A connection does not.
        guard situation.weAreDrivingTheFan else { return [] }
        // Only a manual preference is worth asserting. Sensor control means the
        // fan answers to its own sensor, so there is nothing of the app's to
        // put back and no reason to send a mode command.
        guard situation.wantsManualControl else { return [] }

        var commands: [HeadwindCommand] = []
        let isManual = situation.observedMode == .manual
        if !isManual {
            commands.append(.setMode(.manual))
        }
        if !isManual || situation.observedManualSpeed != situation.desiredManualSpeed {
            commands.append(.setManualSpeed(situation.desiredManualSpeed))
        }
        return commands
    }
}

/// One authoritative state report from a Headwind. The manual speed remains
/// meaningful outside manual mode because the fan remembers it for the next
/// time manual mode is selected.
public struct HeadwindState: Equatable, Sendable {
    public var mode: HeadwindMode
    public var manualSpeed: Int

    public init(mode: HeadwindMode, manualSpeed: Int) {
        self.mode = mode
        self.manualSpeed = min(100, max(0, manualSpeed))
    }

    public func applying(_ command: HeadwindCommand) -> Self {
        switch command {
        case let .setMode(mode):
            return .init(mode: mode, manualSpeed: manualSpeed)
        case let .setManualSpeed(speed):
            return .init(mode: .manual, manualSpeed: speed)
        }
    }

    public func matches(_ other: Self) -> Bool {
        mode == other.mode
            && (mode != .manual || manualSpeed == other.manualSpeed)
    }
}

/// Plans the shortest ordered command sequence that restores an exact state.
public enum HeadwindRestorationPolicy {
    public static func commands(
        restoring target: HeadwindState,
        from current: HeadwindState
    ) -> [HeadwindCommand] {
        guard !current.matches(target) else { return [] }
        guard target.mode == .manual else {
            return current.mode == target.mode ? [] : [.setMode(target.mode)]
        }

        var commands: [HeadwindCommand] = []
        if current.mode != .manual {
            commands.append(.setMode(.manual))
        }
        if current.manualSpeed != target.manualSpeed {
            commands.append(.setManualSpeed(target.manualSpeed))
        }
        return commands
    }
}

/// Owns the pre-control snapshot for exactly one shifting lifecycle.
public struct HeadwindControlLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case awaitingBaseline
        case controlling(HeadwindState)
        case restoring(HeadwindState)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public var isAwaitingBaseline: Bool {
        phase == .awaitingBaseline
    }

    public var restorationTarget: HeadwindState? {
        guard case let .restoring(state) = phase else { return nil }
        return state
    }

    /// Returns true when control may be applied immediately. Repeated starts do
    /// not replace the original baseline.
    @discardableResult
    public mutating func begin(
        observedState: HeadwindState?,
        hasUnsettledCommand: Bool
    ) -> Bool {
        switch phase {
        case .controlling, .awaitingBaseline:
            return false
        case .idle, .restoring:
            guard !hasUnsettledCommand, let observedState else {
                phase = .awaitingBaseline
                return false
            }
            phase = .controlling(observedState)
            return true
        }
    }

    /// Captures only an authoritative state notification, never a requested or
    /// projected state.
    @discardableResult
    public mutating func observeAuthoritative(
        _ state: HeadwindState,
        hasUnsettledCommand: Bool = false
    ) -> Bool {
        guard phase == .awaitingBaseline, !hasUnsettledCommand else {
            return false
        }
        phase = .controlling(state)
        return true
    }

    @discardableResult
    public mutating func beginRestoration() -> HeadwindState? {
        switch phase {
        case .idle:
            return nil
        case .awaitingBaseline:
            phase = .idle
            return nil
        case let .controlling(state):
            phase = .restoring(state)
            return state
        case let .restoring(state):
            return state
        }
    }

    @discardableResult
    public mutating func finishRestoration(ifObserved state: HeadwindState) -> Bool {
        guard case let .restoring(target) = phase, state.matches(target) else {
            return false
        }
        phase = .idle
        return true
    }

    /// A replacement fan needs its own baseline, not the removed fan's state.
    public mutating func deviceChanged(whileControlling: Bool) {
        phase = whileControlling ? .awaitingBaseline : .idle
    }
}
