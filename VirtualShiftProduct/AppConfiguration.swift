import Foundation
import Observation
import VirtualShiftCore

struct AppConfiguration: Codable, Equatable {
    var kickrName = ""
    var kickrUUID = ""
    var usesClick = true
    var clickName = ""
    var clickUUID = ""
    var drivetrainPreset = DrivetrainPreset.zwiftVirtual24
    var setupComplete = false

    var neutralCircumferenceMillimeters: Int { 2_070 }

    var hasValidKickr: Bool {
        !kickrName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: kickrUUID) != nil
    }

    var hasValidClick: Bool {
        !usesClick || (
            !clickName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && UUID(uuidString: clickUUID) != nil
        )
    }

    var hasSafeCircumference: Bool {
        guard (try? ConfirmedGearEngine(
            drivetrain: drivetrainPreset.drivetrain,
            baselineCircumferenceMillimeters:
                Double(neutralCircumferenceMillimeters)
        )) != nil else {
            return false
        }

        let drivetrain = drivetrainPreset.drivetrain
        return drivetrain.gears.allSatisfy { gear in
            guard let circumference = try? WheelCircumferenceScaler
                .effectiveCircumference(
                    neutralCircumference:
                        Double(neutralCircumferenceMillimeters),
                    referenceRatio: drivetrain.referenceGear.ratio,
                    selectedRatio: gear.ratio
                ),
                let command = try? WahooKickrCommand.setWheelCircumference(
                    millimeters: circumference
                ) else {
                return false
            }
            let bytes = Array(command)
            let encoded = Int(bytes[1]) | Int(bytes[2]) << 8
            return (6_469...48_000).contains(encoded)
        }
    }

    var canFinishSetup: Bool {
        hasValidKickr
            && hasValidClick
            && hasSafeCircumference
    }
}

enum DrivetrainPreset: String, Codable, CaseIterable, Identifiable {
    case zwiftVirtual24
    case shimano105Di2
    case sramRoadAxs
    case shimanoGrx12
    case sramXplr12
    case mountain1x12
    case simple1x

    var id: Self { self }

    var name: String {
        switch self {
        case .zwiftVirtual24:
            "Zwift Virtual 24"
        case .shimano105Di2:
            "Shimano Road 2×12"
        case .sramRoadAxs:
            "SRAM Road AXS 2×12"
        case .shimanoGrx12:
            "Shimano GRX 2×12"
        case .sramXplr12:
            "SRAM XPLR 1×12"
        case .mountain1x12:
            "MTB 1×12"
        case .simple1x:
            "Classic 1×10"
        }
    }

    var detail: String {
        switch self {
        case .zwiftVirtual24:
            "24 numbered gears · 0.75–5.49"
        case .shimano105Di2:
            "2×12 · 50/34 · 11–34"
        case .sramRoadAxs:
            "2×12 · 46/33 · 10–33"
        case .shimanoGrx12:
            "2×12 · 48/31 · 11–36"
        case .sramXplr12:
            "1×12 · 40 · 10–44"
        case .mountain1x12:
            "1×12 · 32 · 10–51"
        case .simple1x:
            "1×10 · 42 · 11–42"
        }
    }

    var category: String {
        switch self {
        case .zwiftVirtual24:
            "Virtual"
        case .shimano105Di2, .sramRoadAxs:
            "Road"
        case .shimanoGrx12, .sramXplr12:
            "Gravel"
        case .mountain1x12:
            "Mountain"
        case .simple1x:
            "Simple"
        }
    }

    var symbol: String {
        switch self {
        case .zwiftVirtual24:
            "number.circle.fill"
        case .shimano105Di2, .sramRoadAxs:
            "road.lanes"
        case .shimanoGrx12, .sramXplr12:
            "leaf.fill"
        case .mountain1x12:
            "mountain.2.fill"
        case .simple1x:
            "gearshape.fill"
        }
    }

    var setupDescription: String {
        switch self {
        case .zwiftVirtual24:
            "The default Zwift-style sequence uses 24 numbered gears. Gear 12 "
                + "is the neutral starting point."
        case .shimano105Di2:
            "17 sequential combinations; duplicate ratios and extreme "
                + "cross-chaining are excluded."
        case .sramRoadAxs:
            "16 sequential combinations model a wide-range wireless road setup."
        case .shimanoGrx12:
            "17 sequential combinations balance gravel climbing and road speed."
        case .sramXplr12:
            "12 simple sequential gears model a wide-range gravel drivetrain."
        case .mountain1x12:
            "12 sequential gears cover a broad 10–51 tooth mountain range."
        case .simple1x:
            "10 sequential combinations from the defined 42-tooth drivetrain."
        }
    }

    var drivetrain: Drivetrain {
        switch self {
        case .zwiftVirtual24:
            return .zwiftVirtual24
        case .shimano105Di2:
            return .shimanoRoad2x12
        case .sramRoadAxs:
            return .sramRoadAxs2x12
        case .shimanoGrx12:
            return .shimanoGrx2x12
        case .sramXplr12:
            return .sramXplr1x12
        case .mountain1x12:
            return .mountain1x12
        case .simple1x:
            return .classic1x10
        }
    }
}

@MainActor
@Observable
final class ConfigurationStore {
    private static let storageKey = "VirtualShift.appConfiguration"
    private let defaults: UserDefaults

    var configuration: AppConfiguration {
        didSet {
            if configuration.setupComplete
                && !configuration.canFinishSetup {
                configuration.setupComplete = false
                return
            }
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded: AppConfiguration
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            loaded = saved
        } else {
            loaded = AppConfiguration()
        }
        configuration = loaded
        if configuration.setupComplete && !configuration.canFinishSetup {
            configuration.setupComplete = false
            save()
        }
    }

    func setDrivetrainPreset(_ preset: DrivetrainPreset) {
        configuration.drivetrainPreset = preset
    }

    func finishSetup() {
        guard configuration.canFinishSetup else { return }
        configuration.setupComplete = true
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
