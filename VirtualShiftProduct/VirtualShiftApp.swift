import SwiftUI
import UIKit

@main
struct VirtualShiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurationStore = ConfigurationStore()
    @State private var diagnostics: ProductDiagnosticsStore
    @State private var kickr: KickrCentralService
    @State private var click: ClickCentralService
    @State private var coordinator: ProxyCoordinator

    init() {
        let diagnostics = ProductDiagnosticsStore()
        _diagnostics = State(initialValue: diagnostics)
        let kickr = KickrCentralService(diagnostics: diagnostics)
        let click = ClickCentralService(diagnostics: diagnostics)
        _kickr = State(initialValue: kickr)
        _click = State(initialValue: click)
        _coordinator = State(initialValue: ProxyCoordinator(
            kickr: kickr,
            click: click,
            diagnostics: diagnostics
        ))
    }

    var body: some Scene {
        WindowGroup {
            VirtualShiftHomeView(
                store: configurationStore,
                kickr: kickr,
                click: click,
                coordinator: coordinator
            )
            .onChange(of: configurationStore.configuration.setupComplete) {
                if !configurationStore.configuration.setupComplete {
                    Task { await coordinator.stopRide() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !coordinator.isRidePresented {
                    kickr.autoConnectSavedDevice()
                    if configurationStore.configuration.usesClick {
                        click.autoConnectSavedDevice()
                    }
                }
                guard phase == .background, coordinator.isRidePresented else { return }
                let task = UIApplication.shared.beginBackgroundTask(
                    withName: "Restore KICKR"
                )
                Task { @MainActor in
                    await coordinator.stopRide()
                    if task != .invalid {
                        UIApplication.shared.endBackgroundTask(task)
                    }
                }
            }
        }
    }
}
