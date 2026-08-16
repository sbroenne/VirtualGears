import Foundation

/// The Bluetooth Cycling Power Service, as published *by* Virtual Gears.
///
/// The app has always spoken this service in the other direction, to find the
/// KICKR's Wahoo control characteristic, which is why `WahooKickrProtocol`
/// already names 1818.
public enum CyclingPowerUUID {
    public static let service = "1818"
    public static let measurement = "2A63"
    public static let feature = "2A65"
    public static let sensorLocation = "2A5D"

    /// Bit 3, crank revolution data supported. Nothing else is claimed.
    public static let featureValue = Data([0x08, 0x00, 0x00, 0x00])

    /// 12 is "rear hub", the honest answer for a direct-drive trainer.
    public static let sensorLocationValue = Data([12])
}

/// Turns the power and cadence Virtual Gears already relays into Cycling Power
/// Measurement packets.
///
/// This exists because some riding apps read nothing at all from the FTMS
/// Indoor Bike Data. MyWhoosh pairs, takes control and steers the trainer, then
/// shows 0 W and 0 rpm, and publishing this service alongside FTMS is what
/// makes it work. Measured on hardware; see DEVELOPMENT.md.
///
/// The power figure is the trainer's own. Only the crank *counter* is derived,
/// because FTMS reports cadence directly while this service reports revolutions
/// and the time of the last one, and a riding app divides one by the other to
/// get back to cadence.
public struct CyclingPowerBroadcast: Sendable {
    /// Revolutions counted so far, including the part of one in progress.
    private var revolutions: Double = 0
    /// The whole revolution most recently completed.
    private var completedRevolutions: Double = 0
    /// When that revolution happened, in seconds on the caller's clock.
    private var lastEventSeconds: TimeInterval = 0
    private var lastUpdateSeconds: TimeInterval?

    public init() {}

    /// - Parameters:
    ///   - powerWatts: the trainer's instantaneous power.
    ///   - cadenceRPM: the trainer's instantaneous cadence, if it reported one.
    ///   - now: seconds on any steadily increasing clock.
    public mutating func encode(
        powerWatts: Int16,
        cadenceRPM: Double?,
        at now: TimeInterval
    ) -> Data {
        defer { lastUpdateSeconds = now }

        // A first packet has no interval behind it, and a clock that went
        // backwards would wind the counter back, so both advance nothing.
        let elapsed = lastUpdateSeconds.map { now - $0 } ?? 0
        if let cadenceRPM, cadenceRPM > 0, elapsed > 0 {
            let revolutionsPerSecond = cadenceRPM / 60
            revolutions += revolutionsPerSecond * elapsed
            let whole = revolutions.rounded(.down)
            if whole > completedRevolutions {
                // The counter is read together with the time of the last whole
                // revolution, so that time is backdated by however far past it
                // this update landed.
                let overshoot = revolutions - whole
                lastEventSeconds = now - overshoot / revolutionsPerSecond
                completedRevolutions = whole
            }
        }

        var writer = FTMSByteWriter()
        // Bit 5, crank revolution data present. A trainer that reports no
        // cadence must not claim to, or a riding app shows a stuck 0 rpm
        // instead of nothing at all.
        writer.write(UInt16(cadenceRPM == nil ? 0 : 1 << 5))
        writer.write(powerWatts)
        if cadenceRPM != nil {
            writer.write(UInt16(truncatingIfNeeded: Int(completedRevolutions)))
            // Crank event time counts in 1024ths of a second and wraps.
            writer.write(
                UInt16(truncatingIfNeeded: Int((lastEventSeconds * 1024).rounded()))
            )
        }
        return writer.data
    }
}
