import Foundation

/// A chainring choice, written the way it is stamped on the part: one number for
/// a single ring, or the pair a front derailleur moves between.
public struct ChainringOption: Identifiable, Equatable, Sendable {
    public let id: String
    /// Largest first, matching how a groupset is named ("50/34", never "34/50").
    public let teeth: [Int]
    public let note: String

    public init(id: String, teeth: [Int], note: String) {
        self.id = id
        self.teeth = teeth
        self.note = note
    }

    public var name: String {
        teeth.map(String.init).joined(separator: "/")
    }

    public var isSingle: Bool { teeth.count == 1 }
}

/// A cassette, listed cog by cog because the gaps between cogs are what a rider
/// actually feels. Smallest cog first, which is the hardest gear.
public struct CassetteOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let cogs: [Int]
    public let note: String

    public init(id: String, cogs: [Int], note: String) {
        self.id = id
        self.cogs = cogs
        self.note = note
    }

    public var speeds: Int { cogs.count }

    public var name: String {
        guard let smallest = cogs.first, let largest = cogs.last else { return "" }
        return "\(smallest)-\(largest)"
    }

    /// The name plus what tells it apart from the others that share it. Several
    /// cassettes are called "11-28"; on a screen that lists them under their own
    /// cog-count headings that is clear, but anywhere else — the selected value,
    /// VoiceOver — it names three different parts at once.
    public var qualifiedName: String {
        "\(name) · \(speeds) cogs"
    }
}

/// The parts the shipped groupsets are made of.
///
/// Every entry here appears in at least one entry of ``GroupsetCatalog``, so
/// every entry is a thing you can buy and can be checked against a spec sheet.
/// Picking a groupset is the fast path; these lists are the escape hatch for
/// anyone whose bike mixes parts, so nobody with an unlisted combination is
/// stranded.
public enum DrivetrainCatalog {
    public static let chainrings: [ChainringOption] = [
        // Single rings.
        .init(id: "1x38", teeth: [38], note: "Gravel"),
        .init(id: "1x40", teeth: [40], note: "Gravel, most common"),
        .init(id: "1x42", teeth: [42], note: "Fast gravel"),
        .init(id: "1x44", teeth: [44], note: "Fast gravel"),
        .init(id: "1x46", teeth: [46], note: "Road"),

        // Two rings, Shimano.
        .init(id: "2x50-34", teeth: [50, 34], note: "Compact road, most common"),
        .init(id: "2x52-36", teeth: [52, 36], note: "Mid-compact road"),
        .init(id: "2x53-39", teeth: [53, 39], note: "Standard road, racing"),
        .init(id: "2x54-40", teeth: [54, 40], note: "Dura-Ace, racing"),
        .init(id: "2x48-31", teeth: [48, 31], note: "Shimano GRX gravel"),
        .init(id: "2x46-30", teeth: [46, 30], note: "Gravel, easy climbing"),

        // Two rings, SRAM.
        .init(id: "2x50-37", teeth: [50, 37], note: "SRAM road, racing"),
        .init(id: "2x48-35", teeth: [48, 35], note: "SRAM road, fast"),
        .init(id: "2x46-33", teeth: [46, 33], note: "SRAM road"),
        .init(id: "2x43-30", teeth: [43, 30], note: "SRAM Wide, gravel"),

        // Two rings, Campagnolo.
        .init(id: "2x54-39", teeth: [54, 39], note: "Campagnolo racing"),
        .init(id: "2x48-32", teeth: [48, 32], note: "Campagnolo road"),
        .init(id: "2x45-29", teeth: [45, 29], note: "Campagnolo, easy climbing"),
    ]

    public static let cassettes: [CassetteOption] = [
        // 11 speed, Shimano.
        .init(id: "11s-11-28", cogs: [11, 12, 13, 14, 15, 17, 19, 21, 23, 25, 28], note: "Road, racing"),
        .init(id: "11s-11-30", cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30], note: "Road"),
        .init(id: "11s-11-32", cogs: [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 32], note: "Road, most common"),
        .init(id: "11s-11-34", cogs: [11, 13, 15, 17, 19, 21, 23, 25, 27, 30, 34], note: "Road, easy climbing"),
        .init(id: "11s-12-28", cogs: [12, 13, 14, 15, 16, 17, 19, 21, 23, 25, 28], note: "Road, close gaps"),

        // 12 speed, Shimano.
        .init(id: "12s-11-28", cogs: [11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 25, 28], note: "Road, racing"),
        .init(id: "12s-11-30", cogs: [11, 12, 13, 14, 15, 16, 17, 19, 21, 24, 27, 30], note: "Road, close gaps"),
        .init(id: "12s-11-34", cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34], note: "Road"),
        .init(id: "12s-11-36", cogs: [11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 32, 36], note: "Gravel"),

        // 12 speed, SRAM.
        .init(id: "12s-10-28", cogs: [10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 24, 28], note: "SRAM road, racing"),
        .init(id: "12s-10-30", cogs: [10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 25, 30], note: "SRAM road"),
        .init(id: "12s-10-33", cogs: [10, 11, 12, 13, 14, 15, 17, 19, 21, 24, 28, 33], note: "SRAM road"),
        .init(id: "12s-10-36", cogs: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 32, 36], note: "SRAM road, easy climbing"),
        .init(id: "12s-10-44", cogs: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 35, 44], note: "SRAM XPLR gravel"),
        .init(id: "12s-10-52", cogs: [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42, 52], note: "SRAM Eagle, widest"),

        // 12 speed, Campagnolo.
        .init(id: "12s-11-29", cogs: [11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 26, 29], note: "Campagnolo road"),
        .init(id: "12s-11-32", cogs: [11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 27, 32], note: "Campagnolo road"),

        // 13 speed, Campagnolo.
        .init(id: "13s-10-29", cogs: [10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 26, 29], note: "Campagnolo racing"),
        .init(id: "13s-11-32", cogs: [11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 25, 28, 32], note: "Campagnolo, easy climbing"),
        .init(id: "13s-9-36", cogs: [9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 23, 36], note: "Campagnolo Ekar gravel"),
        .init(id: "13s-9-42", cogs: [9, 10, 11, 12, 13, 14, 16, 18, 20, 23, 27, 34, 42], note: "Campagnolo Ekar, wide"),
        .init(id: "13s-10-44", cogs: [10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 32, 38, 44], note: "Campagnolo Ekar, widest"),
    ]

    /// A 105 R7100 with 50/34 and an 11-34: the most common setup on new bikes.
    public static let defaultChainringID = "2x50-34"
    public static let defaultCassetteID = "12s-11-34"

    public static func chainring(id: String) -> ChainringOption? {
        chainrings.first { $0.id == id }
    }

    public static func cassette(id: String) -> CassetteOption? {
        cassettes.first { $0.id == id }
    }

    public static func chainring(teeth: [Int]) -> ChainringOption? {
        chainrings.first { $0.teeth == teeth }
    }

    public static func cassette(cogs: [Int]) -> CassetteOption? {
        cassettes.first { $0.cogs == cogs }
    }
}
