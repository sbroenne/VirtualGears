import Foundation

/// What is known about a riding app at the moment it asks for something.
public struct FTMSControlRequest: Equatable, Sendable {
    public var request: FitnessMachineControlPointRequest
    public var requesterID: UUID
    /// Who currently holds the trainer, if anyone.
    public var ownerID: UUID?
    /// Whether that holder is still connected and subscribed. A riding app
    /// whose link drops does not reliably get to unsubscribe on the way out,
    /// so a claim can outlive the app that made it.
    public var ownerIsPresent: Bool
    /// Whether the asking app's control-point subscription is the current one.
    /// Commands arriving on a stale subscription belong to a conversation that
    /// has already ended.
    public var requesterSubscriptionIsCurrent: Bool
    /// Whether the asking app is subscribed to the control point at all. An app
    /// that never subscribed cannot be answered, since the answer is an
    /// indication on that very characteristic.
    public var requesterIsSubscribed: Bool
    /// Whether the proxy is in a state to act on commands at all.
    public var isAcceptingCommands: Bool

    public init(
        request: FitnessMachineControlPointRequest,
        requesterID: UUID,
        ownerID: UUID? = nil,
        ownerIsPresent: Bool = false,
        requesterSubscriptionIsCurrent: Bool = true,
        requesterIsSubscribed: Bool = true,
        isAcceptingCommands: Bool = true
    ) {
        self.request = request
        self.requesterID = requesterID
        self.ownerID = ownerID
        self.ownerIsPresent = ownerIsPresent
        self.requesterSubscriptionIsCurrent = requesterSubscriptionIsCurrent
        self.requesterIsSubscribed = requesterIsSubscribed
        self.isAcceptingCommands = isAcceptingCommands
    }
}

public enum FTMSControlDecision: Equatable, Sendable {
    /// Pass the request on to the trainer.
    case handOn
    /// Answer the riding app directly, without troubling the trainer.
    case refuse(FTMSControlPointResult)
}

/// Who is allowed to steer the trainer.
///
/// Only one riding app may steer at a time, and the whole difficulty is
/// deciding when a claim has expired. Too eager, and a brief wobble hands the
/// trainer to nobody mid-ride. Too reluctant, and a riding app that crashed
/// keeps the trainer locked with nothing on the PC able to release it.
public enum FTMSControlOwnership {
    public static func decide(_ request: FTMSControlRequest) -> FTMSControlDecision {
        guard request.isAcceptingCommands, request.requesterSubscriptionIsCurrent else {
            return .refuse(.operationFailed)
        }
        guard request.requesterIsSubscribed else {
            return .refuse(.controlNotPermitted)
        }
        if request.request == .requestControl {
            // An absent owner's claim is not honoured. Holding the trainer for
            // a connection that no longer exists locks out the very app trying
            // to come back.
            if let owner = request.ownerID,
               owner != request.requesterID,
               request.ownerIsPresent
            {
                return .refuse(.controlNotPermitted)
            }
            return .handOn
        }
        // Every other command needs the claim already in hand. Asking to steer
        // is how an app earns it; it is not granted by simply steering.
        guard request.ownerID == request.requesterID else {
            return .refuse(.controlNotPermitted)
        }
        return .handOn
    }

    /// Who holds the trainer after a request has been answered. Only a granted
    /// request moves the claim, so a refusal or a failure leaves it where it
    /// was.
    public static func owner(
        after request: FitnessMachineControlPointRequest,
        result: FTMSControlPointResult,
        currentOwner: UUID?,
        requesterID: UUID
    ) -> UUID? {
        guard result == .success else { return currentOwner }
        switch request {
        case .requestControl:
            return requesterID
        case .reset:
            return nil
        default:
            return currentOwner
        }
    }
}
