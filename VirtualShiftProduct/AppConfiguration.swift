import Foundation
import Observation
import VirtualShiftCore

struct AppConfiguration: Codable, Equatable {
    var kickrName = ""
    var kickrUUID = ""
    var usesClick = false
    var clickName = ""
    var clickUUID = ""
    var neutralCircumferenceMillimeters = 2070
    var confirmedCircumferenceMillimeters: Int?
    var drivetrainPreset = DrivetrainPreset.zwiftVirtual24
    var setupComplete = false

    var isCircumferenceConfirmed: Bool {
        confirmedCircumferenceMillimeters == neutralCircumferenceMillimeters
    }

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
            && isCircumferenceConfirmed
            && hasSafeCircumference
    }
}

enum DrivetrainPreset: String, Codable, CaseIterable, Identifiable {
    case zwiftVirtual24
    case shimano105Di2
    case simple1x

    var id: Self { self }

    var name: String {
        switch self {
        case .zwiftVirtual24:
            "Zwift Virtual 24"
        case .shimano105Di2:
            "Shimano 105 Di2–like"
        case .simple1x:
            "Simple 1×10"
        }
    }

    var detail: String {
        switch self {
        case .zwiftVirtual24:
            "24 numbered gears · 0.75–5.49"
        case .shimano105Di2:
            "2×12 · 50/34 · 11–34"
        case .simple1x:
            "1×10 · 42 · 11–42"
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
        case .simple1x:
            "10 sequential combinations from the defined 42-tooth drivetrain."
        }
    }

    var drivetrain: Drivetrain {
        switch self {
        case .zwiftVirtual24:
            return .zwiftVirtual24
        case .shimano105Di2:
            let cassette = [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
            let combinations =
                gears(chainring: 34, cogs: [15, 17, 19, 21, 24, 27, 30, 34])
                + gears(chainring: 50, cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24])
            return try! Drivetrain(
                chainrings: [34, 50],
                cassetteCogs: cassette,
                allowedCombinations: combinations
            )
        case .simple1x:
            let cassette = [11, 13, 15, 18, 21, 24, 28, 32, 36, 42]
            return try! Drivetrain(
                chainrings: [42],
                cassetteCogs: cassette,
                allowedCombinations: gears(chainring: 42, cogs: cassette)
            )
        }
    }

    private func gear(chainring: Int, cog: Int) -> VirtualGear {
        try! VirtualGear(chainring: chainring, cog: cog)
    }

    private func gears(chainring: Int, cogs: [Int]) -> [VirtualGear] {
        cogs.map { gear(chainring: chainring, cog: $0) }
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

    func setCircumference(_ value: Int) {
        configuration.neutralCircumferenceMillimeters = value
        if configuration.confirmedCircumferenceMillimeters != value {
            configuration.confirmedCircumferenceMillimeters = nil
        }
    }

    func confirmCircumference() {
        configuration.confirmedCircumferenceMillimeters =
            configuration.neutralCircumferenceMillimeters
    }

    func setDrivetrainPreset(_ preset: DrivetrainPreset) {
        configuration.drivetrainPreset = preset
        configuration.confirmedCircumferenceMillimeters = nil
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
