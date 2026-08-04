import Foundation
import Observation
import VirtualShiftCore

struct AppConfiguration: Codable, Equatable {
    var kickrName = ""
    var kickrUUID = ""
    var clickName = ""
    var clickUUID = ""
    var chainringID = DrivetrainCatalog.defaultChainringID
    var cassetteID = DrivetrainCatalog.defaultCassetteID
    /// The gears Zwift and Wahoo hand out when the bike has none of its own.
    /// It is the starting point because it needs no knowledge of the bike.
    var usesVirtualGears = true
    var setupComplete = false

    var neutralCircumferenceMillimeters: Int {
        Int(TrainerSafety.referenceCircumferenceMillimeters)
    }

    var chainring: ChainringOption {
        DrivetrainCatalog.chainring(id: chainringID)
            ?? DrivetrainCatalog.chainring(id: DrivetrainCatalog.defaultChainringID)!
    }

    var cassette: CassetteOption {
        DrivetrainCatalog.cassette(id: cassetteID)
            ?? DrivetrainCatalog.cassette(id: DrivetrainCatalog.defaultCassetteID)!
    }

    /// Nil when the chosen parts cover a wider spread than the trainer can copy.
    var drivetrain: Drivetrain? {
        if usesVirtualGears {
            return try? Drivetrain.virtualLadder()
        }
        return try? Drivetrain.build(
            chainrings: chainring.teeth,
            cassetteCogs: cassette.cogs
        )
    }

    var hasValidKickr: Bool {
        !kickrName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: kickrUUID) != nil
    }

    /// A Zwift Click is an extra, never a requirement. The two on-screen shift
    /// buttons are always live, so a missing or sleeping Click must never stop
    /// a ride from starting.
    var usesClick: Bool {
        !clickName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: clickUUID) != nil
    }

    var hasSafeCircumference: Bool {
        guard let drivetrain else { return false }
        return Self.isSafe(drivetrain)
    }

    /// Confirms every gear of a drivetrain encodes inside the range that was
    /// actually staged on the trainer. Nothing reaches the KICKR without this.
    static func isSafe(_ drivetrain: Drivetrain) -> Bool {
        guard (try? ConfirmedGearEngine(
            drivetrain: drivetrain,
            baselineCircumferenceMillimeters:
                TrainerSafety.referenceCircumferenceMillimeters
        )) != nil else {
            return false
        }

        return drivetrain.gears.allSatisfy { gear in
            guard let circumference = try? WheelCircumferenceScaler
                .effectiveCircumference(
                    neutralCircumference:
                        TrainerSafety.referenceCircumferenceMillimeters,
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
            let proven = TrainerSafety.provenCircumferenceMillimeters
            return (Int(proven.lowerBound * 10)...Int(proven.upperBound * 10))
                .contains(encoded)
        }
    }

    var canFinishSetup: Bool {
        hasValidKickr && hasSafeCircumference
    }
}

/// The plain-English wording the setup and ride screens share, so a drivetrain
/// is described the same way everywhere.
extension AppConfiguration {
    var gearCount: Int { drivetrain?.gears.count ?? 0 }

    /// What the rider chose, in the words printed on the parts.
    var drivetrainName: String {
        guard !usesVirtualGears else { return "Virtual gears" }
        return "\(chainring.name) · \(cassette.name)"
    }

    /// The one line that matters: how many gears they will actually have.
    var gearSummary: String {
        guard drivetrain != nil else {
            return "Too wide a range for the trainer"
        }
        return "\(gearCount) gears · \(rangeDescription)"
    }

    private var rangeDescription: String {
        guard let drivetrain,
              let easiest = drivetrain.gears.first,
              let hardest = drivetrain.gears.last
        else {
            return ""
        }
        switch hardest.ratio / easiest.ratio {
        case ..<2.6:
            return "close together, for flat roads"
        case ..<3.6:
            return "a normal road spread"
        case ..<5:
            return "wide, with easy climbing gears"
        default:
            return "very wide, for steep climbs"
        }
    }

    /// Explains what the numbers on the ride screen will mean.
    var setupDescription: String {
        guard let drivetrain else {
            return "The easiest and hardest gear are too far apart for the "
                + "trainer to copy. Choose a smaller cassette or a single "
                + "chainring."
        }
        return "Gear 1 is the easiest for climbing and gear \(gearCount) is the "
            + "hardest for speed. Every ride starts in gear "
            + "\(drivetrain.referenceIndex + 1)."
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

    func setChainring(_ option: ChainringOption) {
        configuration.chainringID = option.id
    }

    func setCassette(_ option: CassetteOption) {
        configuration.cassetteID = option.id
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
