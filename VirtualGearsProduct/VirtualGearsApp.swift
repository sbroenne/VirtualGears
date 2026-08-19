import SwiftUI
import VirtualGearsCore

@main
struct VirtualGearsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurationStore: ConfigurationStore
    @State private var kickr: KickrCentralService
    @State private var click: ClickCentralService
    @State private var headwind: HeadwindCentralService
    @State private var coordinator: ProxyCoordinator
    @State private var isDemoMode = false

    init() {
        let defaults: UserDefaults
#if DEBUG
        defaults = ScreenshotFixture.current == nil
            ? .standard : ScreenshotFixture.makeDefaults()
#else
        defaults = .standard
#endif
        let configurationStore = ConfigurationStore(defaults: defaults)
        let kickr = KickrCentralService(defaults: defaults)
        let click = ClickCentralService(defaults: defaults)
        let headwind = HeadwindCentralService(defaults: defaults)
        _configurationStore = State(initialValue: configurationStore)
        _kickr = State(initialValue: kickr)
        _click = State(initialValue: click)
        _headwind = State(initialValue: headwind)
        _coordinator = State(initialValue: ProxyCoordinator(
            kickr: kickr,
            click: click,
            peripheral: FTMSPeripheral(),
            screen: DeviceScreenWake(),
            defaults: defaults
        ))
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let scenario = ScreenshotFixture.current {
                ScreenshotFixtureView(
                    scenario: scenario,
                    store: configurationStore,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    coordinator: coordinator
                )
            } else {
                productView
            }
#else
            productView
#endif
        }
    }

    private var productView: some View {
        VirtualGearsHomeView(
            store: configurationStore,
            kickr: kickr,
            click: click,
            headwind: headwind,
            coordinator: coordinator,
            isDemoMode: $isDemoMode
        )
        .onChange(of: configurationStore.configuration.setupComplete) {
            if !configurationStore.configuration.setupComplete {
                Task { await coordinator.shutdown() }
            }
        }
        .onChange(of: headwind.hasSavedDevice) { _, saved in
            if !saved, configurationStore.configuration.usesHeadwind {
                configurationStore.configuration.forgetHeadwind()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !isDemoMode,
                  !coordinator.isShiftingPresented else { return }
            kickr.autoConnectSavedDevice()
            coordinator.makeTrainerProxyAvailable()
            if configurationStore.configuration.usesClick {
                click.autoConnectSavedDevice()
            }
            if configurationStore.configuration.usesHeadwind {
                headwind.autoConnectSavedDevice()
            }
            coordinator.resetInterruptedWheelSizeIfNeeded()
        }
    }
}

#if DEBUG
enum ScreenshotFixture: String {
    case starting = "-shotStarting"
    case startupLooking = "-shotStartupLooking"
    case startupChoosing = "-shotStartupChoosing"
    case ready = "-shotReady"
    /// A trainer that is connected but a bike whose gear has not been
    /// confirmed — the one blocker a rider cannot fix by waiting.
    case unparked = "-shotUnparked"
    case failed = "-shotFailed"
    case ride = "-shotRide"
    case rideAccessibility = "-shotRideAccessibility"
    case rideWaiting = "-shotRideWaiting"
    case rideLowBattery = "-shotRideLowBattery"
    case ridePending = "-shotRidePending"
    case ridePressed = "-shotRidePressed"
    case rideReconnecting = "-shotRideReconnecting"
    case rideStopping = "-shotRideStopping"
    case rideWheelSize = "-shotRideWheelSize"
    case settings = "-shotSettings"
    case settingsSearching = "-shotSettingsSearching"
    case settingsResults = "-shotSettingsResults"
    case settingsUnsupported = "-shotSettingsUnsupported"
    case settingsTimedOut = "-shotSettingsTimedOut"
    case settingsBluetoothIssue = "-shotSettingsBluetoothIssue"
    case settingsStalled = "-shotSettingsStalled"
    case settingsClickLowBattery = "-shotSettingsClickLowBattery"
    case settingsClickDuplicates = "-shotSettingsClickDuplicates"
    case settingsClickIdentifying = "-shotSettingsClickIdentifying"
    case settingsUnsafeGears = "-shotSettingsUnsafeGears"
    case settingsAccessibility = "-shotSettingsAccessibility"
    case setupWizard = "-shotSetupWizard"
    case setupWizardAccessibility = "-shotSetupWizardAccessibility"
    case gears = "-shotGears"
    case realGears = "-shotRealGears"
    case headwind = "-shotHeadwind"
    case headwindAutomatic = "-shotHeadwindAutomatic"
    case headwindPending = "-shotHeadwindPending"
    case headwindError = "-shotHeadwindError"
    case demo = "-shotDemo"

    static let kickrID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let clickID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let headwindID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let ridingAppID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    private static let defaultsSuiteName = "VirtualGears.ScreenshotFixture"

    static var current: Self? {
        ProcessInfo.processInfo.arguments.lazy.compactMap(Self.init(rawValue:)).first
    }

    static func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}

private struct ScreenshotFixtureView: View {
    let scenario: ScreenshotFixture
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var headwind: HeadwindCentralService
    @Bindable var coordinator: ProxyCoordinator

    var body: some View {
        Group {
            switch scenario {
            case .starting, .startupLooking, .startupChoosing, .ready, .failed,
                 .unparked:
                StartupView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    coordinator: coordinator,
                    beginsDiscovery: false,
                    startsWithTrainerChoice: scenario == .startupChoosing
                )
            case .ride, .rideAccessibility, .rideWaiting, .rideLowBattery,
                 .ridePending, .ridePressed, .rideReconnecting, .rideStopping,
                 .rideWheelSize:
                ShiftingView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    coordinator: coordinator,
                    onRiderStop: {}
                )
            case .settings, .settingsSearching, .settingsResults,
                 .settingsUnsupported, .settingsTimedOut,
                 .settingsBluetoothIssue, .settingsStalled,
                 .settingsClickLowBattery, .settingsClickDuplicates,
                 .settingsClickIdentifying, .settingsUnsafeGears,
                 .settingsAccessibility:
                NavigationStack {
                    SetupView(
                        store: store,
                        kickr: kickr,
                        click: click,
                        headwind: headwind,
                        autoConnectsOnAppear: false
                    )
                }
            case .setupWizard, .setupWizardAccessibility:
                NavigationStack {
                    SetupWizardView(store: store, onFinish: {})
                }
            case .gears, .realGears:
                NavigationStack {
                    GearChoiceView(store: store)
                }
            case .headwind, .headwindAutomatic, .headwindPending, .headwindError:
                NavigationStack {
                    HeadwindControlView(headwind: headwind)
                }
            case .demo:
                DemoModeView(onExit: {})
            }
        }
        .dynamicTypeSize(
            scenario == .rideAccessibility
                || scenario == .setupWizardAccessibility
                || scenario == .settingsAccessibility
                ? .accessibility5 : .large
        )
        .task {
            stage()
            try? await Task.sleep(for: .milliseconds(500))
            stage()
        }
    }

    private func stage() {
        guard scenario != .demo else { return }
        var configuration = AppConfiguration()
        // Every fixture here represents a rider who has already been through
        // setup once, not a first launch — so the guide should not pop up
        // and steal the screenshot. The wizard fixture is the one exception:
        // it exists to test the guide itself, so it must start unseen.
        if scenario != .setupWizard {
            configuration.completeSetupWizard()
        }
        if scenario != .startupLooking && scenario != .startupChoosing {
            configuration.rememberKickr(
                named: "Wahoo KICKR 2A93",
                id: ScreenshotFixture.kickrID
            )
        }
        configuration.rememberClick(
            named: "Zwift Click",
            id: ScreenshotFixture.clickID
        )
        configuration.rememberHeadwind(
            named: "KICKR HEADWIND 4D21",
            id: ScreenshotFixture.headwindID
        )
        configuration.usesVirtualGears = scenario != .realGears
        if scenario == .settingsUnsafeGears {
            configuration.usesVirtualGears = true
            configuration.gearLadderID = GearLadderCatalog.customLadderID
            configuration.customLadder = CustomGearLadder(
                gearCount: 24,
                easiestRatioHundredths: 24,
                hardestRatioHundredths: 1_000
            )
        }
        // The screenshot rider has already parked the bike and confirmed the
        // gear, which is the state every screen after setup is drawn in.
        if scenario != .unparked {
            configuration.parkInSuggestion()
        }
        store.configuration = configuration

        let trainerCandidates = [
            BluetoothCandidate(
                id: ScreenshotFixture.kickrID,
                name: "Wahoo KICKR 2A93",
                compatibility: .supported
            ),
            BluetoothCandidate(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!,
                name: scenario == .settingsUnsupported
                    ? "Wahoo KICKR SNAP 7B20" : "Wahoo KICKR 7B20",
                compatibility: scenario == .settingsUnsupported
                    ? .unsupported(
                        model: "KICKR SNAP",
                        reason: "Wheel-on trainers do not support virtual shifting."
                    )
                    : .supported
            ),
        ]
        let stagedTrainerState: ProductConnectionState
        switch scenario {
        case .starting:
            stagedTrainerState = .connecting(name: configuration.kickrName)
        case .startupLooking, .settingsSearching:
            stagedTrainerState = .scanning
        case .settingsBluetoothIssue:
            stagedTrainerState = .unavailable(
                "Bluetooth permission is required to find equipment."
            )
        case .settingsStalled:
            stagedTrainerState = .connecting(name: configuration.kickrName)
        default:
            stagedTrainerState = .ready
        }
        kickr.stageScreenshot(
            name: configuration.kickrName.isEmpty
                ? "Wahoo KICKR 2A93" : configuration.kickrName,
            state: stagedTrainerState,
            candidates: scenario == .startupChoosing
                || scenario == .settingsResults
                || scenario == .settingsUnsupported
                ? trainerCandidates : [],
            stalled: scenario == .settingsStalled
        )
        let duplicateClicks = [
            BluetoothCandidate(
                id: ScreenshotFixture.clickID,
                name: "Zwift Click"
            ),
            BluetoothCandidate(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000012")!,
                name: "Zwift Click"
            ),
        ]
        click.stageScreenshot(
            name: configuration.clickName,
            batteryLevel: scenario == .settingsClickLowBattery ? 15 : 82,
            candidates: scenario == .settingsClickDuplicates
                || scenario == .settingsClickIdentifying ? duplicateClicks : [],
            identifying: scenario == .settingsClickIdentifying
                ? ScreenshotFixture.clickID : nil
        )
        headwind.stageScreenshot(
            name: configuration.headwindName ?? "KICKR HEADWIND",
            speed: 50,
            manual: scenario != .headwindAutomatic,
            pending: scenario == .headwindPending,
            error: scenario == .headwindError
                ? "The Headwind did not confirm the change." : nil
        )

        if scenario == .rideLowBattery {
            click.stageScreenshot(name: configuration.clickName, batteryLevel: 15)
        } else if scenario == .ridePressed {
            click.stageScreenshotPressedButton(.plus)
        }

        if scenario == .ready || scenario == .rideWaiting
            || scenario == .unparked {
            (coordinator.peripheral as? FTMSPeripheral)?
                .stageScreenshotAdvertising()
        } else if isRideScenario {
            (coordinator.peripheral as? FTMSPeripheral)?
                .stageScreenshotConnection()
        }
        if isRideScenario {
            coordinator.stageScreenshotRide(configuration: configuration)
        }
        if scenario == .failed {
            coordinator.stageScreenshotFailure("KICKR denied FTMS control")
        } else if scenario == .ridePending {
            coordinator.stageScreenshotPendingShift()
        } else if scenario == .rideReconnecting {
            kickr.stageScreenshot(
                name: configuration.kickrName,
                state: .connecting(name: configuration.kickrName)
            )
            coordinator.stageScreenshotReconnecting()
        } else if scenario == .rideStopping {
            coordinator.stageScreenshotStopping()
        } else if scenario == .rideWheelSize {
            coordinator.stageScreenshotRidingAppWheelSize()
        }
    }

    private var isRideScenario: Bool {
        switch scenario {
        case .ride, .rideAccessibility, .rideWaiting, .rideLowBattery,
             .ridePending, .ridePressed, .rideReconnecting, .rideStopping,
             .rideWheelSize:
            true
        default:
            false
        }
    }
}
#endif
