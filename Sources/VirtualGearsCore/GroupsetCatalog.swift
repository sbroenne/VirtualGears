import Foundation

public enum GroupsetBrand: String, CaseIterable, Identifiable, Sendable {
    case shimano
    case sram
    case campagnolo

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .shimano: return "Shimano"
        case .sram: return "SRAM"
        case .campagnolo: return "Campagnolo"
        }
    }
}

/// A groupset you can actually buy, so the simulated gears match gearing the
/// rider already knows.
///
/// Nothing physical shifts — the bike is parked in one gear all ride. Picking a
/// groupset does not change what the bike does; it changes what the *ladder*
/// looks like, so the gear count, the range and the size of each step feel
/// familiar instead of arbitrary.
public struct Groupset: Identifiable, Equatable, Sendable {
    public let id: String
    public let brand: GroupsetBrand
    public let name: String
    public let speeds: Int
    public let chainringIDs: [String]
    public let cassetteIDs: [String]
    public let note: String

    public init(
        id: String,
        brand: GroupsetBrand,
        name: String,
        speeds: Int,
        chainringIDs: [String],
        cassetteIDs: [String],
        note: String = ""
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.speeds = speeds
        self.chainringIDs = chainringIDs
        self.cassetteIDs = cassetteIDs
        self.note = note
    }

    public var chainrings: [ChainringOption] {
        chainringIDs.compactMap(DrivetrainCatalog.chainring(id:))
    }

    public var cassettes: [CassetteOption] {
        cassetteIDs.compactMap(DrivetrainCatalog.cassette(id:))
    }

    /// "Shimano 105 R7100" — how a rider would name it.
    public var qualifiedName: String { "\(brand.name) \(name)" }
}

/// The groupsets Virtual Gears simulates.
///
/// Every entry is a real product with real chainring and cassette options, so
/// every entry can be checked by hand and tested. The catalogue it replaced was
/// twenty-two chainrings crossed with twenty-eight cassettes — six hundred and
/// sixteen combinations, most of which exist on no bike anywhere, and which
/// could not be validated because there was nothing to validate them against.
///
/// Weighted by what people own: Shimano is roughly seventy per cent of the
/// market, SRAM twenty-six, Campagnolo three to four.
public enum GroupsetCatalog {
    public static let groupsets: [Groupset] = [
        // MARK: Shimano
        .init(
            id: "shimano-dura-ace-r9200",
            brand: .shimano,
            name: "Dura-Ace R9200",
            speeds: 12,
            chainringIDs: ["2x54-40", "2x52-36", "2x50-34"],
            cassetteIDs: ["12s-11-28", "12s-11-30", "12s-11-34"],
            note: "Racing"
        ),
        // Eleven-speed Dura-Ace and Ultegra are here because eleven-speed is
        // still the most common drivetrain sitting on a trainer: a very large
        // installed base of bikes, and of spare cassettes bought for the
        // trainer itself. Tiagra is deliberately absent — ten-speed is fading
        // and adds nothing these do not already cover.
        .init(
            id: "shimano-dura-ace-r9100",
            brand: .shimano,
            name: "Dura-Ace R9100",
            speeds: 11,
            chainringIDs: ["2x53-39", "2x52-36", "2x50-34"],
            cassetteIDs: ["11s-11-28", "11s-11-30", "11s-12-28"],
            note: "Racing"
        ),
        .init(
            id: "shimano-ultegra-r8100",
            brand: .shimano,
            name: "Ultegra R8100",
            speeds: 12,
            chainringIDs: ["2x52-36", "2x50-34"],
            cassetteIDs: ["12s-11-30", "12s-11-34"],
            note: "Road"
        ),
        .init(
            id: "shimano-ultegra-r8000",
            brand: .shimano,
            name: "Ultegra R8000",
            speeds: 11,
            chainringIDs: ["2x53-39", "2x52-36", "2x50-34"],
            cassetteIDs: [
                "11s-11-28", "11s-11-30", "11s-11-32", "11s-11-34",
            ],
            note: "Road"
        ),
        .init(
            id: "shimano-105-r7100",
            brand: .shimano,
            name: "105 R7100",
            speeds: 12,
            chainringIDs: ["2x52-36", "2x50-34"],
            cassetteIDs: ["12s-11-34", "12s-11-36"],
            note: "Most common on new bikes"
        ),
        .init(
            id: "shimano-105-r7000",
            brand: .shimano,
            name: "105 R7000",
            speeds: 11,
            chainringIDs: ["2x52-36", "2x50-34"],
            cassetteIDs: [
                "11s-11-28", "11s-11-30", "11s-11-32", "11s-11-34",
            ],
            note: "Road"
        ),
        .init(
            id: "shimano-grx-rx820",
            brand: .shimano,
            name: "GRX RX820",
            speeds: 12,
            chainringIDs: ["2x48-31"],
            cassetteIDs: ["12s-11-34", "12s-11-36"],
            note: "Gravel"
        ),
        .init(
            id: "shimano-grx-rx820-1x",
            brand: .shimano,
            name: "GRX RX820 1x",
            speeds: 12,
            chainringIDs: ["1x40", "1x42"],
            cassetteIDs: ["12s-11-34", "12s-11-36"],
            note: "Gravel, single ring"
        ),
        .init(
            id: "shimano-grx-rx810",
            brand: .shimano,
            name: "GRX RX810",
            speeds: 11,
            chainringIDs: ["2x48-31", "2x46-30"],
            cassetteIDs: ["11s-11-34"],
            note: "Gravel"
        ),

        // MARK: SRAM
        .init(
            id: "sram-red-axs",
            brand: .sram,
            name: "Red AXS",
            speeds: 12,
            chainringIDs: ["2x50-37", "2x48-35", "2x46-33"],
            cassetteIDs: ["12s-10-28", "12s-10-30", "12s-10-33"],
            note: "Racing"
        ),
        .init(
            id: "sram-force-axs",
            brand: .sram,
            name: "Force AXS",
            speeds: 12,
            chainringIDs: ["2x50-37", "2x48-35", "2x46-33", "2x43-30"],
            cassetteIDs: [
                "12s-10-28", "12s-10-30", "12s-10-33", "12s-10-36",
            ],
            note: "Road"
        ),
        .init(
            id: "sram-rival-axs",
            brand: .sram,
            name: "Rival AXS",
            speeds: 12,
            chainringIDs: ["2x48-35", "2x46-33", "2x43-30"],
            cassetteIDs: ["12s-10-30", "12s-10-33", "12s-10-36"],
            note: "Road"
        ),
        .init(
            id: "sram-xplr-1x",
            brand: .sram,
            name: "Force / Rival XPLR",
            speeds: 12,
            chainringIDs: ["1x38", "1x40", "1x42", "1x44", "1x46"],
            cassetteIDs: ["12s-10-44"],
            note: "Gravel, single ring"
        ),
        .init(
            id: "sram-apex-axs-1x",
            brand: .sram,
            name: "Apex AXS 1x",
            speeds: 12,
            chainringIDs: ["1x38", "1x40", "1x42", "1x44", "1x46"],
            cassetteIDs: ["12s-10-44", "12s-10-52"],
            note: "Gravel, wide range"
        ),

        // MARK: Campagnolo
        .init(
            id: "campagnolo-super-record-13",
            brand: .campagnolo,
            name: "Super Record 13",
            speeds: 13,
            chainringIDs: ["2x54-39", "2x52-36", "2x50-34", "2x48-32", "2x45-29"],
            cassetteIDs: ["13s-10-29", "13s-11-32"],
            note: "Racing"
        ),
        .init(
            id: "campagnolo-chorus",
            brand: .campagnolo,
            name: "Chorus",
            speeds: 12,
            chainringIDs: ["2x52-36", "2x50-34", "2x48-32"],
            cassetteIDs: ["12s-11-29", "12s-11-32", "12s-11-34"],
            note: "Road"
        ),
        .init(
            id: "campagnolo-ekar",
            brand: .campagnolo,
            name: "Ekar",
            speeds: 13,
            chainringIDs: ["1x38", "1x40", "1x42", "1x44"],
            cassetteIDs: ["13s-9-36", "13s-9-42", "13s-10-44"],
            note: "Gravel, single ring"
        ),
    ]

    /// A 105 R7100 with 50/34 and an 11-34: the single most common setup on new
    /// bikes, and the obvious thing to hand someone who has not chosen yet.
    public static let defaultGroupsetID = "shimano-105-r7100"

    public static func groupset(id: String) -> Groupset? {
        groupsets.first { $0.id == id }
    }

    public static var defaultGroupset: Groupset {
        groupset(id: defaultGroupsetID) ?? groupsets[0]
    }

    public static func groupsets(brand: GroupsetBrand) -> [Groupset] {
        groupsets.filter { $0.brand == brand }
    }

    /// The groupset a pair of parts belongs to, if any. Used to show a saved
    /// setup by the name printed on the bike rather than as two part numbers.
    ///
    /// Several groupsets share the same parts — 50/34 with an 11-34 is sold on
    /// everything from 105 to Dura-Ace — so the default is preferred when it
    /// fits. Guessing the most expensive groupset a rider *might* own is worse
    /// than guessing the most common one they probably do.
    public static func groupset(
        chainringID: String,
        cassetteID: String
    ) -> Groupset? {
        let matches = groupsets.filter {
            $0.chainringIDs.contains(chainringID)
                && $0.cassetteIDs.contains(cassetteID)
        }
        return matches.first { $0.id == defaultGroupsetID } ?? matches.first
    }
}
