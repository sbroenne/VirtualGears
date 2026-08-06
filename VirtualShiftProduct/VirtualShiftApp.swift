import SwiftUI
import VirtualShiftCore

@main
struct VirtualShiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurationStore = ConfigurationStore()
    @State private var diagnostics: ProductDiagnosticsStore
    @State private var kickr: KickrCentralService
    @State private var click: ClickCentralService
    @State private var headwind: HeadwindCentralService
    @State private var coordinator: ProxyCoordinator

    init() {
        let diagnostics = ProductDiagnosticsStore()
        _diagnostics = State(initialValue: diagnostics)
        let kickr = KickrCentralService(diagnostics: diagnostics)
        let click = ClickCentralService(diagnostics: diagnostics)
        let headwind = HeadwindCentralService(diagnostics: diagnostics)
        _kickr = State(initialValue: kickr)
        _click = State(initialValue: click)
        _headwind = State(initialValue: headwind)
        _coordinator = State(initialValue: ProxyCoordinator(
            kickr: kickr,
            click: click,
            peripheral: FTMSPeripheral(diagnostics: diagnostics),
            screen: DeviceScreenWake(),
            diagnostics: diagnostics
        ))
    }

    var body: some Scene {
        WindowGroup {
            VirtualShiftHomeView(
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
                coordinator.restoreInterruptedRideIfNeeded()
            }
        }
    }
}
