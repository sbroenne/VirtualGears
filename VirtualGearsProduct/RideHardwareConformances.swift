import CoreBluetooth
import UIKit
import VirtualGearsCore

/// The real hardware, meeting the promises the ride relies on.
///
/// The ride talks to these three through narrow protocols so it can also be
/// run against stand-ins, with no trainer, Click or PC in the room. Everything
/// here is a plain restatement of what the services already do: if one of these
/// extensions ever needs real logic, it belongs in the service instead.

extension KickrCentralService: TrainerLink {}

extension FTMSPeripheral: FitnessMachineBroadcast {}

extension ClickCentralService: ShifterLink {}

/// Keeps the screen lit while a ride is on.
@MainActor
final class DeviceScreenWake: ScreenWake {
    var keepAwake: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}

extension CBManagerState {
    var productDescription: String {
        switch self {
        case .unknown: "Bluetooth state is unknown"
        case .resetting: "Bluetooth is resetting"
        case .unsupported: "Bluetooth is unsupported"
        case .unauthorized: "Bluetooth permission is denied"
        case .poweredOff: "Bluetooth is off"
        case .poweredOn: "Bluetooth is on"
        @unknown default: "Bluetooth is unavailable"
        }
    }
}
