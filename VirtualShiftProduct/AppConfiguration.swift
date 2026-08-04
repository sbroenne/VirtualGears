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
    case shimanoRoad2x11
    case sramRoadAxs
    case shimanoGrx12
    case sramXplr12
    case sramXplr13
    case campagnoloEkar13
    case mountain1x12
    case mountain1x11
    case simple1x

    var id: Self { self }

    var name: String {
        switch self {
        case .zwiftVirtual24:
            "Zwift Virtual 24"
        case .shimano105Di2:
            "Shimano Road 2×12"
        case .shimanoRoad2x11:
            "Shimano Road 2×11"
        case .sramRoadAxs:
            "SRAM Road AXS 2×12"
        case .shimanoGrx12:
            "Shimano GRX 2×12"
        case .sramXplr12:
            "SRAM XPLR 1×12"
        case .sramXplr13:
            "SRAM Red XPLR 1×13"
        case .campagnoloEkar13:
            "Campagnolo Ekar 1×13"
        case .mountain1x12:
            "MTB 1×12"
        case .mountain1x11:
            "MTB 1×11"
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
        case .shimanoRoad2x11:
            "2×11 · 50/34 · 11–32"
        case .sramRoadAxs:
            "2×12 · 46/33 · 10–33"
        case .shimanoGrx12:
            "2×12 · 48/31 · 11–36"
        case .sramXplr12:
            "1×12 · 40 · 10–44"
        case .sramXplr13:
            "1×13 · 44 · 10–46"
        case .campagnoloEkar13:
            "1×13 · 40 · 9–42"
        case .mountain1x12:
            "1×12 · 32 · 10–51"
        case .mountain1x11:
            "1×11 · 32 · 11–46"
        case .simple1x:
            "1×10 · 42 · 11–42"
        }
    }

    var category: String {
        switch self {
        case .zwiftVirtual24:
            "Virtual"
        case .shimano105Di2, .shimanoRoad2x11, .sramRoadAxs:
            "Road"
        case .shimanoGrx12, .sramXplr12, .sramXplr13, .campagnoloEkar13:
            "Gravel"
        case .mountain1x12, .mountain1x11:
            "Mountain"
        case .simple1x:
            "Simple"
        }
    }

    var symbol: String {
        switch self {
        case .zwiftVirtual24:
            "number.circle.fill"
        case .shimano105Di2, .shimanoRoad2x11, .sramRoadAxs:
            "road.lanes"
        case .shimanoGrx12, .sramXplr12, .sramXplr13, .campagnoloEkar13:
            "leaf.fill"
        case .mountain1x12, .mountain1x11:
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
        case .shimanoRoad2x11:
            "15 sequential combinations model a classic 11-speed road bike."
        case .sramRoadAxs:
            "16 sequential combinations model a wide-range wireless road setup."
        case .shimanoGrx12:
            "17 sequential combinations balance gravel climbing and road speed."
        case .sramXplr12:
            "12 simple sequential gears model a wide-range gravel drivetrain."
        case .sramXplr13:
            "13 sequential gears model the wide 10–46 tooth 13-speed gravel range."
        case .campagnoloEkar13:
            "13 sequential gears model the tightly spaced 9–42 tooth Ekar range."
        case .mountain1x12:
            "12 sequential gears cover a broad 10–51 tooth mountain range."
        case .mountain1x11:
            "11 sequential gears model an 11-speed mountain drivetrain."
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
        case .shimanoRoad2x11:
            return .shimanoRoad2x11
        case .sramRoadAxs:
            return .sramRoadAxs2x12
        case .shimanoGrx12:
            return .shimanoGrx2x12
        case .sramXplr12:
            return .sramXplr1x12
        case .sramXplr13:
            return .sramXplr1x13
        case .campagnoloEkar13:
            return .campagnoloEkar1x13
        case .mountain1x12:
            return .mountain1x12
        case .mountain1x11:
            return .mountain1x11
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
