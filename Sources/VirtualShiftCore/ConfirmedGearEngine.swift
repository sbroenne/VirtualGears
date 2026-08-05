import Foundation

public struct PendingGearChange: Equatable, Sendable {
    public let index: Int
    public let gear: VirtualGear
    public let circumferenceMillimeters: Double
    public let command: Data
}

public struct ConfirmedGearEngine: Sendable {
    public let drivetrain: Drivetrain
    public let baselineCircumferenceMillimeters: Double

    public private(set) var requestedIndex: Int
    public private(set) var confirmedIndex: Int
    public private(set) var pendingChange: PendingGearChange?

    private let changes: [PendingGearChange]

    public init(
        drivetrain: Drivetrain,
        baselineCircumferenceMillimeters: Double
    ) throws {
        let referenceRatio = drivetrain.referenceGear.ratio
        var changes: [PendingGearChange] = []
        for (index, gear) in drivetrain.gears.enumerated() {
            let circumference =
                try WheelCircumferenceScaler.effectiveCircumference(
                    neutralCircumference:
                        baselineCircumferenceMillimeters,
                    referenceRatio: referenceRatio,
                    selectedRatio: gear.ratio
                )
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: circumference
            )
            changes.append(
                PendingGearChange(
                    index: index,
                    gear: gear,
                    circumferenceMillimeters: circumference,
                    command: command
                )
            )
        }

        self.drivetrain = drivetrain
        self.baselineCircumferenceMillimeters =
            baselineCircumferenceMillimeters
        requestedIndex = drivetrain.referenceIndex
        confirmedIndex = drivetrain.referenceIndex
        pendingChange = nil
        self.changes = changes
    }

    /// True when the trainer has caught up with everything asked of it.
    /// Holding a shift button waits for this, so a hold asks for gears at the
    /// trainer's pace and stops the moment the rider lets go.
    public var isSettled: Bool {
        requestedIndex == confirmedIndex
    }

    public var requestedGear: VirtualGear {
        drivetrain.gears[requestedIndex]
    }

    public var confirmedGear: VirtualGear {
        drivetrain.gears[confirmedIndex]
    }

    public var confirmedSetting: PendingGearChange {
        changes[confirmedIndex]
    }

    /// Recalculates effective circumferences while preserving the displayed gear.
    /// Any unconfirmed requested shifts are intentionally discarded.
    public func rebased(
        baselineCircumferenceMillimeters: Double
    ) throws -> Self {
        var result = try Self(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters: baselineCircumferenceMillimeters
        )
        result.requestedIndex = confirmedIndex
        result.confirmedIndex = confirmedIndex
        return result
    }

    @discardableResult
    public mutating func requestShift(
        by stepCount: Int
    ) -> PendingGearChange? {
        if stepCount > 0 {
            let available = drivetrain.gears.count - 1 - requestedIndex
            requestedIndex += min(stepCount, available)
        } else if stepCount < 0 {
            requestedIndex += max(stepCount, -requestedIndex)
        }

        return prepareNextChange()
    }

    @discardableResult
    public mutating func acknowledge(
        _ response: WahooKickrResponse
    ) -> PendingGearChange? {
        guard let pendingChange,
              case let .wheelCircumference(result, _) = response,
              result == 1,
              response.verifies(command: pendingChange.command)
        else {
            return nil
        }

        confirmedIndex = pendingChange.index
        self.pendingChange = nil
        return prepareNextChange()
    }

    public mutating func cancelPendingChanges() {
        requestedIndex = confirmedIndex
        pendingChange = nil
    }

    private mutating func prepareNextChange() -> PendingGearChange? {
        guard pendingChange == nil else {
            return nil
        }

        while confirmedIndex != requestedIndex {
            let nextIndex =
                confirmedIndex + (requestedIndex > confirmedIndex ? 1 : -1)
            let change = changes[nextIndex]

            // The trainer has already confirmed this exact encoded state.
            if changes[confirmedIndex].command == change.command {
                confirmedIndex = nextIndex
                continue
            }

            pendingChange = change
            return change
        }
        return nil
    }
}
