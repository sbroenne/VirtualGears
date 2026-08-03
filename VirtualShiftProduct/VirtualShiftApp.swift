import SwiftUI

@main
struct VirtualShiftApp: App {
    @State private var configurationStore = ConfigurationStore()

    var body: some Scene {
        WindowGroup {
            VirtualShiftHomeView(store: configurationStore)
        }
    }
}
