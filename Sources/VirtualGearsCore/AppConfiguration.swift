import Foundation


public struct AppConfiguration: Codable, Equatable {
    public init() {}

    public var kickrName = ""
    public var kickrUUID = ""
    public var clickName = ""
    public var clickUUID = ""
    public var headwindName: String?
    public var headwindUUID: String?
    public var chainringID = DrivetrainCatalog.defaultChainringID
    public var cassetteID = DrivetrainCatalog.defaultCassetteID
    /// The gears Zwift and Wahoo hand out when the bike has none of its own.
    /// It is the starting point because it needs no knowledge of the bike.
    public var usesVirtualGears = true

    /// There is nothing to complete. A trainer worth remembering and gears the
    /// trainer can copy are all a ride needs, so being set up is simply being
    /// in that state rather than a flag a rider has to go and set.
    public var setupComplete: Bool { canFinishSetup }

    public var neutralCircumferenceMillimeters: Int {
        Int(TrainerSafety.referenceCircumferenceMillimeters)
    }

    public var chainring: ChainringOption {
        DrivetrainCatalog.chainring(id: chainringID)
            ?? DrivetrainCatalog.chainring(id: DrivetrainCatalog.defaultChainringID)!
    }

    public var cassette: CassetteOption {
        DrivetrainCatalog.cassette(id: cassetteID)
            ?? DrivetrainCatalog.cassette(id: DrivetrainCatalog.defaultCassetteID)!
    }

    /// Nil when the chosen parts cover a wider spread than the trainer can copy.
    public var drivetrain: Drivetrain? {
        if usesVirtualGears {
            return try? Drivetrain.virtualLadder()
        }
        return try? Drivetrain.build(
            chainrings: chainring.teeth,
            cassetteCogs: cassette.cogs
        )
    }

    public var hasValidKickr: Bool {
        !kickrName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: kickrUUID) != nil
    }

    /// A Zwift Click is an extra, never a requirement. The two on-screen shift
    /// buttons are always live, so a missing or sleeping Click must never stop
    /// a ride from starting.
    public var usesClick: Bool {
        !clickName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: clickUUID) != nil
    }

    /// A Headwind is optional and never gates a ride.
    public var usesHeadwind: Bool {
        !(headwindName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: headwindUUID ?? "") != nil
    }

    public var hasSafeCircumference: Bool {
        guard let drivetrain else { return false }
        return Self.isSafe(drivetrain)
    }

    /// Confirms every gear of a drivetrain can be built and encoded at both
    /// ends of the wheel sizes a riding app may ask for. Nothing reaches the
    /// KICKR without this.
    public static func isSafe(_ drivetrain: Drivetrain) -> Bool {
        // Building the gears is the check. The engine scales every gear and
        // encodes every command, so anything it accepts can be staged.
        //
        // Both ends of the supported window are tried, not just the reference
        // wheel size, because a drivetrain that fits around 2070 mm can still
        // put its hardest gear out of reach once a riding app asks for 2400 mm.
        // Checking only the middle is how a drivetrain used to pass setup and
        // then fail mid-ride.
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        return [window.lowerBound, window.upperBound].allSatisfy { wheelSize in
            (try? ConfirmedGearEngine(
                drivetrain: drivetrain,
                baselineCircumferenceMillimeters: wheelSize
            )) != nil
        }
    }

    public var canFinishSetup: Bool {
        hasValidKickr && hasSafeCircumference
    }

    /// Connecting to a trainer is not the same as choosing one. Every check
    /// that decides whether a ride can start asks whether a trainer was
    /// *chosen*, so a trainer found automatically has to be recorded exactly
    /// as one picked by hand. Both paths go through here so neither can
    /// quietly forget, which once left new riders unable to start at all.
    public mutating func rememberKickr(named name: String, id: UUID) {
        kickrName = name
        kickrUUID = id.uuidString
    }

    public mutating func rememberClick(named name: String, id: UUID) {
        clickName = name
        clickUUID = id.uuidString
    }

    /// Both halves have to go. Leaving either behind would keep the Click
    /// half-remembered, which reads as still in use.
    public mutating func forgetClick() {
        clickName = ""
        clickUUID = ""
    }

    public mutating func rememberHeadwind(named name: String, id: UUID) {
        headwindName = name
        headwindUUID = id.uuidString
    }

    public mutating func forgetHeadwind() {
        headwindName = nil
        headwindUUID = nil
    }
}

/// The plain-English wording the setup and ride screens share, so a drivetrain
/// is described the same way everywhere.
public extension AppConfiguration {
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
