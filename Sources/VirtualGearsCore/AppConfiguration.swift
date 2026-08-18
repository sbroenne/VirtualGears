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
    /// A made-up ladder of evenly spaced ratios rather than a copy of a real
    /// groupset. It is the starting point because it needs no knowledge of the
    /// bike.
    public var usesVirtualGears = true
    public var gearLadderID = GearLadderCatalog.defaultLadderID
    /// The rider's own gear count and range, used only while `gearLadderID`
    /// equals `GearLadderCatalog.customLadderID`. Kept even while a built-in
    /// ladder is selected, so switching to "Custom" and back never forgets
    /// what the rider last set it to.
    public var customLadder = CustomGearLadder.default
    /// What is physically on the trainer, including the one gear the bike is
    /// parked in. Entirely separate from the gearing being simulated: a rider
    /// on a single-sprocket Zwift Cog can simulate a twelve-speed groupset, and
    /// most will.
    public var physical = PhysicalSetup.default

    /// Whether the rider has been through the setup guide (groupset, chain
    /// position, wheel size) at least once. Not the same as `canFinishSetup`:
    /// a rider can dismiss the guide part-way through and finish setting
    /// things up by hand in Settings, and this should not re-open on every
    /// launch once they have seen it.
    public var setupWizardCompleted = false

    /// Reading is deliberately forgiving: a key that is not there falls back to
    /// the default rather than throwing the whole saved setup away. The app has
    /// no riders yet so there is nothing to migrate today, but a setup a rider
    /// has already made is the one thing worth never losing, so every new field
    /// added from here on stays optional on the way in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys, _ fallback: String) throws -> String {
            try container.decodeIfPresent(String.self, forKey: key) ?? fallback
        }
        kickrName = try string(.kickrName, "")
        kickrUUID = try string(.kickrUUID, "")
        clickName = try string(.clickName, "")
        clickUUID = try string(.clickUUID, "")
        headwindName = try container.decodeIfPresent(
            String.self, forKey: .headwindName
        )
        headwindUUID = try container.decodeIfPresent(
            String.self, forKey: .headwindUUID
        )
        chainringID = try string(
            .chainringID, DrivetrainCatalog.defaultChainringID
        )
        cassetteID = try string(.cassetteID, DrivetrainCatalog.defaultCassetteID)
        usesVirtualGears = try container.decodeIfPresent(
            Bool.self, forKey: .usesVirtualGears
        ) ?? true
        gearLadderID = try string(
            .gearLadderID, GearLadderCatalog.defaultLadderID
        )
        customLadder = try container.decodeIfPresent(
            CustomGearLadder.self, forKey: .customLadder
        ) ?? .default
        physical = try container.decodeIfPresent(
            PhysicalSetup.self, forKey: .physical
        ) ?? .default
        setupWizardCompleted = try container.decodeIfPresent(
            Bool.self, forKey: .setupWizardCompleted
        ) ?? false
        normalWheelCircumferenceMillimeters = try container.decodeIfPresent(
            Int.self, forKey: .normalWheelCircumferenceMillimeters
        )
    }
    /// Nil in configurations saved before this setting existed. The computed
    /// value below turns that into the long-standing 2070 mm default.
    public private(set) var normalWheelCircumferenceMillimeters: Int?

    /// There is nothing to complete. A trainer worth remembering and gears the
    /// trainer can copy are all a ride needs, so being set up is simply being
    /// in that state rather than a flag a rider has to go and set.
    public var setupComplete: Bool { canFinishSetup }

    public var neutralCircumferenceMillimeters: Int {
        guard let normalWheelCircumferenceMillimeters,
              TrainerSafety.supportedRidingAppCircumferenceMillimeters.contains(
                Double(normalWheelCircumferenceMillimeters)
              )
        else {
            return Int(TrainerSafety.referenceCircumferenceMillimeters)
        }
        return normalWheelCircumferenceMillimeters
    }

    /// Saves the wheel size to use when the riding app has not supplied one.
    /// Invalid values are refused rather than silently changed.
    @discardableResult
    public mutating func setNormalWheelCircumference(
        millimeters: Int
    ) -> Bool {
        guard TrainerSafety.supportedRidingAppCircumferenceMillimeters.contains(
            Double(millimeters)
        ) else { return false }
        normalWheelCircumferenceMillimeters = millimeters
        return true
    }

    public var chainring: ChainringOption {
        DrivetrainCatalog.chainring(id: chainringID)
            ?? DrivetrainCatalog.chainring(id: DrivetrainCatalog.defaultChainringID)!
    }

    public var cassette: CassetteOption {
        DrivetrainCatalog.cassette(id: cassetteID)
            ?? DrivetrainCatalog.cassette(id: DrivetrainCatalog.defaultCassetteID)!
    }

    /// True while the rider has chosen to define their own gear count and
    /// range rather than the one built-in ladder.
    public var usesCustomLadder: Bool {
        gearLadderID == GearLadderCatalog.customLadderID
    }

    public var gearLadder: GearLadder {
        if usesCustomLadder {
            return GearLadderCatalog.custom(customLadder)
        }
        return GearLadderCatalog.ladder(id: gearLadderID)
            ?? GearLadderCatalog.defaultLadder
    }

    /// The named groupset the chosen parts belong to, when they belong to one.
    public var groupset: Groupset? {
        guard !usesVirtualGears else { return nil }
        return GroupsetCatalog.groupset(
            chainringID: chainringID,
            cassetteID: cassetteID
        )
    }

    /// The gear the rider confirmed their bike is parked in. Nil until they
    /// have confirmed one, which is why setup is not finished without it.
    public var parkedGear: ParkedGear? { physical.parkedGear }

    /// The gear to recommend: the quietest one that still lets every simulated
    /// gear reach the trainer.
    public var suggestedParkedGear: ParkedGear? {
        guard let drivetrain else { return nil }
        return ParkedGearAdvice.suggestion(
            for: physical,
            simulating: drivetrain
        )
    }

    /// Every parked ratio that keeps the whole ladder within the trainer's
    /// reach, at every wheel size a riding app may ask for.
    public var workableParkedRatios: ClosedRange<Double>? {
        guard let drivetrain else { return nil }
        return ParkedGearAdvice.workableRatios(for: drivetrain)
    }

    /// True when the confirmed parked gear leaves part of the ladder out of
    /// reach, so the app can say so rather than fail mid-ride.
    public var parkedGearPutsGearsOutOfReach: Bool {
        guard let drivetrain, let parkedGear else { return false }
        return !ParkedGearAdvice.isWorkable(parkedGear, simulating: drivetrain)
    }

    public mutating func park(in gear: ParkedGear) {
        physical.park(in: gear)
    }

    /// Pre-selects the recommendation so confirming it is a single tap.
    public mutating func parkInSuggestion() {
        if let suggestedParkedGear { physical.park(in: suggestedParkedGear) }
    }

    /// Marks the setup guide as seen, whether the rider finished every step
    /// or dismissed it early. Either way it should not reopen on its own.
    public mutating func completeSetupWizard() {
        setupWizardCompleted = true
    }

    /// Nil when the chosen parts cover a wider spread than the trainer can copy.
    public var drivetrain: Drivetrain? {
        if usesVirtualGears {
            return try? gearLadder.drivetrain()
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
        return Self.isSafe(drivetrain, parkedGear: parkedGear)
    }

    /// Confirms every gear of a drivetrain can be built and encoded at both
    /// ends of the wheel sizes a riding app may ask for. Nothing reaches the
    /// KICKR without this.
    public static func isSafe(
        _ drivetrain: Drivetrain,
        parkedGear: ParkedGear? = nil
    ) -> Bool {
        // Building the gears is the check. The engine scales every gear and
        // encodes every command, so anything it accepts can be staged.
        //
        // Both ends of the supported window are tried, not just the reference
        // wheel size, because a drivetrain that fits around 2070 mm can still
        // put its hardest gear out of reach once a riding app asks for 2400 mm.
        // Checking only the middle is how a drivetrain used to pass setup and
        // then fail mid-ride.
        // The parked gear is checked separately because encoding is not the
        // only limit. Parked in the big ring on the smallest cog every gear
        // still fits in the command, but the easiest one asks the trainer for a
        // 238 mm wheel, and a riding app would draw that as a rider who has
        // stopped. That is what the scale range exists to prevent.
        if let parkedGear,
           !ParkedGearAdvice.isWorkable(parkedGear, simulating: drivetrain) {
            return false
        }
        let window = TrainerSafety.supportedRidingAppCircumferenceMillimeters
        return [window.lowerBound, window.upperBound].allSatisfy { wheelSize in
            (try? ConfirmedGearEngine(
                drivetrain: drivetrain,
                wheelSizeMillimeters: wheelSize,
                parkedGear: parkedGear
            )) != nil
        }
    }

    /// Setup is not finished until the rider has said which gear the bike is
    /// parked in. There is nothing to fall back to and nothing to preserve —
    /// the app has never shipped — and guessing it quietly moves every gear the
    /// rider feels, so it is asked rather than assumed.
    public var canFinishSetup: Bool {
        hasValidKickr && parkedGear != nil && hasSafeCircumference
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

    /// What the rider chose, named the way the bike is named: the groupset if
    /// the parts belong to one, otherwise the parts themselves.
    var drivetrainName: String {
        guard !usesVirtualGears else { return gearLadder.name }
        if let groupset {
            return "\(groupset.qualifiedName) · \(chainring.name) \(cassette.name)"
        }
        return "\(chainring.name) · \(cassette.name)"
    }

    /// The one line that matters: how many gears they will actually have.
    var gearSummary: String {
        guard drivetrain != nil else {
            return "Too wide a range for the trainer"
        }
        if usesVirtualGears {
            return "\(gearCount) gears · \(gearLadder.note)"
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

    /// What to tell the rider to do with the chain before they start. The
    /// bike never shifts, so this is a one-off: park it, confirm it, ride.
    var parkedGearAdviceText: String {
        guard let suggestedParkedGear else {
            return "Leave the bike in a quiet, straight chain line, then tell "
                + "Virtual Gears which gear that is."
        }
        let cog = physical.isSingleSprocket
            ? "the \(suggestedParkedGear.cogTeeth) tooth sprocket"
            : "the \(suggestedParkedGear.cogTeeth) tooth cog"
        return "Park the chain on the \(suggestedParkedGear.chainringTeeth) "
            + "tooth ring and \(cog). Quiet, straight chain line — and the "
            + "bike stays there for the whole ride."
    }

    /// Says plainly what a confirmed gear costs, rather than only computing it.
    var parkedGearWarning: String? {
        guard parkedGear != nil, parkedGearPutsGearsOutOfReach,
              let range = workableParkedRatios
        else {
            return nil
        }
        return String(
            format: "Parked in that gear, some gears cannot reach the trainer. "
                + "It needs to be between %.2f and %.2f — around %d/%d.",
            range.lowerBound,
            range.upperBound,
            suggestedParkedGear?.chainringTeeth ?? 34,
            suggestedParkedGear?.cogTeeth ?? 15
        )
    }
}
