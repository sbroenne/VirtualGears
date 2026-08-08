import Foundation

/// Local ride state for the in-app demonstration.
///
/// It deliberately knows nothing about Bluetooth, the ride coordinator or
/// persistence. The demo can therefore exercise the same drivetrain choices and
/// visible gear ladder without creating a path to real equipment.
public struct DemoRideState: Equatable, Sendable {
    public private(set) var gearSequence: [VirtualGear]
    public private(set) var selectedIndex: Int

    public init(configuration: AppConfiguration) {
        let drivetrain = configuration.drivetrain
        gearSequence = drivetrain?.gears ?? []
        selectedIndex = drivetrain?.referenceIndex ?? 0
    }

    public var displayedGear: VirtualGear? {
        guard gearSequence.indices.contains(selectedIndex) else { return nil }
        return gearSequence[selectedIndex]
    }

    public var canShiftEasier: Bool {
        !gearSequence.isEmpty && selectedIndex > 0
    }

    public var canShiftHarder: Bool {
        selectedIndex + 1 < gearSequence.count
    }

    public mutating func shift(_ direction: ShiftDirection) {
        switch direction {
        case .easier where canShiftEasier:
            selectedIndex -= 1
        case .harder where canShiftHarder:
            selectedIndex += 1
        default:
            break
        }
    }

    public mutating func use(_ configuration: AppConfiguration) {
        self = Self(configuration: configuration)
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
