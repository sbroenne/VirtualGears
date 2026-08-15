import Foundation

/// How one gear is drawn on the position rail under the gear number.
///
/// The rail used to be a row of identical dots with one of them coloured. That
/// can only be read by counting, which is not something a rider does at 90rpm,
/// so the rail said little the number above it had not already said. Filling in
/// the gears behind the rider turns it into a picture of where they are in the
/// range, which is the one thing the number cannot show.
public enum GearRailMarker: String, CaseIterable, Equatable, Sendable {
    /// The gear the trainer has confirmed.
    case selected
    /// An easier gear the rider has already come up through.
    case behind
    /// A harder gear still available.
    case ahead
    /// The gear the rider has asked for and the trainer has not confirmed yet.
    case requested

    /// How tall this marker is drawn, as a fraction of the tallest one.
    ///
    /// Every kind has its own height so the rail still reads when colour does
    /// not: in greyscale, to a rider who cannot tell the colours apart, or
    /// through a phone screen with sweat on it.
    public var relativeHeight: Double {
        switch self {
        case .selected: 1
        case .requested: 0.75
        case .behind: 0.5
        case .ahead: 0.3
        }
    }
}

public enum GearRail {
    /// Describes each position on the rail for a gear range of `count` gears.
    ///
    /// A requested gear is only ever drawn while it differs from the confirmed
    /// one, so the rail never shows a gear the trainer has not agreed to as if
    /// it were the gear being ridden.
    public static func markers(
        count: Int,
        selected: Int?,
        requested: Int?
    ) -> [GearRailMarker] {
        guard count > 0 else { return [] }
        let range = 0..<count
        let confirmed = selected.flatMap { range.contains($0) ? $0 : nil }
        let pending = requested.flatMap { range.contains($0) ? $0 : nil }
        return range.map { index in
            if let pending, pending != confirmed, index == pending { return .requested }
            guard let confirmed else { return .ahead }
            if index == confirmed { return .selected }
            return index < confirmed ? .behind : .ahead
        }
    }
}

/// Sizes for the gear read-out.
public enum GearReadoutMetrics {
    /// The size of the line under the gear number.
    ///
    /// It carries "of 24" and the chainring and cog, which are worth having but
    /// are not what the rider is looking for. It used to be drawn at a fixed
    /// large title, which made it the second loudest thing on the screen and
    /// took room from the gear itself. It is now a caption to the number: tied
    /// to it, but never competing with it, and never smaller than a size that
    /// can be read from a bike.
    public static func secondaryPointSize(forPrimary primary: Double) -> Double {
        min(24, max(15, primary * 0.09))
    }
}
