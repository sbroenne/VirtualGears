import SwiftUI

struct VirtualShiftHomeView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        if store.configuration.setupComplete {
            ReadyView(store: store)
        } else {
            SetupView(store: store)
        }
    }
}

private struct ReadyView: View {
    @Bindable var store: ConfigurationStore
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    readinessHeader

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            equipmentCard
                            rideCard
                        }
                        VStack(spacing: 16) {
                            equipmentCard
                            rideCard
                        }
                    }

                    startRideButton
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("VirtualShift")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    .accessibilityHint("Review or change setup")
                }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SetupView(store: store, isEditing: true) {
                        showsSettings = false
                    }
                }
            }
        }
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup complete", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("Your ride setup is saved on this iPhone.")
                .font(.title.bold())
            Text("Bluetooth scanning and connections are not active yet. They come next.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var equipmentCard: some View {
        SummaryCard(title: "Equipment", systemImage: "bicycle") {
            SummaryRow(
                title: "KICKR",
                value: store.configuration.kickrName,
                detail: shortUUID(store.configuration.kickrUUID)
            )
            Divider()
            if store.configuration.usesClick {
                SummaryRow(
                    title: "Click",
                    value: store.configuration.clickName,
                    detail: shortUUID(store.configuration.clickUUID)
                )
            } else {
                SummaryRow(title: "Click", value: "Not configured", detail: "Optional")
            }
        }
    }

    private var rideCard: some View {
        SummaryCard(title: "Ride setup", systemImage: "gearshape.2") {
            SummaryRow(
                title: "Drivetrain",
                value: store.configuration.drivetrainPreset.name,
                detail: store.configuration.drivetrainPreset.detail
            )
            Divider()
            SummaryRow(
                title: "Neutral circumference",
                value: "\(store.configuration.neutralCircumferenceMillimeters) mm",
                detail: "Confirmed"
            )
        }
    }

    private var startRideButton: some View {
        Button {} label: {
            VStack(spacing: 4) {
                Label("Start Ride", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.title3.bold())
                Text("Bluetooth coming next")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true)
        .accessibilityLabel("Start Ride unavailable")
        .accessibilityHint("Bluetooth support is coming next")
    }

    private func shortUUID(_ uuid: String) -> String {
        "\(uuid.prefix(8))…"
    }
}

private struct SummaryCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("First run") {
    VirtualShiftHomeView(
        store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.firstRun")!)
    )
}
