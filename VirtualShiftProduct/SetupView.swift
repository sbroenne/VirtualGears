import SwiftUI

/// Setup follows the ordinary iOS Settings pattern: a short list of rows that
/// each show their current value and push to a screen where it can be changed.
/// The disclosure arrow is what tells a rider a row can be tapped, so nothing
/// here relies on a custom affordance they would have to learn.
struct SetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var diagnostics: ProductDiagnosticsStore
    var isEditing = false
    var onFinish: (() -> Void)?
    var onStartRide: (() -> Void)?

    var body: some View {
        Form {
            if !isEditing {
                welcomeSection
            }
            equipmentSection
            gearsSection
            chainLineSection
            supportSection
        }
        .navigationTitle(isEditing ? "Settings" : "Set Up VirtualShift")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            autoConnectSavedEquipment()
        }
        .onChange(of: store.configuration.usesClick) { _, enabled in
            if enabled { click.autoConnectSavedDevice() }
        }
        .safeAreaInset(edge: .bottom) {
            finishButton
        }
        .interactiveDismissDisabled(isEditing && !store.configuration.setupComplete)
    }

    private var welcomeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Three things to set up")
                    .font(.headline)
                Text(
                    "Connect your trainer, choose how you want to shift, and pick "
                        + "your gears. VirtualShift remembers all of it for next time."
                )
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var equipmentSection: some View {
        Section {
            NavigationLink {
                TrainerSetupView(store: store, kickr: kickr)
            } label: {
                SetupRow(
                    title: "Trainer",
                    value: store.configuration.hasValidKickr
                        ? store.configuration.kickrName : "Not set up",
                    status: .init(state: kickr.state, isRequired: true)
                )
            }

            NavigationLink {
                ShiftingSetupView(store: store, click: click)
            } label: {
                SetupRow(
                    title: "Shifting",
                    value: shiftingValue,
                    status: store.configuration.usesClick
                        ? .init(state: click.state, isRequired: true)
                        : .satisfied
                )
            }
        } header: {
            Text("Your equipment")
        } footer: {
            Text(
                "VirtualShift connects to these itself, and reconnects "
                    + "automatically every time you ride."
            )
        }
    }

    private var shiftingValue: String {
        guard store.configuration.usesClick else { return "On-screen buttons" }
        let name = store.configuration.clickName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Not set up" : name
    }

    private var gearsSection: some View {
        Section {
            NavigationLink {
                GearChoiceView(store: store)
            } label: {
                LabeledContent(
                    "Gears",
                    value: store.configuration.drivetrainPreset.name
                )
            }

            if !store.configuration.hasSafeCircumference {
                Label(
                    "These gears fall outside the trainer's safe range. Choose "
                        + "another set.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        } footer: {
            Text(store.configuration.drivetrainPreset.setupDescription)
        }
    }
    private var chainLineSection: some View {
        Section {
            Label(
                "Put your chain in one quiet, straight position and leave it "
                    + "there. VirtualShift does all the shifting from now on.",
                systemImage: "link"
            )
            .font(.callout)
        } header: {
            Text("On the bike")
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                DiagnosticsView(diagnostics: diagnostics, kickr: kickr, click: click)
            } label: {
                Label("Diagnostics & app info", systemImage: "stethoscope")
            }
        } footer: {
            Text(
                "Your setup stays saved if you leave this screen. Start Ride "
                    + "turns on once your equipment is really connected."
            )
        }
    }

    private var finishButton: some View {
        VStack(spacing: 8) {
            if !canFinishSetup, let blocker = remainingStep {
                Text(blocker)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                guard canFinishSetup else { return }
                store.finishSetup()
                if isEditing {
                    onFinish?()
                } else {
                    onStartRide?()
                }
            } label: {
                Text(isEditing ? "Save Setup" : "Start Ride")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canFinishSetup)
        }
        .padding()
        .background(.bar)
    }

    /// Says which single thing is still missing, so a disabled button is never
    /// a dead end.
    private var remainingStep: String? {
        if !store.configuration.hasValidKickr || !kickr.isReady {
            return "Connect your trainer to continue."
        }
        if store.configuration.usesClick, !click.isReady {
            return "Connect your Click to continue."
        }
        if !store.configuration.hasSafeCircumference {
            return "Choose a different set of gears to continue."
        }
        return nil
    }

    private func autoConnectSavedEquipment() {
        kickr.autoConnectSavedDevice()
        if store.configuration.usesClick {
            click.autoConnectSavedDevice()
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
}

// MARK: - Trainer

private struct TrainerSetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService

    var body: some View {
        Form {
            if store.configuration.hasValidKickr {
                Section {
                    EquipmentSummary(
                        name: store.configuration.kickrName,
                        state: kickr.state.label,
                        symbol: "bicycle",
                        connected: kickr.isReady
                    )
                    ConnectionAdvice(
                        isReady: kickr.isReady,
                        isScanning: kickr.isScanning,
                        isConnecting: kickr.state.isConnectionInProgress,
                        isStalled: kickr.connectionIsStalled,
                        hasSavedDevice: kickr.hasSavedDevice,
                        wakeInstruction: WakeInstruction.trainer,
                        retry: { kickr.autoConnectSavedDevice() }
                    )
                }
            }

            Section {
                Button {
                    kickr.isScanning ? kickr.stopScanning() : kickr.startScanning()
                } label: {
                    Label(
                        kickr.isScanning
                            ? "Stop looking"
                            : (store.configuration.hasValidKickr
                                ? "Choose a different trainer" : "Find my trainer"),
                        systemImage: kickr.isScanning
                            ? "stop.circle" : "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                if kickr.isScanning, kickr.candidates.isEmpty {
                    SearchingRow(message: "Looking for nearby trainers…")
                }

                ForEach(kickr.candidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        selected: candidate.id.uuidString
                            == store.configuration.kickrUUID
                    ) {
                        store.configuration.kickrName = candidate.name
                        store.configuration.kickrUUID = candidate.id.uuidString
                        store.configuration.setupComplete = false
                        kickr.selectAndConnect(candidate.id)
                    }
                }

                BluetoothHelp(state: kickr.state)
            } footer: {
                Text(
                    "Pick the trainer your bike is actually on. \(Self.wakeInstruction)"
                )
            }
        }
        .navigationTitle("Trainer")
        .navigationBarTitleDisplayMode(.inline)
        .task { kickr.autoConnectSavedDevice() }
    }

    private static let wakeInstruction =
        "If it does not show up, turn it on and give the pedals half a turn to "
            + "wake it up."
}

// MARK: - Shifting

private struct ShiftingSetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var click: ClickCentralService

    var body: some View {
        Form {
            Section {
                Picker("How you shift", selection: usesClick) {
                    Text("Zwift Click").tag(true)
                    Text("On-screen buttons").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(
                    store.configuration.usesClick
                        ? "Shift with the physical buttons on your handlebar. The "
                            + "on-screen buttons keep working too."
                        : "Shift with the two large buttons on the ride screen."
                )
            }

            if store.configuration.usesClick {
                if !store.configuration.clickUUID.isEmpty {
                    Section {
                        EquipmentSummary(
                            name: store.configuration.clickName,
                            state: click.state.label,
                            symbol: "button.programmable",
                            connected: click.isReady
                        )
                        ConnectionAdvice(
                            isReady: click.isReady,
                            isScanning: click.isScanning,
                            isConnecting: click.state.isConnectionInProgress,
                            isStalled: click.connectionIsStalled,
                            hasSavedDevice: click.hasSavedDevice,
                            wakeInstruction: WakeInstruction.click,
                            retry: { click.autoConnectSavedDevice() }
                        )
                    }
                }

                Section {
                    Button {
                        click.isScanning ? click.stopScanning() : click.startScanning()
                    } label: {
                        Label(
                            click.isScanning ? "Stop looking" : "Find my Click",
                            systemImage: click.isScanning
                                ? "stop.circle" : "antenna.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)

                    if click.isScanning, click.candidates.isEmpty {
                        SearchingRow(message: "Looking for a nearby Click…")
                    }

                    ForEach(click.candidates) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            selected: candidate.id.uuidString
                                == store.configuration.clickUUID
                        ) {
                            store.configuration.clickName = candidate.name
                            store.configuration.clickUUID = candidate.id.uuidString
                            store.configuration.setupComplete = false
                            click.selectAndConnect(candidate.id)
                        }
                    }

                    BluetoothHelp(state: click.state)
                } footer: {
                    Text(WakeInstruction.click)
                }
            }
        }
        .navigationTitle("Shifting")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.configuration.usesClick { click.autoConnectSavedDevice() }
        }
    }

    private var usesClick: Binding<Bool> {
        Binding {
            store.configuration.usesClick
        } set: {
            store.configuration.usesClick = $0
            if $0 {
                click.autoConnectSavedDevice()
            } else {
                click.forgetSelection()
                store.configuration.clickName = ""
                store.configuration.clickUUID = ""
            }
        }
    }
}

// MARK: - Gears

private struct GearChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            ForEach(Self.categories, id: \.self) { category in
                Section {
                    ForEach(presets(in: category)) { preset in
                        gearRow(preset)
                    }
                } header: {
                    Text(category)
                } footer: {
                    if let note = Self.categoryNote[category] {
                        Text(note)
                    }
                }
            }
        }
        .navigationTitle("Gears")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gearRow(_ preset: DrivetrainPreset) -> some View {
        let selected = store.configuration.drivetrainPreset == preset
        return Button {
            store.setDrivetrainPreset(preset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(preset.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(preset.specification)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(.rect)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name), \(preset.summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static let categories = ["Virtual", "Road", "Gravel", "Mountain", "Simple"]

    private static let categoryNote = [
        "Virtual": "Start here if you are not copying a real bike.",
        "Simple": "Fewer gears, so each shift makes a bigger difference.",
    ]

    private func presets(in category: String) -> [DrivetrainPreset] {
        DrivetrainPreset.allCases.filter { $0.category == category }
    }
}

// MARK: - Shared rows

/// A Settings-style row: what it is on the left, what it is set to on the
/// right, and a badge saying whether it is actually connected.
private struct SetupRow: View {
    enum Status {
        case satisfied
        case working
        case attention

        init(state: ProductConnectionState, isRequired: Bool) {
            switch state {
            case .ready: self = .satisfied
            case _ where state.isConnectionInProgress || state == .scanning:
                self = .working
            default: self = isRequired ? .attention : .satisfied
            }
        }
    }

    let title: String
    let value: String
    let status: Status

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                badge
            }
        } label: {
            Text(title)
        }
        .accessibilityLabel("\(title), \(value), \(accessibilityStatus)")
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .satisfied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .working:
            ProgressView().controlSize(.small)
        case .attention:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private var accessibilityStatus: String {
        switch status {
        case .satisfied: "connected"
        case .working: "connecting"
        case .attention: "needs attention"
        }
    }
}

/// The only place that explains a stalled connection. CoreBluetooth will happily
/// wait forever for a sleeping device, so silence here reads as a hang.
private struct ConnectionAdvice: View {
    let isReady: Bool
    let isScanning: Bool
    let isConnecting: Bool
    let isStalled: Bool
    let hasSavedDevice: Bool
    let wakeInstruction: String
    let retry: () -> Void

    var body: some View {
        if isReady || isScanning || !hasSavedDevice {
            EmptyView()
        } else if isConnecting, !isStalled {
            SearchingRow(message: "Connecting…")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(isStalled ? "Still trying to connect" : "Not connected")
                        .font(.headline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(wakeInstruction)
                    .foregroundStyle(.secondary)
                Button("Try again now", action: retry)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SearchingRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CandidateRow: View {
    let candidate: BluetoothCandidate
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(signalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(selected ? Color.green : Color.secondary)
            }
            .contentShape(.rect)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.name), \(signalDescription)")
    }

    /// Riders do not read dBm; they want to know whether it is the device in
    /// front of them.
    private var signalDescription: String {
        switch candidate.rssi {
        case (-55)...: "Very close by"
        case (-70)..<(-55): "Nearby"
        default: "Further away"
        }
    }
}

private struct BluetoothHelp: View {
    let state: ProductConnectionState

    var body: some View {
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

private struct EquipmentSummary: View {
    let name: String
    let state: String
    let symbol: String
    let connected: Bool

    var body: some View {
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
