import SwiftUI

struct SetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var diagnostics: ProductDiagnosticsStore
    var isEditing = false
    var onFinish: (() -> Void)?
    @State private var showsDiagnostics = false

    var body: some View {
        Form {
            introduction
            kickrSection
            clickSection
            drivetrainSection
            supportSection
        }
        .navigationTitle(isEditing ? "Settings" : "Set Up VirtualShift")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            finishButton
        }
        .interactiveDismissDisabled(isEditing && !store.configuration.setupComplete)
        .sheet(isPresented: $showsDiagnostics) {
            NavigationStack {
                DiagnosticsView(
                    diagnostics: diagnostics,
                    kickr: kickr,
                    click: click
                )
            }
        }
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "bicycle.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(isEditing ? "Ride setup" : "Let’s prepare your ride")
                    .font(.title2.bold())
                Text(
                    "Connect your KICKR and original Zwift Click, then choose how "
                        + "you want the virtual gears to feel."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var kickrSection: some View {
        Section {
            if store.configuration.hasValidKickr {
                equipmentCard(
                    name: store.configuration.kickrName,
                    state: kickr.state.label,
                    symbol: "bicycle",
                    connected: kickr.isReady
                )
                if !kickr.isReady, !kickr.isScanning {
                    Button("Connect saved KICKR") {
                        kickr.resumeSavedConnection()
                    }
                }
            }

            Button {
                kickr.isScanning ? kickr.stopScanning() : kickr.startScanning()
            } label: {
                Label(
                    kickr.isScanning
                        ? "Stop looking"
                        : (store.configuration.hasValidKickr
                            ? "Choose a different KICKR" : "Find my KICKR"),
                    systemImage: kickr.isScanning
                        ? "stop.circle" : "antenna.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)

            if kickr.isScanning, kickr.candidates.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for nearby KICKR trainers…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(kickr.candidates) { candidate in
                candidateButton(candidate, selected: candidate.id.uuidString
                    == store.configuration.kickrUUID) {
                    store.configuration.kickrName = candidate.name
                    store.configuration.kickrUUID = candidate.id.uuidString
                    store.configuration.setupComplete = false
                    kickr.selectAndConnect(candidate.id)
                }
            }

            bluetoothHelp(for: kickr.state)
        } header: {
            Text("1. Trainer")
        } footer: {
            Text(
                "Select the KICKR physically attached to your bike. VirtualShift "
                    + "remembers it for future rides."
            )
        }
    }

    private var clickSection: some View {
        Section {
            Toggle("Use Zwift Click", isOn: usesClick)
                .frame(minHeight: 60)

            if store.configuration.usesClick {
                if !store.configuration.clickUUID.isEmpty {
                    equipmentCard(
                        name: store.configuration.clickName,
                        state: click.state.label,
                        symbol: "button.programmable",
                        connected: click.isReady
                    )
                    if !click.isReady, !click.isScanning {
                        Button("Connect saved Click") {
                            click.resumeSavedConnection()
                        }
                    }
                }

                Button {
                    click.isScanning ? click.stopScanning() : click.startScanning()
                } label: {
                    Label(
                        click.isScanning ? "Stop looking" : "Find my Click",
                        systemImage: click.isScanning
                            ? "stop.circle" : "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)

                if click.candidates.isEmpty {
                    Label(
                        "Nothing showing? Press either Click button once to wake "
                            + "it, then try again.",
                        systemImage: "hand.tap.fill"
                    )
                    .foregroundStyle(.secondary)
                }

                ForEach(click.candidates) { candidate in
                    candidateButton(candidate, selected: candidate.id.uuidString
                        == store.configuration.clickUUID) {
                        store.configuration.clickName = candidate.name
                        store.configuration.clickUUID = candidate.id.uuidString
                        store.configuration.setupComplete = false
                        click.selectAndConnect(candidate.id)
                    }
                }

                bluetoothHelp(for: click.state)
            } else {
                Text("Large on-screen shift buttons will be available during the ride.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("2. Shift controller")
        } footer: {
            Text(
                "Enabled by default. Turn this off only if you want to use "
                    + "on-screen shifting."
            )
        }
    }

    private var drivetrainSection: some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(DrivetrainPreset.allCases) { preset in
                        drivetrainCard(preset)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)

            Label(
                "On the bike, choose one quiet, straight chain position and "
                    + "leave it there. No tooth counts or physical gearing setup "
                    + "are needed.",
                systemImage: "link"
            )
            .font(.callout.weight(.semibold))

            if !store.configuration.hasSafeCircumference {
                Label(
                    "This preset cannot use the trainer's verified safe range.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        } header: {
            Text("3. Virtual drivetrain")
        } footer: {
            Text(store.configuration.drivetrainPreset.setupDescription)
        }
    }

    private func drivetrainCard(_ preset: DrivetrainPreset) -> some View {
        let selected = store.configuration.drivetrainPreset == preset
        return Button {
            store.setDrivetrainPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(preset.category, systemImage: preset.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(preset.detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(preset.drivetrain.gears.count) sequential gears")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 250, height: 150, alignment: .topLeading)
            .background(
                selected
                    ? Color.accentColor.opacity(0.12)
                    : Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        selected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: selected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(preset.name), \(preset.detail), "
                + "\(preset.drivetrain.gears.count) gears"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var supportSection: some View {
        Section("Support") {
            Button {
                showsDiagnostics = true
            } label: {
                Label("Diagnostics & App Information", systemImage: "stethoscope")
                    .frame(minHeight: 52)
            }
            Text(
                "Setup remains saved if you leave this screen. Finish Setup is enabled "
                    + "only after the selected devices have completed a real connection."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var finishButton: some View {
        Button {
            guard canFinishSetup else { return }
            store.finishSetup()
            onFinish?()
        } label: {
            Text(isEditing ? "Save Setup" : "Finish Setup")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canFinishSetup)
        .padding()
        .background(.bar)
        .accessibilityHint(
            canFinishSetup
                ? "Saves setup and shows the ready screen"
                : "Connect the selected equipment and choose a drivetrain first"
        )
    }

    private var usesClick: Binding<Bool> {
        Binding {
            store.configuration.usesClick
        } set: {
            store.configuration.usesClick = $0
            if !$0 {
                click.forgetSelection()
                store.configuration.clickName = ""
                store.configuration.clickUUID = ""
            }
        }
    }

    private var canFinishSetup: Bool {
        store.configuration.canFinishSetup
            && kickr.isReady
            && kickr.selectedID?.uuidString == store.configuration.kickrUUID
            && (!store.configuration.usesClick
                || (click.isReady
                    && click.selectedID?.uuidString
                        == store.configuration.clickUUID))
    }

    private func candidateButton(
        _ candidate: BluetoothCandidate,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(candidate.name)
                        .font(.headline)
                    Text("Nearby device · signal \(candidate.rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 52)
        }
    }

    private func equipmentCard(
        name: String,
        state: String,
        symbol: String,
        connected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(connected ? .green : .secondary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(connected ? .green : .secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func bluetoothHelp(for state: ProductConnectionState) -> some View {
        switch state {
        case let .unavailable(reason), let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Bluetooth issue: \(reason)")
            if reason.localizedCaseInsensitiveContains("permission")
                || reason.localizedCaseInsensitiveContains("unauthorized") {
                Button("Open Bluetooth Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        default:
            EmptyView()
        }
    }
}

#Preview("Setup") {
    let diagnostics = ProductDiagnosticsStore()
    NavigationStack {
        SetupView(
            store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.setup")!),
            kickr: KickrCentralService(diagnostics: diagnostics),
            click: ClickCentralService(diagnostics: diagnostics),
            diagnostics: diagnostics
        )
    }
}
