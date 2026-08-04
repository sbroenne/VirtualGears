import Foundation

public struct DiscoveredTrainer: Equatable, Sendable {
    public let id: UUID
    /// Radio signal strength in dBm. Closer is stronger, and stronger is less
    /// negative: a trainer under the bike reads around -50, one through a wall
    /// around -90.
    public let signalStrength: Int

    public init(id: UUID, signalStrength: Int) {
        self.id = id
        self.signalStrength = signalStrength
    }
}

public enum TrainerChoice: Equatable, Sendable {
    case connect(UUID)
    case ask
}

/// Deciding which trainer a rider means without asking them.
///
/// Bluetooth pays no attention to walls, so a scan can turn up a trainer in a
/// neighbouring flat. Connecting to that one would change a stranger's wheel
/// size, so the rule is deliberately timid: go ahead only when the answer is
/// obvious, and ask whenever it is not. A rider with one trainer in the room
/// never sees a question, which is the whole point.
public enum TrainerPicker {
    /// Weaker than this is somewhere else entirely.
    public static let inTheRoom = -85

    /// About the strength of a trainer under the bike you are sitting on.
    public static let closeBy = -70

    /// How much stronger the nearest has to be before two trainers count as one
    /// obvious answer rather than a choice. Twelve decibels is roughly four
    /// times the distance.
    public static let clearlyCloser = 12

    public static func choice(from trainers: [DiscoveredTrainer]) -> TrainerChoice {
        let sorted = trainers.sorted { $0.signalStrength > $1.signalStrength }
        guard let nearest = sorted.first else { return .ask }

        // The only one anybody can see. Believe it unless it is so faint that
        // it cannot be in the same room.
        guard let next = sorted.dropFirst().first else {
            return nearest.signalStrength >= inTheRoom
                ? .connect(nearest.id) : .ask
        }

        // More than one, so the rider's own trainer has to stand out: close
        // enough to be the one they are sitting on, and clearly nearer than
        // anything else.
        guard nearest.signalStrength >= closeBy,
              nearest.signalStrength - next.signalStrength >= clearlyCloser
        else {
            return .ask
        }
        return .connect(nearest.id)
    }
}
