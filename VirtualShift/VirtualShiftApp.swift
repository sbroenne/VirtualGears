import SwiftUI

@main
struct VirtualShiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bluetooth = KickrBluetoothManager()
    @StateObject private var click = ClickBluetoothManager()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("KICKR", systemImage: "bicycle")
                    }
                ClickProofView()
                    .tabItem {
                        Label("Click", systemImage: "button.programmable")
                    }
            }
                .environmentObject(bluetooth)
                .environmentObject(click)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                bluetooth.stop(reason: "App moved to the background")
                click.disconnect()
            }
        }
    }
}
