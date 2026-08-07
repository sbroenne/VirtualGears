import Foundation

public struct DiscoveredTrainer: Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public enum TrainerChoice: Equatable, Sendable {
    case connect(UUID)
    case ask
}

/// Deciding which trainer a rider means without asking them.
///
/// Bluetooth signal strength does not measure distance reliably. One result is
/// unambiguous and can connect automatically; more than one must be chosen by
/// name rather than guessed from a fluctuating radio reading.
public enum TrainerPicker {
    public static func choice(from trainers: [DiscoveredTrainer]) -> TrainerChoice {
        trainers.count == 1
            ? .connect(trainers[0].id)
            : .ask
    }
}
