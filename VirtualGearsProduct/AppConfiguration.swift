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

    func setLadder(_ ladder: GearLadder) {
        configuration.gearLadderID = ladder.id
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

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
