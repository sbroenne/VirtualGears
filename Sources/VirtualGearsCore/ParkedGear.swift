import Foundation

/// The gear the bike is left sitting in on the trainer.
///
/// The bike never shifts. It is parked in one gear for the whole ride, and
/// Virtual Gears changes gear by changing the wheel size the trainer works
/// from. What the rider's legs feel is therefore
///
///     feel  ∝  parked ratio  ×  wheel circumference we set
///
/// The app only controls the second half of that. Until this type existed it
/// silently assumed the first half equalled its own starting gear, so a rider
/// parked in the big ring on the smallest cog got a ladder that was ninety per
/// cent harder than the one on the screen — the easy half simply did not exist.
///
/// The step *sizes* were always right, because the scaling is relative. Only the
/// position of the whole ladder was wrong, which is exactly why it never looked
/// like a bug.
public struct ParkedGear: Codable, Equatable, Hashable, Sendable {
    public let chainringTeeth: Int
    public let cogTeeth: Int

    public init?(chainringTeeth: Int, cogTeeth: Int) {
        guard chainringTeeth > 0, cogTeeth > 0 else { return nil }
        self.chainringTeeth = chainringTeeth
        self.cogTeeth = cogTeeth
    }

    public var ratio: Double {
        Double(chainringTeeth) / Double(cogTeeth)
    }

    /// The way a rider says it out loud: "fifty, fifteen".
    public var name: String {
        "\(chainringTeeth)/\(cogTeeth)"
    }
}

/// What the rider physically has on the trainer, as opposed to the gearing they
/// asked the app to simulate. The two are unrelated: you can ride a single-sprocket
/// Zwift Cog and simulate a twelve-speed groupset, and most riders will.
public struct PhysicalSetup: Codable, Equatable, Sendable {
    /// Largest first, matching how a groupset is named.
    public var chainringTeeth: [Int]
    /// Smallest first. A single value means a single sprocket, such as a Zwift Cog.
    public var cogTeeth: [Int]
    /// Nil until the rider has confirmed it. Setup is not finished until they have,
    /// because guessing this quietly corrupts every gear.
    public var parkedChainringTeeth: Int?
    public var parkedCogTeeth: Int?

    /// A compact road bike with an 11-34 cassette — the setup most riders own.
    public static let `default` = PhysicalSetup(
        chainringTeeth: [50, 34],
        cogTeeth: [11, 12, 13, 14, 15, 17, 19, 21, 24, 27, 30, 34]
    )

    public init(
        chainringTeeth: [Int],
        cogTeeth: [Int],
        parkedChainringTeeth: Int? = nil,
        parkedCogTeeth: Int? = nil
    ) {
        self.chainringTeeth = chainringTeeth
        self.cogTeeth = cogTeeth
        self.parkedChainringTeeth = parkedChainringTeeth
        self.parkedCogTeeth = parkedCogTeeth
    }

    /// True when the bike has one sprocket rather than a cassette, so only the
    /// chainring is worth asking about.
    public var isSingleSprocket: Bool { cogTeeth.count == 1 }

    /// The gear the rider confirmed, if they have confirmed one.
    public var parkedGear: ParkedGear? {
        guard let parkedChainringTeeth, let parkedCogTeeth else { return nil }
        return ParkedGear(
            chainringTeeth: parkedChainringTeeth,
            cogTeeth: parkedCogTeeth
        )
    }

    public mutating func park(in gear: ParkedGear) {
        parkedChainringTeeth = gear.chainringTeeth
        parkedCogTeeth = gear.cogTeeth
    }
}

/// Works out which gear to tell the rider to park in.
///
/// README already says to leave the bike in a quiet, straight chain line. That
/// guidance is right; it just stops one question short, because it never asks
/// which gear that turned out to be. Rather than ask an open question, the app
/// names the gear — the quietest one that still works — and lets the rider
/// confirm or correct it.
public enum ParkedGearAdvice {
    /// How much clearance to keep from the hard limits, so a rider sitting right
    /// on the edge does not lose their top gear to a rounding tenth.
    public static let margin = 1.05

    /// Every parked ratio that lets *all* of a drivetrain's gears reach the
    /// trainer, at every wheel size a riding app may ask for.
    ///
    /// The hard end is a real limit: the command tops out at 6553.5 mm, so at a
    /// 2400 mm wheel the hardest gear needs
    /// `parked ratio ≥ hardest ratio / 2.73`. Park below that and the top of the
    /// ladder silently stops working the moment a riding app sets a big wheel.
    /// This is why "small ring, middle cog" cannot be a fixed sentence: on a
    /// 105 it lands on 34/17 = 2.00, on a GRX 31/17 = 1.82, both under the floor
    /// for a full virtual ladder.
    public static func workableRatios(
        for drivetrain: Drivetrain,
        scaleRange: ClosedRange<Double> = TrainerSafety.supportedScaleRange
    ) -> ClosedRange<Double>? {
        guard let easiest = drivetrain.gears.first?.ratio,
              let hardest = drivetrain.gears.last?.ratio,
              easiest > 0, hardest > 0
        else {
            return nil
        }
        let lowest = hardest / scaleRange.upperBound
        let highest = easiest / scaleRange.lowerBound
        guard lowest <= highest else { return nil }
        return lowest...highest
    }

    /// The gear to recommend: the quietest one that still works.
    ///
    /// Indoors the trainer is the loudest thing in the room and its flywheel
    /// speed is set by the parked ratio, so a lower parked ratio is a quieter
    /// ride — a middle cog on the small ring spins the flywheel around half as
    /// fast as the big ring on the smallest cog. Badly cross-chained corners are
    /// excluded, so the chain line stays straight too.
    ///
    /// Because the app compensates for whatever is confirmed, the parked gear
    /// can be chosen purely for quietness.
    public static func suggestion(
        for setup: PhysicalSetup,
        simulating drivetrain: Drivetrain
    ) -> ParkedGear? {
        guard let workable = workableRatios(for: drivetrain) else { return nil }
        let floor = workable.lowerBound * margin
        let ceiling = workable.upperBound / margin

        let candidates = usableParkedGears(in: setup)
            .filter { $0.ratio >= floor && $0.ratio <= ceiling }

        // Quietest first. If nothing clears the margin, fall back to anything
        // that merely works rather than leaving the rider without a suggestion.
        if let quietest = candidates.min(by: { $0.ratio < $1.ratio }) {
            return quietest
        }
        return usableParkedGears(in: setup)
            .filter { workable.contains($0.ratio) }
            .min { $0.ratio < $1.ratio }
    }

    /// True when the confirmed gear puts part of the ladder out of the trainer's
    /// reach, so the app can say so plainly instead of failing mid-ride.
    public static func isWorkable(
        _ gear: ParkedGear,
        simulating drivetrain: Drivetrain
    ) -> Bool {
        guard let workable = workableRatios(for: drivetrain) else { return false }
        return workable.contains(gear.ratio)
    }

    /// The gears worth parking in: real combinations of the rider's own parts,
    /// with the cross-chained corners left out.
    static func usableParkedGears(in setup: PhysicalSetup) -> [ParkedGear] {
        let rings = setup.chainringTeeth.sorted()
        let cogs = setup.cogTeeth.sorted(by: >)
        guard !rings.isEmpty, !cogs.isEmpty else { return [] }
        guard rings.count > 1 else {
            return cogs.compactMap {
                ParkedGear(chainringTeeth: rings[0], cogTeeth: $0)
            }
        }

        let last = cogs.count - 1
        let limit = min(
            min(Drivetrain.crossChainCogLimit, max(1, cogs.count / 4)),
            last
        )
        var gears: [ParkedGear] = []
        for (position, ring) in rings.enumerated() {
            let lower = position == 0 ? 0 : limit
            let upper = position == rings.count - 1 ? last : last - limit
            guard lower <= upper else { continue }
            for index in lower...upper {
                if let gear = ParkedGear(
                    chainringTeeth: ring,
                    cogTeeth: cogs[index]
                ) {
                    gears.append(gear)
                }
            }
        }
        return gears
    }
}
