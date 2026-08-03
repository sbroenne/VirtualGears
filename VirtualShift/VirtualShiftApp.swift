import SwiftUI

@main
struct VirtualShiftHardwareLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bluetooth = KickrBluetoothManager()
    @StateObject private var click = ClickBluetoothManager()
    @StateObject private var realVeloProbe = RealVeloProbeManager()
    @StateObject private var kickrFTMSProbe = KickrFTMSProbeManager()

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
                RealVeloProbeView()
                    .tabItem {
                        Label("RealVelo", systemImage: "antenna.radiowaves.left.and.right")
                    }
                KickrFTMSProbeView()
                    .tabItem {
                        Label("FTMS Lab", systemImage: "wave.3.right.circle")
                    }
            }
                .environmentObject(bluetooth)
                .environmentObject(click)
                .environmentObject(realVeloProbe)
                .environmentObject(kickrFTMSProbe)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                bluetooth.stop(reason: "App moved to the background")
                click.disconnect()
                kickrFTMSProbe.disconnect(reason: "App moved to the background")
            }
        }
    }
}
