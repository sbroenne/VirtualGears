import SwiftUI
import VirtualShiftCore

/// Setup follows the ordinary iOS Settings pattern: a short list of rows that
/// each show their current value and push to a screen where it can be changed.
/// The disclosure arrow is what tells a rider a row can be tapped, so nothing
/// here relies on a custom affordance they would have to learn.
struct SetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    var onFinish: (() -> Void)?

    var body: some View {
        Form {
            equipmentSection
            gearsSection
            chainLineSection
        }
        .navigationTitle("Settings")
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
    }

    private var equipmentSection: some View {
        Section {
            NavigationLink {
                TrainerSetupView(store: store, kickr: kickr)
            } label: {
                SetupRow(
                    title: "Trainer",
                    value: store.configuration.hasValidKickr
                        ? store.configuration.kickrName : "None yet",
                    status: .init(state: kickr.state, isRequired: true)
                )
            }

            NavigationLink {
                ShiftingSetupView(store: store, click: click)
            } label: {
                SetupRow(
                    title: "Zwift Click",
                    value: shiftingValue,
                    status: store.configuration.usesClick
                        ? .init(state: click.state, isRequired: false)
                        : .satisfied
                )
            }
        } header: {
            Text("Your equipment")
        } footer: {
            Text(
                "VirtualShift finds these by itself and reconnects to them "
                    + "every time you ride. Change them here only if it picked "
                    + "the wrong one."
            )
        }
    }

    private var shiftingValue: String {
        let name = store.configuration.clickName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Not added" : name
    }

    private var gearsSection: some View {
        Section {
            NavigationLink {
                GearChoiceView(store: store)
            } label: {
                LabeledContent(
                    "Gears",
                    value: store.configuration.drivetrainName
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
            Text(store.configuration.setupDescription)
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

    private var finishButton: some View {
        VStack(spacing: 8) {
            if let blocker = remainingStep {
                Text(blocker)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onFinish?()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }

    /// Nothing here is a gate, so this says what is currently true rather than
    /// what the rider must go and do. The gears row raises its own problem, so
    /// only the trainer is mentioned here.
    private var remainingStep: String? {
        guard !store.configuration.hasValidKickr || !kickr.isReady else {
            return nil
        }
        return "Your trainer is not connected, so a ride cannot start yet."
    }

    private func autoConnectSavedEquipment() {
        kickr.autoConnectSavedDevice()
        if store.configuration.usesClick {
            click.autoConnectSavedDevice()
        }
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
                        wakeInstruction: WakeInstruction.trainer
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

/// Shifting always works from the two on-screen buttons, so this screen is not
/// a choice between two ways of shifting. It exists only to add a Zwift Click
/// for anyone who owns one.
private struct ShiftingSetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var click: ClickCentralService

    var body: some View {
        Form {
            Section {
                Label(
                    "The two large buttons on the ride screen always shift, "
                        + "whatever else is connected.",
                    systemImage: "hand.tap.fill"
                )
                .font(.callout)
            } header: {
                Text("On-screen buttons")
            }

            if store.configuration.usesClick {
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
                        wakeInstruction: WakeInstruction.click
                    )
                    Button(role: .destructive) {
                        click.forgetSelection()
                        store.configuration.clickName = ""
                        store.configuration.clickUUID = ""
                    } label: {
                        Text("Stop using this Click")
                    }
                } header: {
                    Text("Your Click")
                } footer: {
                    Text(
                        "You can still shift on screen if the Click is asleep "
                            + "or out of battery."
                    )
                }
            }

            Section {
                Button {
                    click.isScanning ? click.stopScanning() : click.startScanning()
                } label: {
                    Label(
                        click.isScanning
                            ? "Stop looking"
                            : (store.configuration.usesClick
                                ? "Choose a different Click" : "Find my Click"),
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
                        click.selectAndConnect(candidate.id)
                    }
                }

                BluetoothHelp(state: click.state)
            } header: {
                Text(
                    store.configuration.usesClick
                        ? "Change your Click" : "Add a Zwift Click"
                )
            } footer: {
                Text(
                    store.configuration.usesClick
                        ? WakeInstruction.click
                        : "Optional. If you have an original Zwift Click on your "
                            + "handlebar, add it here to shift without reaching "
                            + "for the screen."
                )
            }
        }
        .navigationTitle("Zwift Click")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.configuration.usesClick {
                click.autoConnectSavedDevice()
            } else {
                click.startScanning()
            }
        }
        .onDisappear { click.stopScanning() }
    }
}

// MARK: - Gears

/// Gears are described the way a bike shop describes them: which chainrings are
/// on the front, and which cassette is on the back. A rider can copy the numbers
/// stamped on their own bike, or invent a bike they would rather be riding.
private struct GearChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            Section {
                Picker("Gears", selection: $store.configuration.usesVirtualGears) {
                    Text("Virtual gears").tag(true)
                    Text("Copy a real bike").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(
                    store.configuration.usesVirtualGears
                        ? "The same 24 virtual gears Zwift and Wahoo use. They "
                            + "belong to no particular bike and suit everything "
                            + "from a standing start to a sprint."
                        : "Copy the numbers printed on your own bike, or pick "
                            + "any combination you would like to ride. It does "
                            + "not have to be a set that anyone sells."
                )
            }

            if !store.configuration.usesVirtualGears {
                Section {
                    NavigationLink {
                        ChainringChoiceView(store: store)
                    } label: {
                        LabeledContent(
                            "Chainrings",
                            value: store.configuration.chainring.name
                        )
                    }

                    NavigationLink {
                        CassetteChoiceView(store: store)
                    } label: {
                        LabeledContent(
                            "Cassette",
                            value: store.configuration.cassette.name
                        )
                    }
                } header: {
                    Text("The bike you want to feel")
                }
            }

            Section {
                GearPreview(configuration: store.configuration)
            } header: {
                Text("What you get")
            }
        }
        .navigationTitle("Gears")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The result of the two choices above, kept on the same screen so a change is
/// seen immediately rather than discovered mid-ride.
private struct GearPreview: View {
    let configuration: AppConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let drivetrain = configuration.drivetrain {
                Text("\(drivetrain.gears.count) gears")
                    .font(.title2.weight(.semibold))
                Text(configuration.setupDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !configuration.usesVirtualGears,
                   drivetrain.gears.count < expectedCombinations {
                    Text(
                        "Fewer than the \(expectedCombinations) possible "
                            + "pairings, because the ones that would cross the "
                            + "chain badly are left out, along with any that "
                            + "feel exactly like another."
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            } else {
                Label(
                    "Too wide for the trainer",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                Text(configuration.setupDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var expectedCombinations: Int {
        configuration.chainring.teeth.count * configuration.cassette.cogs.count
    }
}

private struct ChainringChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.title) { group in
                Section {
                    ForEach(options(count: group.count)) { option in
                        ChoiceRow(
                            title: option.name,
                            note: option.note,
                            detail: nil,
                            selected: option.id == store.configuration.chainringID,
                            fits: fits(option)
                        ) {
                            store.setChainring(option)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text(group.note)
                }
            }
        }
        .navigationTitle("Chainrings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let groups: [(title: String, count: Int, note: String)] = [
        (
            "One chainring",
            1,
            "A single ring. Simple, and every gear is a different one."
        ),
        (
            "Two chainrings",
            2,
            "The usual road setup. More gears, but some of them repeat."
        ),
        (
            "Three chainrings",
            3,
            "Older bikes. A very wide spread, so it will not fit every cassette."
        ),
    ]

    private func options(count: Int) -> [ChainringOption] {
        DrivetrainCatalog.chainrings.filter { $0.teeth.count == count }
    }

    private func fits(_ option: ChainringOption) -> Bool {
        (try? Drivetrain.build(
            chainrings: option.teeth,
            cassetteCogs: store.configuration.cassette.cogs
        )) != nil
    }
}

private struct CassetteChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            ForEach(speedCounts, id: \.self) { speeds in
                Section {
                    ForEach(options(speeds: speeds)) { option in
                        ChoiceRow(
                            title: option.name,
                            note: option.note,
                            detail: option.cogs.map(String.init)
                                .joined(separator: ", "),
                            selected: option.id == store.configuration.cassetteID,
                            fits: fits(option)
                        ) {
                            store.setCassette(option)
                        }
                    }
                } header: {
                    Text("\(speeds) cogs")
                }
            }
        }
        .navigationTitle("Cassette")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var speedCounts: [Int] {
        Array(Set(DrivetrainCatalog.cassettes.map(\.speeds))).sorted()
    }

    private func options(speeds: Int) -> [CassetteOption] {
        DrivetrainCatalog.cassettes.filter { $0.speeds == speeds }
    }

    private func fits(_ option: CassetteOption) -> Bool {
        (try? Drivetrain.build(
            chainrings: store.configuration.chainring.teeth,
            cassetteCogs: option.cogs
        )) != nil
    }
}

/// One selectable part. A part that cannot work with the other choice is shown
/// dimmed and says why, rather than disappearing and leaving the rider guessing.
private struct ChoiceRow: View {
    let title: String
    let note: String
    let detail: String?
    let selected: Bool
    let fits: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(fits ? note : "Too wide to combine with your other choice")
                        .font(.subheadline)
                        .foregroundStyle(fits ? .secondary : Color.red)
                    if let detail, fits {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
        .disabled(!fits)
        .opacity(fits ? 1 : 0.5)
        .accessibilityLabel(
            fits
                ? "\(title), \(note)"
                : "\(title), too wide to combine with your other choice"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            click: ClickCentralService(diagnostics: diagnostics)
        )
    }
}
