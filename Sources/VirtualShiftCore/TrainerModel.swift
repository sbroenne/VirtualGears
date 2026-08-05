import Foundation

/// How well a trainer suits the way VirtualShift makes gears.
///
/// VirtualShift shifts by changing the wheel size the trainer is configured
/// for. Not every trainer with KICKR on the side works that way, and the two
/// that do not are worth naming before a rider spends an evening wondering why
/// nothing happens.
public enum TrainerCompatibility: Equatable, Sendable {
    /// Named like the trainer the app was built and measured against.
    case supported
    /// Known to shift some other way, so VirtualShift cannot drive it.
    case unsupported(model: String, reason: String)
    /// A KICKR, but not one anybody has tried this with. Allowed, because the
    /// trainer confirms every gear change and so says for itself whether it
    /// worked.
    case untested

    public var isUsable: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

public enum TrainerModel {
    /// Works from the Bluetooth name because it is all a trainer offers before
    /// connecting, and the two unsuitable models announce themselves plainly:
    /// they are "KICKR SNAP …" and "KICKR BIKE …", where the trainers that do
    /// work are "Wahoo KICKR …".
    public static func compatibility(
        forAdvertisedName name: String
    ) -> TrainerCompatibility {
        let upper = name.uppercased()

        // Checked before anything else, so a name like "Wahoo KICKR SNAP"
        // is still recognised as a SNAP.
        if upper.contains("KICKR BIKE") {
            return .unsupported(
                model: "KICKR Bike",
                reason: """
                    The KICKR Bike already has its own gear levers and shifts \
                    itself, so it has no use for VirtualShift.
                    """
            )
        }
        if upper.contains("KICKR SNAP") {
            return .unsupported(
                model: "KICKR Snap",
                reason: """
                    The KICKR Snap changes gear a different way that \
                    VirtualShift cannot drive.
                    """
            )
        }
        if upper.hasPrefix("WAHOO KICKR") {
            return .supported
        }
        return .untested
    }

    /// The app should offer only trainers a rider might plausibly want, which
    /// includes the two unsuitable ones: a rider whose trainer is missing from
    /// the list assumes the app is broken, where a rider who is told why can
    /// stop looking.
    public static func isKickr(advertisedName name: String) -> Bool {
        name.uppercased().contains("KICKR")
    }
}
