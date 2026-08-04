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
    case campagnoloRoad12
    case mountain1x12
    case mountain1x11
    case simple1x

    var id: Self { self }

    /// Plain names a rider recognises. Chain-notation such as "2x12" belongs in
    /// `specification`, not here, because it means nothing to a first-time user.
    var name: String {
        switch self {
        case .zwiftVirtual24:
            "Virtual gears"
        case .shimano105Di2:
            "Shimano road bike"
        case .shimanoRoad2x11:
            "Shimano road bike, classic"
        case .sramRoadAxs:
            "SRAM road bike"
        case .shimanoGrx12:
            "Shimano gravel bike"
        case .sramXplr12:
            "SRAM gravel bike"
        case .sramXplr13:
            "SRAM gravel bike, wide"
        case .campagnoloEkar13:
            "Campagnolo gravel bike"
        case .campagnoloRoad12:
            "Campagnolo road bike"
        case .mountain1x12:
            "Mountain bike"
        case .mountain1x11:
            "Mountain bike, classic"
        case .simple1x:
            "Simple 10-speed"
        }
    }

    /// The one line a rider needs to choose: how many gears, and what they suit.
    var summary: String {
        "\(gearCount) gears · \(suitedFor)"
    }

    var gearCount: Int { drivetrain.gears.count }

    private var suitedFor: String {
        switch self {
        case .zwiftVirtual24:
            "the widest range"
        case .shimano105Di2, .shimanoRoad2x11, .sramRoadAxs, .campagnoloRoad12:
            "flat and rolling roads"
        case .shimanoGrx12, .sramXplr12, .campagnoloEkar13:
            "mixed roads and hills"
        case .sramXplr13:
            "hills and gravel, easy climbing"
        case .mountain1x12, .mountain1x11:
            "steep climbs, very easy gears"
        case .simple1x:
            "bigger jumps between gears"
        }
    }

    /// Tooth counts for riders who want them. Kept out of the way of everyone else.
    var specification: String {
        switch self {
        case .zwiftVirtual24:
            "Evenly spaced virtual ratios, not copied from a real bike"
        case .shimano105Di2:
            "2×12 · 50/34 chainrings · 11–34 cassette"
        case .shimanoRoad2x11:
            "2×11 · 50/34 chainrings · 11–32 cassette"
        case .sramRoadAxs:
            "2×12 · 46/33 chainrings · 10–33 cassette"
        case .shimanoGrx12:
            "2×12 · 48/31 chainrings · 11–36 cassette"
        case .sramXplr12:
            "1×12 · 40 chainring · 10–44 cassette"
        case .sramXplr13:
            "1×13 · 44 chainring · 10–46 cassette"
        case .campagnoloEkar13:
            "1×13 · 40 chainring · 9–42 cassette"
        case .campagnoloRoad12:
            "2×12 · 45/29 chainrings · 10–27 cassette"
        case .mountain1x12:
            "1×12 · 32 chainring · 10–51 cassette"
        case .mountain1x11:
            "1×11 · 32 chainring · 11–46 cassette"
        case .simple1x:
            "1×10 · 42 chainring · 11–42 cassette"
        }
    }

    var category: String {
        switch self {
        case .zwiftVirtual24:
            "Virtual"
        case .shimano105Di2, .shimanoRoad2x11, .sramRoadAxs, .campagnoloRoad12:
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
        case .shimano105Di2, .shimanoRoad2x11, .sramRoadAxs, .campagnoloRoad12:
            "road.lanes"
        case .shimanoGrx12, .sramXplr12, .sramXplr13, .campagnoloEkar13:
            "leaf.fill"
        case .mountain1x12, .mountain1x11:
            "mountain.2.fill"
        case .simple1x:
            "gearshape.fill"
        }
    }

    /// Explains what the numbers on the ride screen will mean.
    var setupDescription: String {
        "Gear 1 is the easiest for climbing and gear \(gearCount) is the hardest "
            + "for speed. Every ride starts in gear \(drivetrain.referenceIndex + 1)."
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
        case .campagnoloRoad12:
            return .campagnoloRoad2x12
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
