import CoreBluetooth
import Foundation
import ToolSupport
import VirtualGearsCore

/// Measures how a real KICKR behaves, so the app's timing and lifecycle rules
/// can be checked against the trainer instead of assumed.
///
/// It answers two questions the app's own logs cannot:
///
/// 1. How long does the trainer take to confirm a gear change? A held shift
///    button is now paced by that confirmation, so the answer says whether the
///    old fixed 300 ms repeat was ever slow enough to keep up.
/// 2. Does the trainer take control away when it is told to stop? The app now
///    refuses to recover control during a stop, which only matters if the
///    trainer really does drop it there.
///
/// It shifts through real gears using the same engine the app uses, so what is
/// measured is what a rider would actually experience.
///
/// Every run puts the wheel size back before it exits, including after a
/// failure, because the trainer works out speed and distance from it.
///
/// Run with the iPhone app closed: a KICKR takes one controlling connection.
let log = ToolLog(environmentKey: "KICKR_PROBE_LOG", defaultPath: "/tmp/kickr-probe.log")
let logPath = log.path

func say(_ text: String) { log.say(text) }

/// Every way out prints the same last line, so a script following the log knows
/// the probe is done instead of waiting for a write that never comes.
func finish(_ code: Int32) -> Never {
    ToolSupport.finish(sentinel: "kickr-probe finished.", code: code, say: say)
}

/// What this run is for. The wheel size cannot be read back from the trainer,
/// so proving whether it survives a power cut takes two runs with the plug
/// pulled in between.
enum ProbeMode {
    /// Time gear changes and check whether control survives a stop.
    case measure
    /// Leave a distinctive wheel size behind, on purpose.
    case set(millimeters: Double)
    /// Send each wheel size in turn, resetting to 2070 mm in between, and
    /// report which the trainer confirmed. This is how the recorded range
    /// evidence is produced.
    case sweep(millimeters: [Double])
    /// Work out the wheel size the trainer is currently using.
    case read
    /// Find out whether a riding app's standard FTMS reset wipes the wheel size
    /// the gears are riding on. RealVelo sends one a second and a half after it
    /// connects, which lands while gears are already set up, so the answer
    /// decides whether the app must stop passing resets straight through.
    case resetTest
    /// Ask the trainer what it claims to support, and find out whether it
    /// accepts the *standard* wheel-size command as well as Wahoo's own.
    case features
}

let mode: ProbeMode = {
    let arguments = CommandLine.arguments.dropFirst()
        .filter { !$0.hasPrefix("-") }
    switch arguments.first {
    case "set":
        let value = arguments.dropFirst().first.flatMap(Double.init) ?? 3105
        return .set(millimeters: value)
    case "sweep":
        let values = arguments.dropFirst().compactMap(Double.init)
        // The easy end of the shipping ladder, which the original ten-value
        // run never reached, up to the lowest value it did cover.
        return .sweep(
            millimeters: values.isEmpty
                ? [517.5, 525, 550, 575, 600, 625, 647] : values
        )
    case "read":
        return .read
    case "reset-test":
        return .resetTest
    case "features":
        return .features
    default:
        return .measure
    }
}()

enum ProbeError: Error {
    case notReady
    case timedOut
    case noGearsLeft
}

@MainActor
final class KickrProbe: NSObject {
    private var central: CBCentralManager!
    private var kickr: CBPeripheral? { finder.peripheral }
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var subscribed = Set<CBUUID>()
    private var hasStarted = false
    private var ignored = Set<String>()
    private var settleTask: Task<Void, Never>?

    private let ftmsService = CBUUID(string: FTMSUUID.fitnessMachineService)
    private let powerService = CBUUID(
        string: WahooKickrProtocol.cyclingPowerServiceUUID
    )
    private let controlUUID = CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
    private let statusUUID = CBUUID(string: FTMSUUID.fitnessMachineStatus)
    private let bikeDataUUID = CBUUID(string: FTMSUUID.indoorBikeData)
    private let wahooUUID = CBUUID(
        string: WahooKickrProtocol.controlCharacteristicUUID
    )
    private let featureUUID = CBUUID(string: FTMSUUID.fitnessMachineFeature)

    private lazy var finder = PeripheralFinder(
        scanServices: [ftmsService], discoveryServices: [ftmsService, powerService],
        say: say,
        matches: { [weak self] discovery in
            let name = discovery.peripheralName ?? ""
            guard name.uppercased().contains("KICKR") else {
                if self?.ignored.contains(name) == false {
                    self?.ignored.insert(name)
                    say("Ignoring \(name.isEmpty ? "an unnamed device" : name).")
                }
                return false
            }
            return true
        },
        foundMessage: { "Found \($0.peripheralName ?? "") at \($0.rssi) dBm. Connecting." }
    )

    /// One waiter per characteristic, which is all the protocol allows: a
    /// control point carries one outstanding request at a time.
    private let ftmsWaiter = CharacteristicWaiter<Data>()
    private let readWaiter = CharacteristicWaiter<Data>()
    private let wahooWaiter = CharacteristicWaiter<Data>()

    private var statusMessages: [Data] = []
    /// Speed as the trainer reports it, which is the only visible consequence
    /// of the wheel size and so the only way to work out what it is.
    private var speedSamples: [(at: Date, kilometersPerHour: Double)] = []
    private var warnedAboutSpeed = false
    private let neutral = TrainerSafety.referenceCircumferenceMillimeters

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
        // Runs whatever the radio does. Without it, a probe that is never told
        // Bluetooth is available — the shape a pending permission prompt takes —
        // would sit silently for ever.
        scheduleMainActorTimeout(after: .seconds(180)) {
            guard !self.hasStarted else { return }
            say(
                "Gave up after three minutes. If macOS asked for Bluetooth "
                    + "permission, answer it and run this again."
            )
            finish(1)
        }
    }

    // MARK: - The experiment

    private func run() async {
        do {
            _ = try await sendFTMS(.requestControl)
            say("Trainer handed over control.")
            switch mode {
            case .measure:
                let times = try await measureGearConfirmations()
                let heldControl = try await measureControlAfterStop()
                report(times: times, heldControl: heldControl)
                await restoreNeutral()
            case let .set(millimeters):
                try await leaveWheelSize(millimeters)
            case let .sweep(millimeters):
                try await sweepWheelSizes(millimeters)
            case .read:
                try await readWheelSize()
            case .resetTest:
                try await runResetTest()
            case .features:
                try await surveyFeatures()
            }
        } catch {
            say("\nThe probe stopped early: \(error)")
            if case .read = mode {} else if case .set = mode {}
            else if case .features = mode {} else {
                await restoreNeutral()
            }
        }
        say("\nDone. Full log in \(logPath)")
        finish(0)
    }

    /// Sets a wheel size no trainer uses by default, sends the standard FTMS
    /// reset a riding app sends, and then works out what the trainer is
    /// actually riding on afterwards.
    private func runResetTest() async throws {
        let marker = 4000.0
        say("\n== Does a riding app's reset wipe the gears? ==")
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: marker
        )
        let raw = try await sendWahoo(command)
        guard try WahooKickrResponse.decode(raw).confirmsSuccess(for: command)
        else {
            say("The trainer refused \(Int(marker)) mm, so there is nothing to test.")
            return
        }
        say("Wheel size set to \(Int(marker)) mm, which is nothing like any default.")

        do {
            _ = try await sendFTMS(.reset)
            say("Sent the standard FTMS reset, and the trainer accepted it.")
        } catch {
            say("The trainer refused the reset: \(error)")
            say("That alone would answer the question, but the read below still runs.")
        }

        // A reset drops control by the FTMS rules, and the read needs control
        // to ask for no resistance. Asking again here is exactly what a riding
        // app does, so a refusal is itself worth knowing about.
        do {
            _ = try await sendFTMS(.requestControl)
            say("Control was handed back after the reset.")
        } catch {
            say("The trainer would not hand control back after the reset: \(error)")
        }

        // A reset leaves the machine idle, and an idle KICKR stops reporting
        // speed. RealVelo sends start straight after its own reset, so doing
        // the same here both matches a real ride and gets the data flowing.
        do {
            _ = try await sendFTMS(.startOrResume)
            say("Sent start, the same as a riding app does after its reset.")
        } catch {
            say("The trainer would not start after the reset: \(error)")
        }

        try await readWheelSize(
            keptMessage: "That is still the odd size, so the reset did NOT touch the "
                + "wheel size. Passing a riding app's reset through to the "
                + "trainer does not break the gears.",
            lostMessage: "That is back to the default, so the reset DID wipe the wheel "
                + "size. A riding app connecting mid-session silently undoes "
                + "the current gear, and the app must stop passing resets "
                + "through while it is shifting."
        )
    }

    /// Deliberately leaves the trainer on an unusual wheel size, so that after
    /// the plug is pulled it is obvious whether it kept it or went back to its
    /// own default.
    private func leaveWheelSize(_ millimeters: Double) async throws {
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: millimeters
        )
        let raw = try await sendWahoo(command)
        guard try WahooKickrResponse.decode(raw).confirmsSuccess(for: command)
        else {
            say("The trainer refused that wheel size. Nothing was changed.")
            return
        }
        if millimeters == TrainerSafety.referenceCircumferenceMillimeters {
            say("\nWheel size set back to \(Int(millimeters)) mm, where it belongs.")
            return
        }
        say(
            """

            Wheel size set to \(Int(millimeters)) mm and left there on purpose.
            The trainer will report the wrong speed and distance until it is put
            back, so do not ride until the next step is done.

            Now unplug the trainer, wait about ten seconds, and plug it back in.
            Then run: ./Tools/KickrProbe/run.sh read
            """
        )
    }

    /// The trainer will not say what wheel size it is using, so this changes it
    /// to a known value mid-spin and reads the jump in speed. Speed is
    /// proportional to wheel size, so the size before the change is the known
    /// size multiplied by how much the speed fell.
    private func readWheelSize(
        keptMessage: String = "That is clearly not the default, so the trainer kept the odd "
            + "size across the power cut. Putting the wheel size right "
            + "after a crash genuinely matters: nothing else will.",
        lostMessage: String = "That is about the same as the known size, so the trainer did "
            + "not keep the odd size across the power cut. Putting the "
            + "wheel size right after a crash matters less than feared, "
            + "though it still matters while the trainer stays on."
    ) async throws {
        guard let kickr, let data = characteristics[bikeDataUUID] else {
            throw ProbeError.notReady
        }
        kickr.setNotifyValue(true, for: data)
        // A direct-drive trainer is geared up hard, so turning the pedals by
        // hand against normal resistance is a real effort. Asking for none
        // first makes the flywheel light enough to spin with one hand.
        do {
            _ = try await sendFTMS(.setTargetResistanceLevel(tenths: 0))
            say("Asked the trainer for no resistance, so it turns easily.")
        } catch {
            say("The trainer would not drop its resistance: \(error)")
        }
        say(
            """

            Now turn the pedals by hand and keep them going.

            It will take some effort even with no resistance: a direct-drive
            flywheel is heavy, and that is normal. What is not normal is the
            trainer pushing back harder the faster you go. Stop if that happens.
            Waiting for movement.
            """
        )
        try await waitForMovement()
        let before = try await collectSpeed(forSeconds: 4)
        let known = TrainerSafety.referenceCircumferenceMillimeters
        let command = try WahooKickrCommand.setWheelCircumference(
            millimeters: known
        )
        let changedAt = Date()
        _ = try await sendWahoo(command)
        say("Wheel size set to the known \(Int(known)) mm. Keep spinning.")
        let after = try await collectSpeed(forSeconds: 4)
        interpretWheelSize(
            before: before,
            after: after,
            changedAt: changedAt,
            known: known,
            keptMessage: keptMessage,
            lostMessage: lostMessage
        )
    }

    /// Waits for the pedals to turn for as long as it takes. The person doing
    /// this has to walk to the bike, so a deadline only makes them race the
    /// tool; the trainer is happy to sit connected in the meantime.
    private func waitForMovement() async throws {
        var reported = 0
        for tick in 0..<1800 {
            if let latest = speedSamples.last?.kilometersPerHour, latest > 1 {
                say("Movement detected at \(String(format: "%.1f", latest)) km/h.")
                return
            }
            if tick % 40 == 39, speedSamples.count != reported {
                reported = speedSamples.count
                let latest = speedSamples.last?.kilometersPerHour ?? 0
                say(
                    "Still waiting, take your time. \(reported) speed readings "
                        + "so far, latest \(String(format: "%.1f", latest)) km/h."
                )
            } else if tick % 40 == 39 {
                say("Still waiting, take your time. Spin whenever you are ready.")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw ProbeError.timedOut
    }

    @discardableResult
    private func collectSpeed(
        forSeconds seconds: Double
    ) async throws -> [(at: Date, kilometersPerHour: Double)] {
        let from = Date()
        try? await Task.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
        return speedSamples.filter { $0.at >= from }
    }

    private func interpretWheelSize(
        before: [(at: Date, kilometersPerHour: Double)],
        after: [(at: Date, kilometersPerHour: Double)],
        changedAt: Date,
        known: Double,
        keptMessage: String,
        lostMessage: String
    ) {
        say("\n== What wheel size was the trainer using? ==")
        // A hand spin slows down all the while, so only the samples either side
        // of the change are comparable; anything further out is mostly coasting.
        guard let last = before.last,
              let first = after.first(where: { $0.at > changedAt }),
              last.kilometersPerHour > 1,
              first.kilometersPerHour > 0.1 else {
            say("The spin stopped too soon to tell. Try again, spinning longer.")
            return
        }
        let ratio = last.kilometersPerHour / first.kilometersPerHour
        let estimate = known * ratio
        say(
            "Speed went from \(String(format: "%.1f", last.kilometersPerHour)) "
                + "to \(String(format: "%.1f", first.kilometersPerHour)) km/h "
                + "the moment the wheel size changed."
        )
        say("So it had been using roughly \(Int(estimate.rounded())) mm.")
        if abs(estimate - known) < 150 {
            say(lostMessage)
        } else {
            say(keptMessage)
        }
        say(
            "The trainer is now on \(Int(known)) mm, which is where it should be."
        )
        say("You can stop turning the pedals.")
    }

    /// Shifts up one gear at a time, exactly as holding the button does, and
    /// times how long the trainer takes to confirm each one.
    private func measureGearConfirmations() async throws -> [TimeInterval] {
        say("\n== How long does one gear change take to confirm? ==")
        var engine = try ConfirmedGearEngine(
            drivetrain: try Drivetrain.virtualLadder(),
            wheelSizeMillimeters: neutral
        )
        var times: [TimeInterval] = []
        for _ in 0..<8 {
            guard let change = engine.requestShift(by: 1) else {
                throw ProbeError.noGearsLeft
            }
            let began = Date()
            let raw = try await sendWahoo(change.command)
            let elapsed = Date().timeIntervalSince(began)
            let response = try WahooKickrResponse.decode(raw)
            guard engine.acknowledge(response) != nil
                    || engine.confirmedIndex == change.index else {
                say("Gear \(change.index + 1): the trainer did not confirm.")
                continue
            }
            times.append(elapsed)
            say(
                "Gear \(change.index + 1) "
                    + "(\(String(format: "%.1f", change.circumferenceMillimeters)) mm) "
                    + "confirmed in \(milliseconds(elapsed))"
            )
        }
        return times
    }

    /// Sends Stop the way ending a ride does, then asks for something that
    /// needs control, to see whether the trainer still grants it.
    private func measureControlAfterStop() async throws -> Bool {
        say("\n== Does the trainer keep control through a stop? ==")
        statusMessages.removeAll()
        _ = try await sendFTMS(.stopOrPause(.stop))
        say("Stop accepted.")
        // A message announcing lost control can arrive just after the reply to
        // Stop, so there is a moment for it to land.
        try? await Task.sleep(nanoseconds: 800_000_000)
        for data in statusMessages {
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            let decoded = (try? FitnessMachineStatus.decode(data))
                .map { "\($0)" } ?? "not recognised"
            say("Trainer announced: [\(hex)] — \(decoded)")
        }
        do {
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: neutral
            )
            let raw = try await sendWahoo(command)
            let held = try WahooKickrResponse.decode(raw)
                .confirmsSuccess(for: command)
            say(
                held
                    ? "A command after Stop was accepted, so control was kept."
                    : "A command after Stop was refused, so control was lost."
            )
            return held
        } catch {
            say("A command after Stop failed outright: \(error)")
            return false
        }
    }

    private func restoreNeutral() async {
        say("\n== Putting the wheel size back ==")
        do {
            _ = try? await sendFTMS(.requestControl)
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: neutral
            )
            let raw = try await sendWahoo(command)
            if try WahooKickrResponse.decode(raw).confirmsSuccess(for: command) {
                say("Wheel size back to \(Int(neutral)) mm. The trainer is as it was.")
            } else {
                say("WARNING: the trainer did not confirm the wheel size going back.")
            }
        } catch {
            say("WARNING: could not put the wheel size back: \(error)")
        }
    }

    /// Sends each wheel size in turn and records whether the trainer confirmed
    /// it, resetting to 2070 mm between probes so no two values can run
    /// together, and again at the end. Nothing is concluded from a value the
    /// trainer did not acknowledge.
    private func sweepWheelSizes(_ sizes: [Double]) async throws {
        say("\n== Wheel size range probe ==")
        say("Reference reset to \(Int(neutral)) mm between every probe.")
        var confirmed: [Double] = []
        var refused: [Double] = []
        for size in sizes {
            let command = try WahooKickrCommand.setWheelCircumference(
                millimeters: size
            )
            let started = Date()
            let raw = try await sendWahoo(command)
            let elapsed = Date().timeIntervalSince(started)
            if try WahooKickrResponse.decode(raw).confirmsSuccess(for: command) {
                confirmed.append(size)
                say("  \(size) mm confirmed in \(milliseconds(elapsed))")
            } else {
                refused.append(size)
                say("  \(size) mm REFUSED")
            }
            let back = try WahooKickrCommand.setWheelCircumference(
                millimeters: neutral
            )
            let backRaw = try await sendWahoo(back)
            guard try WahooKickrResponse.decode(backRaw)
                .confirmsSuccess(for: back)
            else {
                throw ProbeError.notReady
            }
        }
        say("\n== Result ==")
        say("Confirmed: " + confirmed.map { "\($0)" }.joined(separator: ", "))
        if refused.isEmpty {
            say("Refused: none")
        } else {
            say("Refused: " + refused.map { "\($0)" }.joined(separator: ", "))
        }
        await restoreNeutral()
    }

    private func report(times: [TimeInterval], heldControl: Bool) {
        say("\n== What this means for the app ==")
        guard !times.isEmpty else {
            say("Nothing was confirmed, so nothing can be concluded.")
            return
        }
        let slowest = times.max() ?? 0
        let average = times.reduce(0, +) / Double(times.count)
        say(
            "Confirmations: fastest \(milliseconds(times.min() ?? 0)), "
                + "average \(milliseconds(average)), "
                + "slowest \(milliseconds(slowest))"
        )
        if slowest > 0.3 {
            say(
                "At least one gear took longer than the 300 ms the app used to "
                    + "leave between repeats, so holding a button really could "
                    + "ask for gears faster than the trainer applies them."
            )
        } else {
            say(
                "Every gear confirmed inside 300 ms on this connection, so the "
                    + "old repeat rate was not outrunning the trainer here. "
                    + "Pacing by confirmation still cannot overshoot."
            )
        }
        say(
            heldControl
                ? "Control survived Stop this time. Refusing to recover during "
                    + "a stop costs nothing, and still covers the case where "
                    + "control is dropped."
                : "Control was lost at Stop, which is exactly when the app used "
                    + "to start recovering and re-apply a gear behind the "
                    + "stop's back."
        )
    }

    // MARK: - Talking to the trainer


    /// Asks the trainer two separate questions. First, what does it *claim* to
    /// support? Second, what does it actually do when sent the standard
    /// wheel-size command rather than Wahoo's own? The two answers often
    /// differ, which is the whole reason for asking both.
    private func surveyFeatures() async throws {
        say("\n== What the trainer says it can do ==")
        let raw = try await readCharacteristic(featureUUID)
        let hex = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        say("Raw feature bits: \(hex)")

        let feature = try FitnessMachineFeature.decode(raw)
        let claimsWheelSize = feature.targetSettingFeatures
            .contains(.wheelCircumference)
        say("Things it can measure: \(describe(feature.machineFeatures))")
        say("Things it accepts being set: "
            + describe(feature.targetSettingFeatures))
        say(
            claimsWheelSize
                ? "It CLAIMS to accept the standard wheel-size command."
                : "It does NOT claim to accept the standard wheel-size command."
        )

        say("\n== What happens when it is actually sent ==")
        // Sent at the value the trainer should be on anyway, so the answer
        // costs nothing whichever way it goes.
        statusMessages.removeAll()
        let tenths = UInt16(neutral * 10)
        let reply = try await sendFTMS(
            .setWheelCircumference(tenthsOfMillimeter: tenths)
        )
        let rereadHex = reply.map { String(format: "%02X", $0) }
            .joined(separator: " ")
        say("Reply: \(rereadHex)")

        let decoded = try FitnessMachineControlPointResponse.decode(reply)
        let accepted = decoded.result == .success
        say("Verdict: \(explain(decoded.result))")

        try? await Task.sleep(nanoseconds: 800_000_000)
        let announced = statusMessages.contains { $0.first == 0x13 }
        if accepted {
            say(
                announced
                    ? "It also announced the change, as the standard expects."
                    : "It accepted it but announced nothing, so whether it "
                        + "took effect is unproven."
            )
        }

        // A trainer that simply says yes to everything would look identical to
        // one that really supports the command, so this asks for something it
        // does not advertise and checks that it says no.
        say("\n== Is that yes worth anything? ==")
        let unadvertised = Data([0x14, 0x3C, 0x00])  // set target cadence
        let controlPoint = try await write(
            unadvertised,
            to: controlUUID,
            isWahoo: false
        )
        let controlHex = controlPoint.map { String(format: "%02X", $0) }
            .joined(separator: " ")
        let unsupported = try FitnessMachineControlPointResponse
            .decode(controlPoint)
        say("Asked for something it never advertised. Reply: \(controlHex)")
        let discriminates = unsupported.result != .success
        say(
            discriminates
                ? "It refused that one, so it does read the command before "
                    + "answering. The yes above means something."
                : "It said yes to that too, so it may be agreeing to anything. "
                    + "Treat the yes above with suspicion."
        )

        say("\n== Conclusion ==")
        if !discriminates {
            say("""
                This trainer says yes to commands it does not advertise, so its
                yes carries no information. Nothing can be concluded about the
                standard wheel-size command from the fact that it was accepted.

                Wahoo's own command is not affected: it answers with the wheel
                size it actually applied, so a change can be checked rather than
                assumed. That is why Virtual Gears uses it.
                """)
        } else if accepted {
            say("""
                The trainer refuses commands it does not support and accepted
                this one, so the standard command is genuinely handled. Whether
                it really moves the gearing still needs a ride, since the
                trainer cannot be asked what wheel size it is on.
                """)
        } else {
            say("""
                The trainer discriminates between commands and refused this one.
                The standard wheel-size command is not supported here. Wahoo's
                own command is the only way to shift this trainer, which is what
                Virtual Gears uses.
                """)
        }
        if claimsWheelSize && !discriminates {
            say("""

                Note that it does advertise wheel-size support. That claim is
                untested either way, not disproved.
                """)
        }
        say("\nNothing was changed. The trainer is on \(Int(neutral)) mm.")
    }

    private func explain(_ result: FTMSControlPointResult) -> String {
        switch result {
        case .success: return "accepted"
        case .opcodeNotSupported: return "refused, command not supported"
        case .invalidParameter: return "refused, it disliked the value"
        case .operationFailed: return "refused, the attempt failed"
        case .controlNotPermitted: return "refused, control not permitted"
        }
    }

    private func describe(_ features: FTMSMachineFeatures) -> String {
        var names: [String] = []
        if features.contains(.cadence) { names.append("cadence") }
        if features.contains(.resistanceLevel) { names.append("resistance") }
        if features.contains(.heartRateMeasurement) { names.append("heart rate") }
        if features.contains(.elapsedTime) { names.append("elapsed time") }
        if features.contains(.powerMeasurement) { names.append("power") }
        return names.isEmpty ? "nothing recognised" : names.joined(separator: ", ")
    }

    private func describe(_ features: FTMSTargetSettingFeatures) -> String {
        var names: [String] = []
        if features.contains(.resistanceLevel) { names.append("resistance") }
        if features.contains(.power) { names.append("power") }
        if features.contains(.indoorBikeSimulationParameters) {
            names.append("terrain")
        }
        if features.contains(.wheelCircumference) { names.append("wheel size") }
        return names.isEmpty ? "nothing recognised" : names.joined(separator: ", ")
    }

    private func readCharacteristic(_ uuid: CBUUID) async throws -> Data {
        guard let kickr, let characteristic = characteristics[uuid] else {
            throw ProbeError.notReady
        }
        return try await readWaiter.wait(
            timeout: .seconds(5),
            timedOut: ProbeError.timedOut
        ) {
            kickr.readValue(for: characteristic)
        }
    }

    private func sendFTMS(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> Data {
        try await write(try request.encode(), to: controlUUID, isWahoo: false)
    }

    private func sendWahoo(_ command: Data) async throws -> Data {
        try await write(command, to: wahooUUID, isWahoo: true)
    }

    private func write(
        _ payload: Data,
        to uuid: CBUUID,
        isWahoo: Bool
    ) async throws -> Data {
        guard let kickr, let characteristic = characteristics[uuid] else {
            throw ProbeError.notReady
        }
        let waiter = isWahoo ? wahooWaiter : ftmsWaiter
        return try await waiter.wait(
            timeout: .seconds(5),
            timedOut: ProbeError.timedOut
        ) {
            kickr.writeValue(payload, for: characteristic, type: .withResponse)
        }
    }
}

@MainActor
extension KickrProbe: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            say("Looking for a KICKR. Wake it, and close the phone app first.")
            finder.startScanning(with: central)
            scheduleMainActorTimeout(after: .seconds(60)) {
                guard !self.hasStarted else { return }
                say(
                    "No KICKR answered in a minute. Wake it, and close "
                        + "the phone app, which takes the one connection it has."
                )
                finish(1)
            }
        case .unauthorized:
            say("macOS refused Bluetooth. Allow it for this tool and run again.")
            finish(1)
        case .poweredOff:
            say("Bluetooth is off.")
            finish(1)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // The iPhone running Virtual Gears also advertises as a fitness machine,
        // so the trainer has to be picked by name rather than by service.
        finder.connectFirstMatch(
            from: central, peripheral: peripheral,
            advertisementData: advertisementData, rssi: RSSI, delegate: self
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        finder.discoverServices(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        say("The trainer disconnected.")
        finish(1)
    }
}

@MainActor
extension KickrProbe: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
            if [controlUUID, statusUUID, wahooUUID, bikeDataUUID]
                .contains(characteristic.uuid) {
                say("Found the \(label(characteristic.uuid)) channel.")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        startWhenSettled()
    }

    private func label(_ uuid: CBUUID) -> String {
        switch uuid {
        case controlUUID: return "standard control"
        case statusUUID: return "status"
        case wahooUUID: return "Wahoo gear"
        case bikeDataUUID: return "speed"
        default: return uuid.uuidString
        }
    }

    /// Discovery arrives in pieces, so this waits for a quiet moment rather
    /// than guessing which channel reports itself last.
    private func startWhenSettled() {
        // Once the experiment is under way this must not fire again. It runs
        // inside settleTask, so cancelling that here would cancel the
        // experiment itself — and a cancelled task's sleeps return at once,
        // which silently collapses every wait the experiment depends on.
        // Subscribing to the speed channel mid-run is enough to trigger it.
        guard !hasStarted else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, !self.hasStarted else { return }
            guard self.characteristics[self.controlUUID] != nil,
                  self.characteristics[self.wahooUUID] != nil else {
                say("The trainer is missing a channel this probe needs.")
                finish(1)
            }
            self.hasStarted = true
            say("Connected and listening.")
            await self.run()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        subscribed.insert(characteristic.uuid)
        startWhenSettled()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case featureUUID:
            readWaiter.resume(returning: data)
        case controlUUID:
            ftmsWaiter.resume(returning: data)
        case wahooUUID:
            wahooWaiter.resume(returning: data)
        case statusUUID:
            statusMessages.append(data)
        case bikeDataUUID:
            do {
                let decoded = try IndoorBikeData.decode(data)
                if let speed = decoded.instantaneousSpeedKilometersPerHour {
                    speedSamples.append((at: Date(), kilometersPerHour: speed))
                } else if !warnedAboutSpeed {
                    warnedAboutSpeed = true
                    say("The trainer reports data but leaves speed out of it.")
                }
            } catch {
                if !warnedAboutSpeed {
                    warnedAboutSpeed = true
                    let hex = data.map { String(format: "%02X", $0) }
                        .joined(separator: " ")
                    say("Could not read the speed message [\(hex)]: \(error)")
                }
            }
        default:
            break
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
log.clear()
let probe = MainActor.assumeIsolated { KickrProbe() }
MainActor.assumeIsolated { probe.start() }
RunLoop.main.run()
