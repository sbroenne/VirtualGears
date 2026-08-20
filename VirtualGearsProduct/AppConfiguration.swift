import Foundation
import Observation
import VirtualGearsCore

@MainActor
@Observable
final class ConfigurationStore {
    private static let storageKey = "VirtualGears.appConfiguration"
    private let defaults: UserDefaults?

    var configuration: AppConfiguration {
        didSet { save() }
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
    }

    /// An in-memory store for previews and Demo Mode. Changes are intentionally
    /// discarded and can never overwrite the rider's saved equipment or gears.
    init(configuration: AppConfiguration) {
        defaults = nil
        self.configuration = configuration
    }

    func setChainring(_ option: ChainringOption) {
        configuration.chainringID = option.id
    }

    func setCassette(_ option: CassetteOption) {
        configuration.cassetteID = option.id
    }

    /// Choosing a groupset sets both parts at once, which is the whole point of
    /// naming groupsets: a rider picks the bike they own rather than assembling
    /// one part at a time from a list that includes pairings nobody sells.
    func setGroupset(_ groupset: Groupset) {
        if let chainring = groupset.chainrings.first {
            configuration.chainringID = chainring.id
        }
        if let cassette = groupset.cassettes.first {
            configuration.cassetteID = cassette.id
        }
    }

    /// Whether the rider's real bike (chainrings, and cassette unless they
    /// are on a single sprocket) already matches this simulated groupset. Used
    /// to decide whether it is worth offering to bring the physical setup
    /// along too, rather than always showing that offer even when there is
    /// nothing left to do.
    func physicalSetupMatches(_ groupset: Groupset) -> Bool {
        guard let chainring = groupset.chainrings.first,
              configuration.physical.chainringTeeth == chainring.teeth
        else { return false }
        guard !configuration.physical.isSingleSprocket else { return true }
        guard let cassette = groupset.cassettes.first else { return false }
        return configuration.physical.cogTeeth == cassette.cogs
    }

    /// Brings the physical bike's chainrings — and cassette, unless the rider
    /// is on a single sprocket — in line with a groupset chosen from Settings.
    /// Settings otherwise keeps the two apart on purpose, so this is offered
    /// rather than automatic: a rider who deliberately simulates a different
    /// bike than the one on the trainer should never have that quietly
    /// overwritten just for picking a new groupset to simulate.
    func matchPhysicalSetup(to groupset: Groupset) {
        if let chainring = groupset.chainrings.first {
            setPhysicalChainrings(chainring.teeth)
        }
        if !configuration.physical.isSingleSprocket,
           let cassette = groupset.cassettes.first {
            setPhysicalCogs(cassette.cogs)
        }
    }

    /// The setup guide's single "what's your bike" question: one groupset
    /// answers both what is physically bolted on (so the chain-position
    /// advice is right) and what gearing gets simulated (so the ladder
    /// matches a bike the rider actually recognises), instead of asking the
    /// same thing twice. Either half can still be changed independently
    /// afterwards in Settings, for the rider who wants to simulate different
    /// gearing than what is on the bike.
    ///
    /// - Parameter singleSprocketTeeth: Set when the trainer's actual back
    ///   cog is a single sprocket — a Zwift Cog (14 teeth) or any other
    ///   single-speed cog — rather than the groupset's own cassette; a
    ///   common indoor-only setup. The simulated gearing still matches the
    ///   groupset chosen either way; only the physical cog (and so the
    ///   parked-gear advice) changes.
    func adoptGroupsetForBikeAndGears(
        _ groupset: Groupset,
        singleSprocketTeeth: Int? = nil
    ) {
        configuration.usesVirtualGears = false
        setGroupset(groupset)
        if let chainring = groupset.chainrings.first {
            setPhysicalChainrings(chainring.teeth)
        }
        if let singleSprocketTeeth {
            setPhysicalCogs([singleSprocketTeeth])
        } else if let cassette = groupset.cassettes.first {
            setPhysicalCogs(cassette.cogs)
        }
    }

    func setLadder(_ ladder: GearLadder) {
        configuration.gearLadderID = ladder.id
    }

    func useStandardVirtualGears() {
        configuration.usesVirtualGears = true
        setLadder(GearLadderCatalog.standardRange)
        clearParkedGear()
    }

    func configureFirstRunBike(
        chainringTeeth: [Int],
        cogTeeth: [Int]
    ) {
        configuration.physical = PhysicalSetup(
            chainringTeeth: chainringTeeth,
            cogTeeth: cogTeeth
        )
        useStandardVirtualGears()
    }

    /// Uses the parts the rider just chose for both the real bike and the
    /// simulated gearing. A single sprocket is not a cassette to simulate, so
    /// that setup keeps the physical answer and uses the standard virtual ladder.
    func copyPhysicalBikeToSimulatedGears() {
        guard !configuration.physical.isSingleSprocket,
              let chainring = DrivetrainCatalog.chainrings.first(where: {
                  $0.teeth == configuration.physical.chainringTeeth
              }),
              let cassette = DrivetrainCatalog.cassettes.first(where: {
                  $0.cogs == configuration.physical.cogTeeth
              })
        else {
            useStandardVirtualGears()
            return
        }
        configuration.usesVirtualGears = false
        setChainring(chainring)
        setCassette(cassette)
        clearParkedGear()
    }

    /// Switches to a ladder the rider defines themselves. The parameters are
    /// kept even after switching back to the built-in ladder, so returning to
    /// "Custom" does not forget what was last set.
    func setCustomLadder(_ params: CustomGearLadder) {
        configuration.gearLadderID = GearLadderCatalog.customLadderID
        configuration.customLadder = params
    }

    /// What is physically bolted to the bike. Changing it invalidates whichever
    /// gear was confirmed before, because that gear may no longer exist.
    func setPhysicalChainrings(_ teeth: [Int]) {
        configuration.physical.chainringTeeth = teeth
        clearParkedGear()
    }

    func setPhysicalCogs(_ teeth: [Int]) {
        configuration.physical.cogTeeth = teeth
        clearParkedGear()
    }

    func park(in gear: ParkedGear) {
        configuration.park(in: gear)
    }

    func parkInSuggestion() {
        configuration.parkInSuggestion()
    }

    private func clearParkedGear() {
        configuration.physical.parkedChainringTeeth = nil
        configuration.physical.parkedCogTeeth = nil
        configuration.parkInSuggestion()
    }

    func setNormalWheelCircumference(millimeters: Int) {
        configuration.setNormalWheelCircumference(millimeters: millimeters)
    }

    func useDefaultWheelCircumference() {
        configuration.useDefaultWheelCircumference()
    }

    @discardableResult
    func completeSetupWizard() -> Bool {
        configuration.completeSetupWizard()
    }

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
