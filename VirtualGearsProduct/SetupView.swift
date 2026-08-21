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
    var autoConnectsOnAppear = true

    var body: some View {
        Form {
            setupStatusSection
            equipmentSection
            wheelSizeSection
            gearsSection
            parkedGearSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.settings")
        .task {
            if autoConnectsOnAppear {
                autoConnectSavedEquipment()
            }
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

    @ViewBuilder
    private var setupStatusSection: some View {
        if needsSetup {
            Section {
                Text(setupStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    if store.configuration.hasSafeGearing {
                        ParkedGearView(store: store)
                    } else {
                        GearChoiceView(store: store)
                    }
                } label: {
                    Label(setupNextAction, systemImage: "arrow.right.circle.fill")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("action.finishSetup")
            } header: {
                Text("Finish setup")
            } footer: {
                Text(
                    "Gearing comes first because it decides which parked gear "
                        + "is safe. Then confirm where the chain is left."
                )
            }
        }
    }

    private var needsSetup: Bool {
        !store.configuration.hasSafeGearing
            || store.configuration.parkedGear == nil
            || store.configuration.parkedGearPutsGearsOutOfReach
    }

    private var setupStatusMessage: String {
        if !store.configuration.hasSafeGearing {
            return "First choose gears that fit the trainer. After that, Virtual "
                + "Gears can recommend where to leave the chain."
        }
        if store.configuration.parkedGearPutsGearsOutOfReach {
            return "Your gears fit the trainer, but the current chain position "
                + "puts some of them out of reach. Choose a workable parked gear."
        }
        return "Your gears are ready. Confirm the gear the bike is left in so "
            + "every virtual gear is scaled correctly."
    }

    private var setupNextAction: String {
        store.configuration.hasSafeGearing
            ? "Confirm the gear the bike is in"
            : "Choose gears that fit"
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
                    "Your trainer is not connected, so shifting cannot start yet.",
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
                    + "switch devices or fix a connection."
            )
        }
    }

    /// The saved name, unless it is the row's own title. A Click that reports
    /// itself as "Zwift Click" under a row called "Zwift Click" says the same
    /// word twice and tells the rider nothing; the badge beside it already says
    /// whether it is there.
    private var shiftingValue: String? {
        let name = store.configuration.clickName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Not added" }
        guard name.caseInsensitiveCompare("Zwift Click") != .orderedSame else {
            return nil
        }
        return name
    }

    private var wheelSizeSection: some View {
        Section {
            NavigationLink {
                NormalWheelSizeView(store: store)
            } label: {
                LabeledContent(
                    "Wheel circumference",
                    value: wheelCircumferenceValue
                )
            }
        } header: {
            Text("Trainer wheel size")
        } footer: {
            Text(
                "Optional. Used when your riding app does not send a wheel circumference. "
                    + "A value sent by the riding app takes precedence."
            )
        }
    }

    private var wheelCircumferenceValue: String {
        if let saved = store.configuration.normalWheelCircumferenceMillimeters {
            return "\(saved) mm"
        }
        return "Default · \(store.configuration.neutralCircumferenceMillimeters) mm"
    }

    private var gearsSection: some View {
        Section {
            NavigationLink {
                GearChoiceView(store: store)
            } label: {
                // The row leads with what the rider chose, not with a count of
                // it. "24 gears · extra-low climbing range" under the word Gears
                // describes the result of a decision without ever naming it.
                LabeledContent {
                    Text(store.configuration.gearSummary)
                } label: {
                    Text("Gears")
                    Text(store.configuration.drivetrainName)
                }
            }

            if !store.configuration.hasSafeGearing {
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
    /// The bike never shifts, so the gear it is parked in is a fact the app has
    /// to know rather than guess. Every virtual gear is scaled from that ratio,
    /// and a wrong guess moves the whole ladder without ever looking broken.
    private var parkedGearSection: some View {
        Section {
            NavigationLink {
                ParkedGearView(store: store)
            } label: {
                // Deliberately not a connection badge. Nothing here connects;
                // this is a fact about the bike, so it either has an answer or
                // it is still needed.
                LabeledContent {
                    if let parked = store.configuration.parkedGear {
                        Text(parked.name)
                    } else {
                        Text("Needed")
                            .foregroundStyle(.orange)
                    }
                } label: {
                    Text("Gear the bike is in")
                }
            }
            // A stable identifier for UI tests to find this row directly,
            // since it can sit below the fold once other rows are added
            // above it and its value text changes with the parked gear.
            .accessibilityIdentifier("row.parkedGear")

            if store.configuration.parkedGear == nil,
               store.configuration.hasSafeGearing {
                Label(
                    "Virtual Gears needs to know which gear the bike is left "
                        + "in. Without it every gear is scaled from a guess.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            if let warning = store.configuration.parkedGearWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("On the bike")
        } footer: {
            Text(store.configuration.parkedGearAdviceText)
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

private struct NormalWheelSizeView: View {
    @Bindable var store: ConfigurationStore
    @State private var enteredValue: String
    @State private var isApplyingDefault = false

    init(store: ConfigurationStore) {
        self.store = store
        _enteredValue = State(
            initialValue: String(
                store.configuration.neutralCircumferenceMillimeters
            )
        )
    }

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(WheelCircumferenceShortcut.all) { shortcut in
                            Button {
                                apply(shortcut)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shortcut.kind)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(shortcut.size)
                                        .font(.headline)
                                    Text("\(shortcut.millimeters) mm")
                                        .font(.subheadline)
                                }
                                .frame(width: 112, alignment: .leading)
                                .padding(12)
                                .background(
                                    selectedShortcut == shortcut
                                        ? Color.accentColor.opacity(0.16)
                                        : Color(.secondarySystemGroupedBackground),
                                    in: .rect(cornerRadius: 12)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedShortcut == shortcut
                                                ? Color.accentColor : .clear,
                                            lineWidth: 2
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(shortcut.kind), \(shortcut.size), "
                                    + "\(shortcut.millimeters) millimetres"
                            )
                            .accessibilityAddTraits(
                                selectedShortcut == shortcut ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("wheel.shortcuts")
                .scrollIndicators(.hidden)
            } header: {
                Text("Common size shortcuts")
            }

            Section {
                TextField("Millimetres", text: $enteredValue)
                    .keyboardType(.numberPad)
                    .onChange(of: enteredValue) { _, value in
                        if isApplyingDefault {
                            isApplyingDefault = false
                            return
                        }
                        guard let millimeters = Int(value), isValid(millimeters)
                        else { return }
                        store.setNormalWheelCircumference(
                            millimeters: millimeters
                        )
                    }

                Stepper(
                    value: wheelSize,
                    in: lowerBound...upperBound,
                    step: 1
                ) {
                    LabeledContent(
                        "Wheel circumference",
                        value: "\(store.configuration.neutralCircumferenceMillimeters) mm"
                    )
                }

                Button("Use default \(defaultMillimeters) mm") {
                    store.useDefaultWheelCircumference()
                    let defaultText = String(defaultMillimeters)
                    if enteredValue != defaultText {
                        isApplyingDefault = true
                        enteredValue = defaultText
                    }
                }
                .accessibilityIdentifier("wheel.useDefault")
                .disabled(
                    store.configuration.normalWheelCircumferenceMillimeters == nil
                )
            } header: {
                Text("Circumference")
            } footer: {
                Text(
                    "Choose 1800–2400 mm. Virtual Gears uses \(defaultMillimeters) mm "
                        + "(700×25 road) when no value is saved. A wheel circumference "
                        + "from the riding app takes precedence."
                )
            }

            if let value = Int(enteredValue), !isValid(value) {
                Section {
                    Label(
                        "Enter a value from \(lowerBound) to \(upperBound) mm.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Wheel circumference")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultMillimeters: Int {
        Int(TrainerSafety.referenceCircumferenceMillimeters)
    }

    private var selectedShortcut: WheelCircumferenceShortcut? {
        guard let entered = Int(enteredValue)
        else { return nil }
        return WheelCircumferenceShortcut.all.first {
            $0.millimeters == entered
        }
    }

    private func apply(_ shortcut: WheelCircumferenceShortcut) {
        store.setNormalWheelCircumference(millimeters: shortcut.millimeters)
        enteredValue = String(shortcut.millimeters)
    }

    private var wheelSize: Binding<Int> {
        Binding(
            get: { store.configuration.neutralCircumferenceMillimeters },
            set: { value in
                store.setNormalWheelCircumference(millimeters: value)
                enteredValue = String(value)
            }
        )
    }

    private var lowerBound: Int {
        Int(TrainerSafety.supportedRidingAppCircumferenceMillimeters.lowerBound)
    }

    private var upperBound: Int {
        Int(TrainerSafety.supportedRidingAppCircumferenceMillimeters.upperBound)
    }

    private func isValid(_ value: Int) -> Bool {
        (lowerBound...upperBound).contains(value)
    }
}

private struct WheelCircumferenceShortcut: Identifiable, Equatable {
    let kind: String
    let size: String
    let millimeters: Int

    var id: String { "\(kind)-\(size)" }

    static let all = [
        WheelCircumferenceShortcut(kind: "Road", size: "700×25", millimeters: 2_105),
        WheelCircumferenceShortcut(kind: "Road", size: "700×28", millimeters: 2_136),
        WheelCircumferenceShortcut(kind: "Gravel", size: "700×40", millimeters: 2_200),
        WheelCircumferenceShortcut(kind: "MTB", size: "26×2.0", millimeters: 2_055),
        WheelCircumferenceShortcut(kind: "MTB", size: "27.5×2.25", millimeters: 2_188),
        WheelCircumferenceShortcut(kind: "MTB", size: "29×2.25", millimeters: 2_326),
    ]
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
                initialPhase: stagedDiscoveryPhase(for: .trainer),
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
                    "The two large buttons on the shifting screen always shift, "
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
                initialPhase: stagedDiscoveryPhase(for: .click),
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
                initialPhase: stagedDiscoveryPhase(for: .headwind),
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
        .accessibilityIdentifier("screen.headwind")
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
        .accessibilityAddTraits(
            headwind.desiredManualSpeed == speed ? .isSelected : []
        )
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
                        ? "Evenly spaced gears designed for indoor riding "
                            + "rather than copied from a particular bike."
                        : "Pick the groupset your bike has, or one you would "
                            + "rather be riding. Nothing on the bike moves — "
                            + "this is the gearing that gets simulated."
                )
            }

            if store.configuration.usesVirtualGears {
                Section {
                    ChoiceRow(
                        title: GearLadderCatalog.standardRange.name,
                        note: GearLadderCatalog.standardRange.note,
                        selected: !store.configuration.usesCustomLadder
                    ) {
                        store.setLadder(GearLadderCatalog.standardRange)
                    }
                    NavigationLink {
                        CustomGearLadderView(store: store)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Custom")
                                if store.configuration.usesCustomLadder {
                                    Text(store.configuration.gearLadder.note)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if store.configuration.usesCustomLadder {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .accessibilityAddTraits(
                            store.configuration.usesCustomLadder
                                ? .isSelected : []
                        )
                    }
                } header: {
                    Text("Which ladder")
                } footer: {
                    Text(
                        "Standard is the widely used 24-gear table. Custom "
                            + "lets you set your own gear count and range."
                    )
                }
            }

            if !store.configuration.usesVirtualGears {
                Section {
                    NavigationLink {
                        GroupsetChoiceView(store: store)
                    } label: {
                        LabeledContent(
                            "Groupset",
                            value: store.configuration.groupset?.qualifiedName
                                ?? "Custom"
                        )
                    }

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
                            value: store.configuration.cassette.qualifiedName
                        )
                    }
                } header: {
                    Text("The bike you want to feel")
                } footer: {
                    Text(
                        "Pick a groupset for a set that exists, or set the "
                            + "chainrings and cassette yourself if your bike "
                            + "is not listed."
                    )
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
        .accessibilityIdentifier("screen.gears")
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
struct GearPreview: View {
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
                            + "pairings. The gears are walked the way an "
                            + "electronic groupset shifts them — one cog at a "
                            + "time, changing ring at the right moment — so "
                            + "badly crossed and repeated combinations never "
                            + "appear."
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

/// Lets a rider define their own gear count and range instead of the one
/// built-in ladder, for a bike whose gearing does not match the standard
/// table. Selecting "Custom" and opening this screen are the same action, so
/// there is nothing to separately confirm — the live preview at the bottom is
/// the confirmation.
private struct CustomGearLadderView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            Section {
                Stepper(
                    "\(store.configuration.customLadder.gearCount) gears",
                    value: gearCountBinding,
                    in: CustomGearLadder.gearCountRange
                )
            } header: {
                Text("How many gears")
            }

            Section {
                Stepper(
                    "Easiest \(easiestRatioText)×",
                    value: easiestBinding,
                    in: CustomGearLadder.ratioHundredthsRange,
                    step: 5
                )
                Stepper(
                    "Hardest \(hardestRatioText)×",
                    value: hardestBinding,
                    in: CustomGearLadder.ratioHundredthsRange,
                    step: 5
                )
            } header: {
                Text("Range")
            } footer: {
                Text(
                    "A ratio is how much harder or easier a gear is than "
                        + "riding one-to-one. 1.00× is even, 2.00× is twice "
                        + "as hard, 0.50× is half as hard."
                )
            }

            Section {
                GearPreview(configuration: store.configuration)
            } header: {
                Text("What you get")
            }
        }
        .navigationTitle("Custom Ladder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opening this screen is how a rider chooses Custom, so it takes
            // effect immediately rather than waiting for a value to change —
            // otherwise navigating here and back without touching anything
            // would silently leave Standard selected.
            if !store.configuration.usesCustomLadder {
                store.setCustomLadder(store.configuration.customLadder)
            }
        }
        .accessibilityIdentifier("screen.customGearLadder")
    }

    private var easiestRatioText: String {
        String(
            format: "%.2f",
            Double(store.configuration.customLadder.easiestRatioHundredths)
                / 100
        )
    }

    private var hardestRatioText: String {
        String(
            format: "%.2f",
            Double(store.configuration.customLadder.hardestRatioHundredths)
                / 100
        )
    }

    private var gearCountBinding: Binding<Int> {
        Binding(
            get: { store.configuration.customLadder.gearCount },
            set: { store.configuration.customLadder.gearCount = $0 }
        )
    }

    /// Kept at least one step below the hardest ratio, so the two can never
    /// cross and silently swap places under the rider's thumb.
    private var easiestBinding: Binding<Int> {
        Binding(
            get: { store.configuration.customLadder.easiestRatioHundredths },
            set: { newValue in
                store.configuration.customLadder.easiestRatioHundredths = min(
                    newValue,
                    store.configuration.customLadder.hardestRatioHundredths - 5
                )
            }
        )
    }

    private var hardestBinding: Binding<Int> {
        Binding(
            get: { store.configuration.customLadder.hardestRatioHundredths },
            set: { newValue in
                store.configuration.customLadder.hardestRatioHundredths = max(
                    newValue,
                    store.configuration.customLadder.easiestRatioHundredths + 5
                )
            }
        )
    }
}

private struct ChainringChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.title) { group in
                // A heading with nothing under it looks like a loading bug, so
                // groups the catalogue no longer stocks simply do not appear.
                if !options(count: group.count).isEmpty {
                    Section {
                        ForEach(options(count: group.count)) { option in
                            ChoiceRow(
                                title: option.name,
                                note: option.note,
                                detail: nil,
                                selected: option.id
                                    == store.configuration.chainringID,
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
                            spokenTitle: option.qualifiedName,
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
///
/// This is the one row style used for every tap-to-select list in setup —
/// ladders, groupsets, physical parts and the parked gear all reuse it rather
/// than each hand-rolling a `Button` — because a hand-rolled row rendered its
/// title in the accent colour on iOS 26 (`.buttonStyle(.plain)` alone did not
/// override it) and nobody noticed until a rider pointed it out. Sharing this
/// one implementation means that class of bug cannot come back a part at a
/// time.
struct ChoiceRow: View {
    let title: String
    /// What VoiceOver says, when the visible title alone is ambiguous. Three
    /// cassettes are called "11-28"; on screen their section heading tells them
    /// apart, but a rider hearing the list gets no heading with each row.
    var spokenTitle: String?
    /// A single line under the title. Read aloud by VoiceOver as part of the
    /// row, so it is the right place for anything a rider needs to hear, not
    /// just see — the gear the row is recommended for, or the cog counts on a
    /// cassette.
    var note: String? = nil
    /// Overrides the note's colour for a warning that should still be tappable
    /// (a parked gear that puts some gears out of reach, say). Leave nil for
    /// the default: secondary, or red when `fits` is false.
    var noteColor: Color? = nil
    /// A second, quieter line, not read aloud — used for the small print under
    /// a part that already explains itself in `note`.
    var detail: String? = nil
    let selected: Bool
    /// False disables the row, dims it and swaps in a fixed "too wide" note —
    /// used only by the two screens that can conflict with another choice. All
    /// other callers default to always-tappable.
    var fits: Bool = true
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let resolvedNote {
                        Text(resolvedNote)
                            .font(.subheadline)
                            .foregroundStyle(resolvedNoteColor)
                    }
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
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var resolvedNote: String? {
        guard fits else { return "Too wide to combine with your other choice" }
        return note
    }

    private var resolvedNoteColor: Color {
        guard fits else { return .red }
        return noteColor ?? .secondary
    }

    private var accessibilityText: String {
        guard let resolvedNote else { return spokenTitle ?? title }
        return "\(spokenTitle ?? title), \(resolvedNote)"
    }
}

// MARK: - Shared rows

private enum StagedDiscoveryDevice {
    case trainer
    case click
    case headwind
}

/// Production discovery always starts idle. Screenshot fixtures can seed a
/// later app-owned phase so UI tests cover results, timeout, and identification
/// without waiting on a real Bluetooth radio.
private func stagedDiscoveryPhase(
    for device: StagedDiscoveryDevice
) -> DeviceDiscoveryState.Phase {
#if DEBUG
    guard let fixture = ScreenshotFixture.current else { return .idle }
    switch (device, fixture) {
    case (.trainer, .settingsSearching):
        return .searching
    case (.trainer, .settingsResults),
         (.trainer, .settingsUnsupported):
        return .showingResults
    case (.trainer, .settingsTimedOut),
         (.trainer, .settingsBluetoothIssue):
        return .timedOut
    case (.click, .settingsClickDuplicates),
         (.click, .settingsClickIdentifying):
        return .showingResults
    default:
        return .idle
    }
#else
    .idle
#endif
}

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
        initialPhase: DeviceDiscoveryState.Phase = .idle,
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
        var initialDiscovery = DeviceDiscoveryState()
        switch initialPhase {
        case .idle:
            break
        case .searching:
            initialDiscovery.start()
        case .showingResults:
            initialDiscovery.start()
            initialDiscovery.observe(candidateCount: max(1, candidates.count))
        case .timedOut:
            initialDiscovery.start()
            initialDiscovery.finish(candidateCount: 0)
        }
        _discovery = State(initialValue: initialDiscovery)
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
                    Button("Switch to another \(deviceName)") {
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
    NavigationStack {
        SetupView(
            store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.setup")!),
            kickr: KickrCentralService(),
            click: ClickCentralService(),
            headwind: HeadwindCentralService()
        )
    }
}

/// What is physically on the bike, and which gear it is left sitting in.
///
/// This is the one question the app used to skip. The bike never shifts, so the
/// parked ratio is the baseline every virtual gear is scaled from — and a
/// "quiet, straight chain line" is satisfied by gears more than twice as hard
/// as each other. Rather than ask an open question, the app names the gear it
/// wants and lets the rider confirm or correct it in one tap.
struct ParkedGearView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            recommendationSection
            bikeSection
            gearSection
        }
        .navigationTitle("Gear the bike is in")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.parkedGear")
    }

    private var recommendationSection: some View {
        Section {
            Text(store.configuration.parkedGearAdviceText)

            if let suggestion = store.configuration.suggestedParkedGear,
               store.configuration.parkedGear != suggestion {
                Button("Use \(suggestion.name)") {
                    store.park(in: suggestion)
                }
                .accessibilityIdentifier("button.useSuggestedGear")
            }

            if let warning = store.configuration.parkedGearWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("What to do")
        } footer: {
            Text(
                "Virtual Gears changes gear by changing the wheel size the "
                    + "trainer works from, so it has to know the gear it is "
                    + "working from. Park the chain once and leave it there."
            )
        }
    }

    private var bikeSection: some View {
        Section {
            Picker("Back of the bike", selection: backOfBike) {
                Text("Cassette").tag(false)
                Text("Single sprocket").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            NavigationLink {
                PhysicalChainringView(store: store)
            } label: {
                LabeledContent("Chainrings", value: chainringSummary)
            }

            if store.configuration.physical.isSingleSprocket {
                Stepper(
                    value: sprocketTeeth,
                    in: 9...30
                ) {
                    LabeledContent(
                        "Sprocket",
                        value: "\(store.configuration.physical.cogTeeth[0])T"
                    )
                }
                .accessibilityIdentifier("parkedGear.sprocketTeeth")
            } else {
                NavigationLink {
                    PhysicalCassetteView(store: store)
                } label: {
                    LabeledContent("Cassette", value: cassetteSummary)
                }
            }
        } header: {
            Text("What is on the bike")
        } footer: {
            Text(
                "This is your real bike, not the gearing you asked to be "
                    + "simulated. A Zwift Cog is a single sprocket with 14 teeth."
            )
        }
    }

    private var gearSection: some View {
        Section {
            ForEach(candidates, id: \.self) { gear in
                ChoiceRow(
                    title: gear.name,
                    note: caption(for: gear),
                    noteColor: isWorkable(gear) ? nil : .orange,
                    selected: gear == store.configuration.parkedGear
                ) {
                    store.park(in: gear)
                }
            }
        } header: {
            Text("Which gear is it in")
        }
    }

    private func caption(for gear: ParkedGear) -> String? {
        if gear == store.configuration.suggestedParkedGear {
            return "Recommended — quietest that works"
        } else if !isWorkable(gear) {
            return "Puts some gears out of reach"
        }
        return nil
    }

    private var candidates: [ParkedGear] {
        ParkedGearAdvice.usableParkedGears(in: store.configuration.physical)
    }

    private func isWorkable(_ gear: ParkedGear) -> Bool {
        guard let drivetrain = store.configuration.drivetrain else { return true }
        return ParkedGearAdvice.isWorkable(gear, simulating: drivetrain)
    }

    private var chainringSummary: String {
        store.configuration.physical.chainringTeeth
            .map { "\($0)" }
            .joined(separator: "/")
    }

    private var cassetteSummary: String {
        let cogs = store.configuration.physical.cogTeeth
        guard let smallest = cogs.min(), let largest = cogs.max() else {
            return "—"
        }
        return "\(smallest)-\(largest)"
    }

    private var backOfBike: Binding<Bool> {
        Binding(
            get: { store.configuration.physical.isSingleSprocket },
            set: { single in
                store.setPhysicalCogs(
                    single ? PhysicalSetup.zwiftCogTeeth : PhysicalSetup.default.cogTeeth
                )
            }
        )
    }

    private var sprocketTeeth: Binding<Int> {
        Binding(
            get: { store.configuration.physical.cogTeeth.first ?? 14 },
            set: { store.setPhysicalCogs([$0]) }
        )
    }
}

/// The rings on the rider's own bike. Kept separate from the simulated gearing
/// on purpose: plenty of riders will run a single 31-tooth ring and ask for a
/// twelve-speed groupset to be simulated on top of it.
struct PhysicalChainringView: View {
    @Binding private var teeth: [Int]

    init(store: ConfigurationStore) {
        _teeth = Binding(
            get: { store.configuration.physical.chainringTeeth },
            set: { store.setPhysicalChainrings($0) }
        )
    }

    init(teeth: Binding<[Int]>) {
        _teeth = teeth
    }

    var body: some View {
        Form {
            Section("One chainring") {
                ForEach(options(withRingCount: 1)) { option in
                    choice(for: option)
                }
            }

            Section("Two chainrings") {
                ForEach(options(withRingCount: 2)) { option in
                    choice(for: option)
                }
            }
        }
        .navigationTitle("Chainrings on the bike")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func options(withRingCount count: Int) -> [ChainringOption] {
        DrivetrainCatalog.chainrings
            .filter { $0.teeth.count == count }
            .sorted { $0.teeth.lexicographicallyPrecedes($1.teeth) }
    }

    private func choice(for option: ChainringOption) -> some View {
        ChoiceRow(
            title: option.name,
            selected: option.teeth == teeth
        ) {
            teeth = option.teeth
        }
    }
}

struct PhysicalCassetteView: View {
    @Binding private var cogs: [Int]

    init(store: ConfigurationStore) {
        _cogs = Binding(
            get: { store.configuration.physical.cogTeeth },
            set: { store.setPhysicalCogs($0) }
        )
    }

    init(cogs: Binding<[Int]>) {
        _cogs = cogs
    }

    var body: some View {
        Form {
            ForEach(DrivetrainCatalog.cassettes) { option in
                ChoiceRow(
                    title: option.qualifiedName,
                    note: option.cogs.map(String.init).joined(separator: ", "),
                    selected: option.cogs == cogs
                ) {
                    cogs = option.cogs
                }
            }
        }
        .navigationTitle("Cassette on the bike")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Named groupsets are the fast path: one tap sets both the chainrings and the
/// cassette to a pairing that exists on a real bike, so the simulated ladder
/// matches gearing the rider already recognises. The parts lists stay behind it
/// for anyone whose bike is not here.
private struct GroupsetChoiceView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            ForEach(GroupsetBrand.allCases) { brand in
                Section {
                    ForEach(GroupsetCatalog.groupsets(brand: brand)) { set in
                        ChoiceRow(
                            title: set.name,
                            spokenTitle: set.qualifiedName,
                            note: "\(set.speeds)-speed · \(set.note)",
                            selected: set.id == store.configuration.groupset?.id
                        ) {
                            store.setGroupset(set)
                        }
                    }
                } header: {
                    Text(brand.name)
                }
            }

            if let groupset = store.configuration.groupset,
               !store.physicalSetupMatches(groupset) {
                Section {
                    Button("Also set this as what's on the bike") {
                        store.matchPhysicalSetup(to: groupset)
                    }
                } footer: {
                    Text(
                        "This only changes the gearing being simulated. Your "
                            + "real bike still shows different chainrings or "
                            + "a different cassette — tap to bring those in "
                            + "line too, unless that is deliberate."
                    )
                }
            }
        }
        .navigationTitle("Groupset")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.groupset")
    }
}
