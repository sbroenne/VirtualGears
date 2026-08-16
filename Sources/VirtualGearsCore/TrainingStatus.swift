import Foundation

/// The Training Status channel a fitness machine may publish. A real KICKR
/// offers it, and a riding app may read it to decide whether the trainer is
/// ready before it shows any numbers.
public enum FTMSTrainingStatus: UInt8, Sendable {
    /// Nothing is coming from the trainer yet.
    case idle = 0x01
    /// The rider is riding and the trainer is not following a stored workout,
    /// which is exactly what Virtual Gears passes through.
    case manualMode = 0x0D

    /// A flags byte of zero says no status string follows, which is all any
    /// riding app needs from this channel.
    public func encode() -> Data {
        Data([0x00, rawValue])
    }
}
