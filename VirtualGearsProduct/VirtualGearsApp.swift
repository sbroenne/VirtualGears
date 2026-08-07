import SwiftUI
import VirtualGearsCore

@main
struct VirtualGearsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurationStore = ConfigurationStore()
    @State private var kickr: KickrCentralService
    @State private var click: ClickCentralService
    @State private var headwind: HeadwindCentralService
    @State private var coordinator: ProxyCoordinator

    init() {
        let kickr = KickrCentralService()
        let click = ClickCentralService()
        let headwind = HeadwindCentralService()
        _kickr = State(initialValue: kickr)
        _click = State(initialValue: click)
        _headwind = State(initialValue: headwind)
        _coordinator = State(initialValue: ProxyCoordinator(
            kickr: kickr,
            click: click,
            peripheral: FTMSPeripheral(),
            screen: DeviceScreenWake()
        ))
    }

    var body: some Scene {
        WindowGroup {
            VirtualGearsHomeView(
                store: configurationStore,
                kickr: kickr,
                click: click,
                headwind: headwind,
                coordinator: coordinator
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
                guard phase == .active, !coordinator.isRidePresented else { return }
                kickr.autoConnectSavedDevice()
                if configurationStore.configuration.usesClick {
                    click.autoConnectSavedDevice()
                }
                if configurationStore.configuration.usesHeadwind {
                    headwind.autoConnectSavedDevice()
                }
                coordinator.resetInterruptedRideBaselineIfNeeded()
            }
        }
    }
}
