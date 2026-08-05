import Foundation

/// What a ride needs from the hardware, and nothing more.
///
/// The ride used to talk to the Bluetooth classes directly, which meant none of
/// it could be checked without a trainer, a Click and a PC in the room. Three
/// bugs that a rider hit in twenty minutes had sat through two code reviews
/// because nothing could exercise them. These protocols are narrow on purpose:
/// they list only what the ride actually asks for, so a stand-in is small
/// enough to be obviously honest.

/// Something the ride waits on before it can start.
@MainActor
public protocol ConnectableLink: AnyObject {
    var isReady: Bool { get }
    var state: ProductConnectionState { get }
}

/// The trainer the ride is borrowing.
@MainActor
public protocol TrainerLink: ConnectableLink {
    var hasFTMSControl: Bool { get }
    var selectedID: UUID? { get }
    var eventHandler: ((KickrEvent) -> Void)? { get set }
    var stateHandler: ((ProductConnectionState) -> Void)? { get set }

    func execute(
        _ request: FitnessMachineControlPointRequest
    ) async throws -> FitnessMachineControlPointResponse
    func executeWahoo(_ data: Data) async throws -> WahooKickrResponse
    func resumeSavedConnection()
    func disconnect(restoringCircumferenceMillimeters: Double?)
}

/// The trainer the riding app thinks it is talking to.
@MainActor
public protocol FitnessMachineBroadcast: AnyObject {
    var isAdvertising: Bool { get }
    /// Every app that has asked for ride data, and the one steering, if any.
    /// The ride screen shows both so the rider can tell a riding app that is
    /// merely watching from one that is actually in charge.
    var subscribedAppCount: Int { get }
    var controllingAppID: UUID? { get }
    var latestEvent: FTMSPeripheralEvent? { get }
    var commandHandler: ((
        FitnessMachineControlPointRequest,
        UUID
    ) async -> FTMSPeripheralCommandResult)? { get set }

    func startAdvertising()
    func stopAcceptingCommands()
    func stopAdvertising()
    func relayIndoorBikeData(_ data: Data)
    func notifyControlLost()
}

/// The buttons on the handlebars, if the rider has any.
@MainActor
public protocol ShifterLink: ConnectableLink {
    var shiftHandler: ((ShiftRequest) -> Void)? { get set }

    func resumeSavedConnection()
    func disconnect()
}

/// Keeping the screen lit while riding.
///
/// Behind a protocol only so the ride can be checked off the phone: UIKit does
/// not exist on the machine the tests run on.
@MainActor
public protocol ScreenWake: AnyObject {
    var keepAwake: Bool { get set }
}
