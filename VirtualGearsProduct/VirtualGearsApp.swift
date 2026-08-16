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
    case startingAccessibility = "-shotStartingAccessibility"
    case ready = "-shotReady"
    case readyAccessibility = "-shotReadyAccessibility"
    case failed = "-shotFailed"
    case ride = "-shotRide"
    case rideAccessibility = "-shotRideAccessibility"
    case rideWaiting = "-shotRideWaiting"
    case rideLowBattery = "-shotRideLowBattery"
    case ridePending = "-shotRidePending"
    case ridePressed = "-shotRidePressed"
    case rideReconnecting = "-shotRideReconnecting"
    case settings = "-shotSettings"
    case gears = "-shotGears"
    case realGears = "-shotRealGears"
    case headwind = "-shotHeadwind"
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
            case .starting, .startingAccessibility, .ready,
                 .readyAccessibility, .failed:
                StartupView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    coordinator: coordinator,
                    beginsDiscovery: false
                )
            case .ride, .rideAccessibility, .rideWaiting, .rideLowBattery,
                 .ridePending, .ridePressed, .rideReconnecting:
                ShiftingView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    coordinator: coordinator,
                    onRiderStop: {}
                )
            case .settings:
                NavigationStack {
                    SetupView(
                        store: store,
                        kickr: kickr,
                        click: click,
                        headwind: headwind,
                        autoConnectsOnAppear: false
                    )
                }
            case .gears, .realGears:
                NavigationStack {
                    GearChoiceView(store: store)
                }
            case .headwind:
                NavigationStack {
                    HeadwindControlView(headwind: headwind)
                }
            case .demo:
                DemoModeView(onExit: {})
            }
        }
        .dynamicTypeSize(
            scenario == .rideAccessibility
                || scenario == .startingAccessibility
                || scenario == .readyAccessibility
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
        configuration.rememberKickr(
            named: "Wahoo KICKR 2A93",
            id: ScreenshotFixture.kickrID
        )
        configuration.rememberClick(
            named: "Zwift Click",
            id: ScreenshotFixture.clickID
        )
        configuration.rememberHeadwind(
            named: "KICKR HEADWIND 4D21",
            id: ScreenshotFixture.headwindID
        )
        configuration.usesVirtualGears = scenario != .realGears
        store.configuration = configuration

        kickr.stageScreenshot(
            name: configuration.kickrName,
            state: scenario == .starting || scenario == .startingAccessibility
                ? .connecting(name: configuration.kickrName) : .ready
        )
        click.stageScreenshot(name: configuration.clickName, batteryLevel: 82)
        headwind.stageScreenshot(
            name: configuration.headwindName ?? "KICKR HEADWIND",
            speed: 50
        )

        if scenario == .rideLowBattery {
            click.stageScreenshot(name: configuration.clickName, batteryLevel: 15)
        } else if scenario == .ridePressed {
            click.stageScreenshotPressedButton(.plus)
        }

        if scenario == .ready || scenario == .readyAccessibility
            || scenario == .rideWaiting {
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
        }
    }

    private var isRideScenario: Bool {
        switch scenario {
        case .ride, .rideAccessibility, .rideWaiting, .rideLowBattery,
             .ridePending, .ridePressed, .rideReconnecting:
            true
        default:
            false
        }
    }
}
#endif
