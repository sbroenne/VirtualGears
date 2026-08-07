import SwiftUI
import VirtualGearsCore

/// Setup follows the ordinary iOS Settings pattern: a short list of rows that
/// each show their current value and push to a screen where it can be changed.
/// The disclosure arrow is what tells a rider a row can be tapped, so nothing
/// here relies on a custom affordance they would have to learn.
struct SetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var headwind: HeadwindCentralService
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
        .onChange(of: store.configuration.usesHeadwind) { _, enabled in
            if enabled { headwind.autoConnectSavedDevice() }
        }
        .toolbar {
            // A sheet is dismissed from its own navigation bar, which is where
            // iOS has trained everyone to look. Every change here saves the
            // moment it is made, so this confirms nothing and only closes.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onFinish?() }
                    .fontWeight(.semibold)
            }
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
                        ? store.configuration.kickrName : nil,
                    status: EquipmentDisplayState(
                        isConfigured: store.configuration.hasValidKickr,
                        connectionState: kickr.state,
                        isRequired: true
                    ),
                    isRequired: true
                )
            }

            if !store.configuration.hasValidKickr || !kickr.isReady {
                Label(
                    "Your trainer is not connected, so a ride cannot start yet.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            NavigationLink {
                ShiftingSetupView(store: store, click: click)
            } label: {
                SetupRow(
                    title: "Zwift Click",
                    value: store.configuration.usesClick ? shiftingValue : nil,
                    status: EquipmentDisplayState(
                        isConfigured: store.configuration.usesClick,
                        connectionState: click.state,
                        isRequired: false
                    ),
                    isRequired: false
                )
            }

            NavigationLink {
                HeadwindSetupView(store: store, headwind: headwind)
            } label: {
                SetupRow(
                    title: "Wahoo Headwind",
                    value: store.configuration.headwindName,
                    status: EquipmentDisplayState(
                        isConfigured: store.configuration.usesHeadwind,
                        connectionState: headwind.state,
                        isRequired: false
                    ),
                    isRequired: false
                )
            }
        } header: {
            Text("Your equipment")
        } footer: {
            Text(
                "Equipment reconnects automatically. Open a device here to "
                    + "replace it or fix a connection."
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
                LabeledContent {
                    Text(store.configuration.drivetrainName)
                } label: {
                    Text("Gears")
                    Text(store.configuration.gearSummary)
                }
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
                "Use the smaller front ring if your bike has one. Pick a rear gear "
                    + "that keeps the chain straight, and leave it there. "
                    + "Virtual Gears does all the shifting from now on.",
                systemImage: "link"
            )
            .font(.callout)
        } header: {
            Text("On the bike")
        }
    }

    private func autoConnectSavedEquipment() {
        kickr.autoConnectSavedDevice()
        if store.configuration.usesClick {
            click.autoConnectSavedDevice()
        }
        if store.configuration.usesHeadwind {
            headwind.autoConnectSavedDevice()
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

            DeviceDiscoverySection(
                deviceName: "trainer",
                searchMessage: "Looking for trainers…",
                wakeInstruction: Self.wakeInstruction,
                hasSavedDevice: store.configuration.hasValidKickr,
                candidates: kickr.candidates,
                selectedID: kickr.selectedID,
                isScanning: kickr.isScanning,
                connectionState: kickr.state,
                startScanning: kickr.startScanning,
                stopScanning: {
                    kickr.stopScanning(reconnectSavedDevice: false)
                },
                cancelScanning: { kickr.stopScanning() }
            ) { candidate in
                store.configuration.rememberKickr(
                    named: candidate.name,
                    id: candidate.id
                )
                kickr.selectAndConnect(candidate.id)
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
    @State private var identificationCandidates: [BluetoothCandidate] = []
    @State private var identificationIndex = 0
    @State private var identificationTask: Task<Void, Never>?

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
                    if let battery = click.batteryLevel {
                        ClickBatteryRow(percent: battery)
                    }
                    ConnectionAdvice(
                        isReady: click.isReady,
                        isScanning: click.isScanning,
                        isConnecting: click.state.isConnectionInProgress,
                        isStalled: click.connectionIsStalled,
                        hasSavedDevice: click.hasSavedDevice,
                        wakeInstruction: WakeInstruction.click
                    )
                } header: {
                    Text("Your Click")
                } footer: {
                    Text(
                        "You can still shift on screen if the Click is asleep "
                            + "or out of battery."
                    )
                }
            }

            DeviceDiscoverySection(
                deviceName: "Zwift Click",
                searchMessage: "Looking for a Zwift Click…",
                wakeInstruction: WakeInstruction.click,
                hasSavedDevice: store.configuration.usesClick,
                candidates: click.candidates,
                selectedID: click.selectedID,
                isScanning: click.isScanning,
                connectionState: click.state,
                startScanning: click.startScanning,
                stopScanning: {
                    click.stopScanning(reconnectSavedDevice: false)
                },
                cancelScanning: { click.stopScanning() },
                identifyDuplicates: beginClickIdentification,
                identificationMessage: click.identificationCandidateID == nil
                    ? nil
                    : "Keep pressing either button on the Click you want.",
                cancelIdentification: cancelClickIdentification
            ) { candidate in
                store.configuration.rememberClick(
                    named: candidate.name,
                    id: candidate.id
                )
                click.selectAndConnect(candidate.id)
            }

            if store.configuration.usesClick {
                Section {
                    Button("Remove this Click", role: .destructive) {
                        click.forgetSelection()
                        store.configuration.forgetClick()
                    }
                }
            }
        }
        .navigationTitle("Zwift Click")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.configuration.usesClick {
                click.autoConnectSavedDevice()
            }
        }
        .onChange(of: click.latestButtonEvent) { _, event in
            guard click.identificationCandidateID != nil, let event else { return }
            if case .pressed = event {
                confirmClickIdentification()
            }
        }
        .onDisappear {
            identificationTask?.cancel()
            if click.identificationCandidateID != nil {
                click.cancelIdentification()
            }
        }
    }

    private func beginClickIdentification() {
        identificationCandidates = click.candidates
        identificationIndex = 0
        connectToIdentificationCandidate()
    }

    private func connectToIdentificationCandidate() {
        guard !identificationCandidates.isEmpty else { return }
        identificationTask?.cancel()
        let candidate = identificationCandidates[identificationIndex]
        click.connectForIdentification(candidate.id)
        identificationTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  click.identificationCandidateID != nil else { return }
            identificationIndex =
                (identificationIndex + 1) % identificationCandidates.count
            connectToIdentificationCandidate()
        }
    }

    private func confirmClickIdentification() {
        guard let id = click.identificationCandidateID,
              let candidate = identificationCandidates.first(where: {
                  $0.id == id
              })
        else { return }
        identificationTask?.cancel()
        click.confirmIdentification()
        store.configuration.rememberClick(
            named: candidate.name,
            id: candidate.id
        )
        identificationCandidates.removeAll()
    }

    private func cancelClickIdentification() {
        identificationTask?.cancel()
        identificationCandidates.removeAll()
        click.cancelIdentification()
    }
}

// MARK: - Headwind

private struct HeadwindSetupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var headwind: HeadwindCentralService

    var body: some View {
        Form {
            if store.configuration.usesHeadwind {
                Section {
                    EquipmentSummary(
                        name: store.configuration.headwindName
                            ?? "Wahoo HEADWIND",
                        state: headwind.state.label,
                        symbol: "fan.fill",
                        connected: headwind.isReady
                    )
                    ConnectionAdvice(
                        isReady: headwind.isReady,
                        isScanning: headwind.isScanning,
                        isConnecting: headwind.state.isConnectionInProgress,
                        isStalled: headwind.connectionIsStalled,
                        hasSavedDevice: headwind.hasSavedDevice,
                        wakeInstruction: WakeInstruction.headwind
                    )
                } header: {
                    Text("Your Headwind")
                } footer: {
                    Text(
                        "If the fan is in Manual, Virtual Gears returns it to "
                            + "Sensors before forgetting it."
                    )
                }

                HeadwindControls(headwind: headwind)
            }

            DeviceDiscoverySection(
                deviceName: "Wahoo Headwind",
                searchMessage: "Looking for a Wahoo Headwind…",
                wakeInstruction: WakeInstruction.headwind,
                hasSavedDevice: store.configuration.usesHeadwind,
                candidates: headwind.candidates,
                selectedID: headwind.selectedID,
                isScanning: headwind.state == .scanning,
                connectionState: headwind.state,
                startScanning: headwind.startScanning,
                stopScanning: {
                    headwind.stopScanning(reconnectSavedDevice: false)
                },
                cancelScanning: { headwind.stopScanning() }
            ) { candidate in
                store.configuration.rememberHeadwind(
                    named: candidate.name,
                    id: candidate.id
                )
                headwind.selectAndConnect(candidate.id)
            }

            if store.configuration.usesHeadwind {
                Section {
                    Button("Remove this Headwind", role: .destructive) {
                        headwind.stopUsing()
                    }
                }
            }
        }
        .navigationTitle("Wahoo Headwind")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.configuration.usesHeadwind {
                headwind.autoConnectSavedDevice()
            }
        }
        .onChange(of: headwind.hasSavedDevice) { _, saved in
            if !saved { store.configuration.forgetHeadwind() }
        }
    }
}

struct HeadwindControlView: View {
    @Bindable var headwind: HeadwindCentralService
    var onDone: (() -> Void)?

    var body: some View {
        Form {
            HeadwindControls(headwind: headwind, showsHelp: false)
        }
        .navigationTitle("Headwind")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct HeadwindControls: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Bindable var headwind: HeadwindCentralService
    var showsHelp = true
    private let quickSpeeds = [0, 25, 50, 75, 100]

    var body: some View {
        Section {
            Picker("Fan control", selection: manualBinding) {
                Text("Automatic").tag(false)
                Text("Manual").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!headwind.isReady || headwind.isCommandPending)

            if verticalSizeClass != .compact {
                modeSummary
            }

            if headwind.isManual || manualBinding.wrappedValue {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Fan speed")
                            .font(.headline)
                        Spacer()
                        Text("\(headwind.desiredManualSpeed)%")
                            .font(
                                .system(.largeTitle, design: .rounded)
                                    .weight(.bold)
                            )
                            .contentTransition(.numericText())
                    }

                    Slider(
                        value: speedBinding,
                        in: 0...100,
                        step: 5
                    ) {
                        Text("Fan speed")
                    } minimumValueLabel: {
                        Image(systemName: "fan")
                    } maximumValueLabel: {
                        Image(systemName: "fan.fill")
                    }

                    HStack(spacing: 8) {
                        ForEach(quickSpeeds, id: \.self) { speed in
                            quickSpeedButton(speed)
                        }
                    }

                    if verticalSizeClass != .compact {
                        HStack(spacing: 12) {
                            speedButton(
                                title: "Slower",
                                symbol: "minus",
                                change: -5
                            )
                            speedButton(
                                title: "Faster",
                                symbol: "plus",
                                change: 5
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
                .disabled(
                    !headwind.isReady
                        || headwind.isCommandPending
                        || !headwind.requestedManual
                )
            }
            if let error = headwind.commandError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Fan control")
        } footer: {
            if showsHelp {
                Text(
                    "Automatic uses the sensor already paired to your Headwind. "
                        + "Manual holds a fixed speed until you switch back."
                )
            }
        }
    }

    private var modeSummary: some View {
        HStack(spacing: 12) {
            Image(
                systemName: manualBinding.wrappedValue
                    ? "slider.horizontal.3" : "sensor.tag.radiowaves.forward"
            )
            .font(.title2)
            .foregroundStyle(.blue)
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(manualBinding.wrappedValue ? "Fixed fan speed" : "Sensor control")
                    .font(.headline)
                Text(modeDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            ProgressView()
                .opacity(headwind.isCommandPending ? 1 : 0)
                .accessibilityHidden(!headwind.isCommandPending)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var modeDetail: String {
        if headwind.isCommandPending {
            return "Applying change…"
        }
        if manualBinding.wrappedValue {
            return "Keeps running at the speed you choose"
        }
        return "Following \(headwind.lastSensorMode.label.lowercased())"
    }

    private var manualBinding: Binding<Bool> {
        Binding {
            headwind.requestedManual
        } set: { manual in
            manual ? headwind.useManualControl() : headwind.useSensorControl()
        }
    }

    private var speedBinding: Binding<Double> {
        Binding {
            Double(headwind.desiredManualSpeed)
        } set: { value in
            headwind.setManualSpeed(Int(value.rounded()))
        }
    }

    private func speedButton(
        title: String,
        symbol: String,
        change: Int
    ) -> some View {
        Button {
            headwind.setManualSpeed(headwind.desiredManualSpeed + change)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Changes fan speed by 5 percent")
    }

    private func quickSpeedButton(_ speed: Int) -> some View {
        Button {
            headwind.setManualSpeed(speed)
        } label: {
            Text(speed == 0 ? "Off" : "\(speed)")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(
            .borderedProminent
        )
        .tint(headwind.desiredManualSpeed == speed ? .blue : .gray.opacity(0.28))
        .foregroundStyle(headwind.desiredManualSpeed == speed ? .white : .primary)
        .accessibilityLabel(speed == 0 ? "Fan off" : "\(speed) percent")
    }
}

// MARK: - Gears

/// Gears are described the way a bike shop describes them: which chainrings are
/// on the front, and which cassette is on the back. A rider can copy the numbers
/// stamped on their own bike, or invent a bike they would rather be riding.
/// Reached from Settings, and directly from the ride screen's title menu when
/// the rider only wants their gears.
struct GearChoiceView: View {
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
                        ? "Twenty-four very wide virtual gears, from an easier "
                            + "climbing gear to the same hard end. They belong "
                            + "to no particular bike."
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

/// Gears described in numbers tell a rider almost nothing: 50/34 with 11-34 is
/// a fact about parts, not about what riding it feels like. Drawn instead, one
/// bar per gear from easiest to hardest, the two things that actually matter are
/// visible at a glance: how far the gears reach, and how evenly they are spread.
/// A tall step means a jump the legs will notice.
private struct GearSpread: View {
    let drivetrain: Drivetrain

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(drivetrain.gears.enumerated()), id: \.offset) {
                    index, gear in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            index == drivetrain.referenceIndex
                                ? Color.accentColor
                                : Color.secondary.opacity(0.35)
                        )
                        .frame(height: 12 + 48 * height(of: gear))
                }
            }
            .frame(height: 60, alignment: .bottom)

            // The marker is laid out exactly like the bars above it, so it
            // always sits under the right one. A centred label would only be
            // correct when the starting gear happens to be the middle one.
            HStack(spacing: 3) {
                ForEach(Array(drivetrain.gears.indices), id: \.self) { index in
                    Capsule()
                        .fill(
                            index == drivetrain.referenceIndex
                                ? Color.accentColor : Color.clear
                        )
                        .frame(height: 3)
                }
            }

            HStack {
                Text("Easier")
                Spacer()
                Text("Harder")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(drivetrain.gears.count) gears from easiest to hardest. "
                + "You start in gear \(drivetrain.referenceIndex + 1)."
        )
    }

    /// Spacing is judged by ratio between gears rather than difference, because
    /// that is how a step feels on the legs, so the scale is a logarithmic one.
    private func height(of gear: VirtualGear) -> Double {
        let ratios = drivetrain.gears.map(\.ratio)
        guard let easiest = ratios.min(), let hardest = ratios.max(),
              hardest > easiest
        else {
            return 0.5
        }
        return (log(gear.ratio) - log(easiest)) / (log(hardest) - log(easiest))
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
                GearSpread(drivetrain: drivetrain)
                    .padding(.vertical, 4)
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
    let title: String
    let value: String?
    let status: EquipmentDisplayState
    let isRequired: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let value {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(status.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                badge
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .connected:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .connecting:
            ProgressView().controlSize(.small)
        case .disconnected:
            Image(
                systemName: isRequired
                    ? "exclamationmark.circle.fill" : "circle.dashed"
            )
            .foregroundStyle(isRequired ? Color.orange : Color.secondary)
        case .notAdded:
            EmptyView()
        }
    }

    private var accessibilityDescription: String {
        [title, value, status.label]
            .compactMap { $0 }
            .joined(separator: ", ")
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

private struct DeviceDiscoverySection: View {
    let deviceName: String
    let searchMessage: String
    let wakeInstruction: String
    let hasSavedDevice: Bool
    let candidates: [BluetoothCandidate]
    let selectedID: UUID?
    let isScanning: Bool
    let connectionState: ProductConnectionState
    let startScanning: () -> Void
    let stopScanning: () -> Void
    let cancelScanning: () -> Void
    let identifyDuplicates: (() -> Void)?
    let identificationMessage: String?
    let cancelIdentification: (() -> Void)?
    let select: (BluetoothCandidate) -> Void

    @State private var discovery = DeviceDiscoveryState()
    @State private var timeoutTask: Task<Void, Never>?
    @State private var timeoutScheduled = false

    private let searchDuration = DeviceDiscoveryPolicy.searchDuration

    init(
        deviceName: String,
        searchMessage: String,
        wakeInstruction: String,
        hasSavedDevice: Bool,
        candidates: [BluetoothCandidate],
        selectedID: UUID?,
        isScanning: Bool,
        connectionState: ProductConnectionState,
        startScanning: @escaping () -> Void,
        stopScanning: @escaping () -> Void,
        cancelScanning: @escaping () -> Void,
        identifyDuplicates: (() -> Void)? = nil,
        identificationMessage: String? = nil,
        cancelIdentification: (() -> Void)? = nil,
        select: @escaping (BluetoothCandidate) -> Void
    ) {
        self.deviceName = deviceName
        self.searchMessage = searchMessage
        self.wakeInstruction = wakeInstruction
        self.hasSavedDevice = hasSavedDevice
        self.candidates = candidates
        self.selectedID = selectedID
        self.isScanning = isScanning
        self.connectionState = connectionState
        self.startScanning = startScanning
        self.stopScanning = stopScanning
        self.cancelScanning = cancelScanning
        self.identifyDuplicates = identifyDuplicates
        self.identificationMessage = identificationMessage
        self.cancelIdentification = cancelIdentification
        self.select = select
    }

    var body: some View {
        Section {
            switch discovery.phase {
            case .idle:
                if hasSavedDevice {
                    Button("Replace \(deviceName)") {
                        beginSearch()
                    }
                }
                BluetoothHelp(state: connectionState)

            case .searching:
                SearchingRow(message: progressMessage)
                BluetoothHelp(state: connectionState)

            case .showingResults:
                if isScanning {
                    SearchingRow(message: progressMessage)
                } else {
                    if hasDuplicateNames, let identifyDuplicates {
                        if let identificationMessage {
                            SearchingRow(message: identificationMessage)
                            Button("Cancel identification", role: .cancel) {
                                cancelIdentification?()
                            }
                        } else {
                            Button {
                                identifyDuplicates()
                            } label: {
                                Label(
                                    "Identify by pressing a button",
                                    systemImage: "hand.tap"
                                )
                            }
                        }
                    } else {
                        ForEach(candidates) { candidate in
                            CandidateRow(
                                candidate: candidate,
                                selected: candidate.id == selectedID
                            ) {
                                choose(candidate)
                            }
                        }
                    }
                    Button("Search Again") {
                        beginSearch()
                    }
                }
                BluetoothHelp(state: connectionState)

            case .timedOut:
                if !bluetoothUnavailable {
                    Label(
                        "No \(deviceName) found",
                        systemImage: "questionmark.circle"
                    )
                    Text(wakeInstruction)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Try Again") {
                    beginSearch()
                }
                .buttonStyle(.borderedProminent)
                BluetoothHelp(state: connectionState)
            }
        } header: {
            Text(hasSavedDevice ? "Device" : "Add \(deviceName)")
        } footer: {
            if discovery.phase == .showingResults, candidates.count > 1 {
                Text("More than one was found. Choose yours by name.")
            } else if !hasSavedDevice, discovery.phase == .idle {
                Text("Optional equipment is found automatically.")
            }
        }
        .task {
            if !hasSavedDevice {
                beginSearch()
            }
        }
        .onChange(of: isScanning) { _, scanning in
            if scanning { scheduleTimeoutIfNeeded() }
        }
        .onChange(of: candidates.count) { _, count in
            discovery.observe(candidateCount: count)
        }
        .onChange(of: connectionState) { _, state in
            handleConnectionState(state)
        }
        .onChange(of: hasSavedDevice) { _, saved in
            if saved {
                timeoutTask?.cancel()
                timeoutScheduled = false
                discovery.reset()
            }
        }
        .onDisappear {
            timeoutTask?.cancel()
            if discovery.phase != .idle || isScanning {
                cancelScanning()
            }
        }
    }

    private var progressMessage: String {
        guard !candidates.isEmpty else { return searchMessage }
        return candidates.count == 1
            ? "Found one. Checking for others…"
            : "Found \(candidates.count). Checking for others…"
    }

    private var hasDuplicateNames: Bool {
        let names = candidates.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        return Set(names).count < names.count
    }

    private var bluetoothUnavailable: Bool {
        if case .unavailable = connectionState { return true }
        return false
    }

    private func beginSearch() {
        timeoutTask?.cancel()
        timeoutScheduled = false
        discovery.start()
        startScanning()
        if isScanning {
            scheduleTimeoutIfNeeded()
        } else {
            handleConnectionState(connectionState)
        }
    }

    private func scheduleTimeoutIfNeeded() {
        guard !timeoutScheduled else { return }
        timeoutScheduled = true
        timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: searchDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            finishSearch()
        }
    }

    private func finishSearch() {
        timeoutScheduled = false
        stopScanning()
        if candidates.count == 1, let candidate = candidates.first,
           candidate.compatibility.isUsable {
            choose(candidate)
            return
        }
        discovery.finish(candidateCount: candidates.count)
    }

    private func handleConnectionState(_ state: ProductConnectionState) {
        guard discovery.phase == .searching
                || discovery.phase == .showingResults,
              !isScanning else { return }
        if case let .unavailable(reason) = state,
           !reason.localizedCaseInsensitiveContains("starting") {
            timeoutTask?.cancel()
            timeoutScheduled = false
            discovery.finish(candidateCount: candidates.count)
        }
    }

    private func choose(_ candidate: BluetoothCandidate) {
        timeoutTask?.cancel()
        timeoutScheduled = false
        select(candidate)
    }
}

private struct CandidateRow: View {
    let candidate: BluetoothCandidate
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.headline)
                        .foregroundStyle(usable ? .primary : .secondary)
                    if case let .unsupported(_, reason) = candidate.compatibility {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: trailingSymbol)
                    .foregroundStyle(trailingColour)
            }
            .contentShape(.rect)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .accessibilityLabel(accessibilityDescription)
    }

    private var usable: Bool { candidate.compatibility.isUsable }

    private var trailingSymbol: String {
        if !usable { return "exclamationmark.circle" }
        return selected ? "checkmark.circle.fill" : "circle"
    }

    private var trailingColour: Color {
        if !usable { return .orange }
        return selected ? .green : .secondary
    }

    private var accessibilityDescription: String {
        if case let .unsupported(_, reason) = candidate.compatibility {
            return "\(candidate.name). \(reason)"
        }
        return candidate.name
    }
}

private struct BluetoothHelp: View {
    let state: ProductConnectionState

    var body: some View {
        switch state {
        case let .unavailable(reason)
            where reason.localizedCaseInsensitiveContains("starting"):
            EmptyView()
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

private struct ClickBatteryRow: View {
    let percent: Int

    private var isLow: Bool { percent <= ClickCentralService.lowBatteryPercent }

    /// The bar fills in quarters, so it reads at a glance without anyone
    /// having to interpret the number.
    private var symbol: String {
        switch percent {
        case ...10: "battery.0percent"
        case ...40: "battery.25percent"
        case ...70: "battery.50percent"
        case ...90: "battery.75percent"
        default: "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isLow ? .orange : .secondary)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Battery \(percent)%")
                    .font(.subheadline)
                if isLow {
                    Text("Worth replacing the battery soon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLow
                ? "Click battery \(percent) percent. Worth replacing soon."
                : "Click battery \(percent) percent."
        )
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
            headwind: HeadwindCentralService(diagnostics: diagnostics)
        )
    }
}
