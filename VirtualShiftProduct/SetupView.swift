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
            fixedChainSection
            circumferenceSection
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
                    "Choose your actual trainer and, optionally, an original Zwift Click. "
                        + "Selections are saved and can reconnect after interruption."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var kickrSection: some View {
        Section {
            Button {
                kickr.isScanning ? kickr.stopScanning() : kickr.startScanning()
            } label: {
                HStack {
                    Label(
                        kickr.isScanning ? "Stop scanning" : "Scan for KICKR",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    Spacer()
                    Text(kickr.state.label)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 60)
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

            if store.configuration.hasValidKickr {
                savedDevice(
                    name: store.configuration.kickrName,
                    uuid: store.configuration.kickrUUID,
                    state: kickr.state.label
                )
                if kickr.selectedID?.uuidString == store.configuration.kickrUUID,
                   !kickr.isReady,
                   !kickr.isScanning {
                    Button("Reconnect saved KICKR") {
                        kickr.resumeSavedConnection()
                    }
                }
                bluetoothHelp(for: kickr.state)
            }
        } header: {
            Text("KICKR trainer")
        } footer: {
            Text("Required. The selected Core Bluetooth identity is stored on this iPhone.")
        }
    }

    private var clickSection: some View {
        Section {
            Toggle("Configure a Zwift Click", isOn: usesClick)
                .frame(minHeight: 60)

            if store.configuration.usesClick {
                Button {
                    click.isScanning ? click.stopScanning() : click.startScanning()
                } label: {
                    HStack {
                        Label(
                            click.isScanning ? "Stop scanning" : "Scan for Click",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        Spacer()
                        Text(click.state.label)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
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

                if !store.configuration.clickUUID.isEmpty {
                    savedDevice(
                        name: store.configuration.clickName,
                        uuid: store.configuration.clickUUID,
                        state: click.state.label
                    )
                    if click.selectedID?.uuidString == store.configuration.clickUUID,
                       !click.isReady,
                       !click.isScanning {
                        Button("Reconnect saved Click") {
                            click.resumeSavedConnection()
                        }
                    }
                    bluetoothHelp(for: click.state)
                }
            }
        } header: {
            Text("Shift controller")
        } footer: {
            Text("Optional. Only the original Zwift Click protocol is supported.")
        }
    }

    private var drivetrainSection: some View {
        Section("Drivetrain") {
            Picker("Preset", selection: drivetrainPreset) {
                ForEach(DrivetrainPreset.allCases) { preset in
                    VStack(alignment: .leading) {
                        Text(preset.name)
                        Text(preset.detail)
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.inline)

            Text(
                store.configuration.drivetrainPreset.setupDescription
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

        }
    }

    private var fixedChainSection: some View {
        Section {
            Label(
                "Choose a quiet, straight chain line and leave the physical "
                    + "chain there for the whole ride.",
                systemImage: "link"
            )
            .font(.callout.weight(.semibold))
        } header: {
            Text("Physical bike setup")
        } footer: {
            Text(
                "A Zwift Cog is already fixed. On a cassette, select one rear cog "
                    + "with a straight chain line. Tooth counts are not needed because "
                    + "this fixed position becomes the neutral reference."
            )
        }
    }

    private var circumferenceSection: some View {
        Section {
            TextField("Millimeters", value: circumference, format: .number)
                .keyboardType(.numberPad)
                .accessibilityLabel("Neutral wheel circumference in millimeters")

            if store.configuration.isCircumferenceConfirmed {
                Label(
                    "\(store.configuration.neutralCircumferenceMillimeters) mm confirmed",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .accessibilityLabel(
                    "Neutral circumference confirmed at "
                        + "\(store.configuration.neutralCircumferenceMillimeters) millimeters"
                )
            } else if !store.configuration.hasSafeCircumference {
                Label(
                    "This value is unsafe for the selected drivetrain.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            } else {
                Button {
                    store.confirmCircumference()
                } label: {
                    Text(
                        "Confirm \(store.configuration.neutralCircumferenceMillimeters) mm"
                    )
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Neutral circumference")
        } footer: {
            Text(
                "Default: 2070 mm. Every virtual gear must stay inside the "
                    + "physically verified 646.9–4800 mm KICKR range. Changing the "
                    + "drivetrain or this value requires confirmation again."
            )
        }
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
                : "Complete equipment, drivetrain, and circumference first"
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

    private var drivetrainPreset: Binding<DrivetrainPreset> {
        Binding {
            store.configuration.drivetrainPreset
        } set: {
            store.setDrivetrainPreset($0)
        }
    }

    private var circumference: Binding<Int> {
        Binding {
            store.configuration.neutralCircumferenceMillimeters
        } set: {
            store.setCircumference($0)
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
                    Text("\(candidate.rssi) dBm · \(candidate.id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(minHeight: 52)
        }
    }

    private func savedDevice(
        name: String,
        uuid: String,
        state: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(name, systemImage: "checkmark.circle")
                .font(.headline)
            Text(uuid)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(state)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
