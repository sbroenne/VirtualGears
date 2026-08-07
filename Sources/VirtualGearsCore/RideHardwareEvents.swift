import Foundation

public enum ShiftDirection: Equatable, Sendable {
    case harder
    case easier
}

public enum ShiftRequest: Equatable, Sendable {
    case single(ShiftDirection)
    /// A button has been held long enough to mean "keep going". The sweep is
    /// then paced by the trainer rather than by a timer, so it runs as fast as
    /// the trainer can really confirm gears instead of dropping the beats that
    /// land while it is still working.
    case holdBegan(ShiftDirection)
    /// The button was let go. The sweep stops after the gear already in flight.
    case holdEnded
}

public struct KickrCapabilities: Equatable, Sendable {
    public var feature: FitnessMachineFeature?
    public var resistanceRange: SupportedResistanceLevelRange?
    public var supportsWahooControl = false

    public init(
        feature: FitnessMachineFeature? = nil,
        resistanceRange: SupportedResistanceLevelRange? = nil,
        supportsWahooControl: Bool = false
    ) {
        self.feature = feature
        self.resistanceRange = resistanceRange
        self.supportsWahooControl = supportsWahooControl
    }
}

public enum KickrEvent: Equatable, Sendable {
    case bikeData(IndoorBikeData)
    case rawBikeData(Data)
    case status(FitnessMachineStatus)
    case controlResponse(FitnessMachineControlPointResponse)
    case wahooResponse(WahooKickrResponse)
    case commandFailed(String)
}

public enum KickrCommandResult: Equatable, Sendable {
    case ftms(FitnessMachineControlPointResponse)
    case wahoo(WahooKickrResponse)
}

public enum FTMSPeripheralEvent: Equatable, Sendable {
    case advertisingStarted
    case advertisingStopped
    case centralSubscribed(UUID, characteristic: String)
    case centralUnsubscribed(UUID, characteristic: String)
    case controlRequest(UUID, FitnessMachineControlPointRequest)
    case controlResponse(UUID, FitnessMachineControlPointResponse)
    case failed(String)
}

public struct FTMSPeripheralCommandResult: Sendable {
    public let result: FTMSControlPointResult
    public let status: FitnessMachineStatus?

    public init(
        result: FTMSControlPointResult,
        status: FitnessMachineStatus? = nil
    ) {
        self.result = result
        self.status = status
    }

    public static func success(
        status: FitnessMachineStatus? = nil
    ) -> Self {
        .init(result: .success, status: status)
    }
}

