import SwiftUI

struct VirtualShiftHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("VirtualShift", systemImage: "bicycle")
            } description: {
                Text(
                    "The product app is ready for the FTMS proxy work. "
                        + "Hardware investigations are kept in "
                        + "VirtualShift Hardware Lab."
                )
            }
            .navigationTitle("VirtualShift")
        }
    }
}
