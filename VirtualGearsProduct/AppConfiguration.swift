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

    func setNormalWheelCircumference(millimeters: Int) {
        configuration.setNormalWheelCircumference(millimeters: millimeters)
    }

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
