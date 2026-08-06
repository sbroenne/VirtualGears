import SwiftUI
import UIKit
import VirtualShiftCore

struct VirtualShiftHomeView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var headwind: HeadwindCentralService
    @Bindable var coordinator: ProxyCoordinator
    /// Set once the rider stops a ride, so the app does not immediately start a
    /// new one. Reopening the app is the only way to ask for another ride.
    @State private var riderStopped = false

    var body: some View {
        if coordinator.isRidePresented {
            ActiveRideView(
                store: store,
                kickr: kickr,
                click: click,
                headwind: headwind,
                coordinator: coordinator,
                onRiderStop: { riderStopped = true }
            )
        } else {
            StartupView(
                store: store,
                kickr: kickr,
                click: click,
                headwind: headwind,
                coordinator: coordinator,
                autoStarts: !riderStopped
            )
        }
    }
}

/// What a rider sees before the ride screen: the app looking for their trainer
/// and getting on with it. There is no setup to complete. A trainer worth
/// remembering and gears the trainer can copy are all a ride needs, and the
/// only question ever asked is which trainer, only when that is genuinely
/// unclear.
private struct StartupView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var headwind: HeadwindCentralService
    @Bindable var coordinator: ProxyCoordinator
    /// False after the rider stops a ride, so this screen waits for a tap.
    var autoStarts: Bool = true
    @State private var showsSettings = false
    /// Set when the trainers in range are too alike to choose between, which is
    /// the one situation where the rider has to say which is theirs.
    @State private var mustChoose = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let failureMessage {
                        failureCard(failureMessage)
                        retryButton
                    } else if mustChoose {
                        chooser
                    } else if autoStarts {
                        searching
                    } else {
                        stoppedCard
                        retryButton
                    }
                }
                .frame(maxWidth: 560)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("VirtualShift")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    .accessibilityHint("Review your equipment and gears")
                }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SetupView(
                        store: store,
                        kickr: kickr,
                        click: click,
                        headwind: headwind,
                        onFinish: { showsSettings = false }
                    )
                }
            }
            .task { await begin() }
            .onChange(of: canStart) { _, _ in startIfReady() }
            .onChange(of: kickr.candidates) { _, _ in considerCandidates() }
            .onDisappear { kickr.stopScanning() }
        }
    }

    // MARK: - Finding a trainer

    private func begin() async {
        if store.configuration.usesClick { click.autoConnectSavedDevice() }
        if store.configuration.usesHeadwind { headwind.autoConnectSavedDevice() }
        guard !store.configuration.hasValidKickr else {
            kickr.autoConnectSavedDevice()
            startIfReady()
            return
        }
        kickr.startScanning()
        // A moment for a second trainer to announce itself, so a room with two
        // in it is recognised as a choice rather than raced into.
        try? await Task.sleep(for: .seconds(2.5))
        considerCandidates()
    }

    /// Never interrupts a connection already under way, so a slow first reply
    /// from the right trainer cannot be overtaken by a louder neighbour.
    private func considerCandidates() {
        guard autoStarts, !store.configuration.hasValidKickr,
              kickr.selectedID == nil, !mustChoose else { return }
        let seen = kickr.candidates.map {
            DiscoveredTrainer(id: $0.id, signalStrength: $0.rssi)
        }
        guard !seen.isEmpty else { return }
        switch TrainerPicker.choice(from: seen) {
        case let .connect(id): adopt(id)
        case .ask: mustChoose = true
        }
    }

    /// Connecting is not enough on its own. Everything that lets a ride start
    /// asks whether a trainer has been *chosen*, so a trainer found
    /// automatically has to be recorded exactly as one picked in Settings is.
    /// Without this a new rider watches their trainer connect and then waits
    /// forever, because nothing ever agreed which trainer it was.
    private func adopt(_ id: UUID) {
        let name = kickr.candidates.first { $0.id == id }?.name
            ?? store.configuration.kickrName
        store.configuration.rememberKickr(named: name, id: id)
        kickr.selectAndConnect(id)
    }

    private var searching: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(searchingTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(
                "Turn the pedals if your trainer is asleep. Virtual shifting starts "
                    + "by itself, and your riding app will find VirtualShift."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            connectionList(includeRidingApp: false)
            chainReminder
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var searchingTitle: String {
        store.configuration.hasValidKickr
            ? "Getting VirtualShift ready"
            : "Looking for your trainer"
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which one is yours?")
                .font(.title3.weight(.semibold))
            Text(
                "More than one trainer is switched on nearby. Pick yours and "
                    + "VirtualShift will remember it."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ForEach(kickr.candidates) { candidate in
                Button {
                    mustChoose = false
                    adopt(candidate.id)
                } label: {
                    HStack {
                        Text(candidate.name)
                        Spacer()
                        Image(systemName: signalSymbol(candidate.rssi))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(candidate.name), \(signalWords(candidate.rssi))")
            }
            chainReminder
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalSymbol(_ rssi: Int) -> String {
        rssi >= TrainerPicker.closeBy
            ? "wifi" : (rssi >= TrainerPicker.inTheRoom ? "wifi.medium" : "wifi.low")
    }

    private func signalWords(_ rssi: Int) -> String {
        rssi >= TrainerPicker.closeBy
            ? "close by"
            : (rssi >= TrainerPicker.inTheRoom ? "further away" : "a long way off")
    }

    /// The one thing the app cannot do for the rider.
    private var chainReminder: some View {
        Label(
            "Use the smaller front ring if your bike has one. Pick a rear gear "
                + "that keeps the chain straight, and leave it there.",
            systemImage: "link"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Stopping and failing

    private var stoppedCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Virtual shifting stopped")
                    .font(.title3.weight(.semibold))
                Text(
                    "Virtual shifting is off. Your trainer setting is restored, "
                        + "and your riding app keeps running."
                )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            connectionList(includeRidingApp: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func connectionList(includeRidingApp: Bool) -> some View {
        var items = [
            ConnectionStatusItem(
                id: "trainer",
                name: store.configuration.kickrName.isEmpty
                    ? "Trainer" : store.configuration.kickrName,
                role: "Trainer",
                detail: connectionDetail(kickr.state),
                state: connectionState(kickr.state, isReady: kickr.isReady)
            )
        ]
        if store.configuration.usesClick {
            items.append(
                ConnectionStatusItem(
                    id: "click",
                    name: store.configuration.clickName,
                    role: "Zwift Click",
                    detail: connectionDetail(click.state),
                    state: connectionState(
                        click.state,
                        isReady: click.isReady,
                        isOptional: true
                    )
                )
            )
        }
        if store.configuration.usesHeadwind {
            items.append(
                ConnectionStatusItem(
                    id: "headwind",
                    name: store.configuration.headwindName ?? "Wahoo HEADWIND",
                    role: "Fan",
                    detail: connectionDetail(headwind.state),
                    state: connectionState(
                        headwind.state,
                        isReady: headwind.isReady,
                        isOptional: true
                    )
                )
            )
        }
        if includeRidingApp {
            let connected = coordinator.peripheral.subscribedAppCount > 0
            let steering = coordinator.peripheral.controllingAppID != nil
            items.append(
                ConnectionStatusItem(
                    id: "riding-app",
                    name: "PC riding app",
                    role: "Riding app",
                    detail: steering
                        ? "Connected and steering"
                        : (connected ? "Connected" : "Waiting for connection"),
                    state: connected
                        ? .ok : (coordinator.peripheral.isAdvertising ? .pending : .warn)
                )
            )
        }
        return ConnectionStatusList(items: items)
    }

    private func connectionDetail(_ state: ProductConnectionState) -> String {
        switch state {
        case .ready: "Connected"
        case .disconnected: "Asleep or not connected"
        default: state.shortLabel
        }
    }

    private func connectionState(
        _ state: ProductConnectionState,
        isReady: Bool,
        isOptional: Bool = false
    ) -> EquipmentItem.LinkState {
        if isReady { return .ok }
        if state.isConnectionInProgress || state == .scanning { return .pending }
        return isOptional ? .pending : .warn
    }

    private func failureCard(_ message: String) -> some View {
        let failure = coordinator.failure ?? .starting(trainerNeedsRestoring: false)
        let heading = failure.happenedWhileStopping
            ? "Ride could not be ended cleanly"
            : "Ride could not start"
        // Being told to check Bluetooth is useless when the problem is that
        // the trainer is still carrying a gear's wheel size. That distorts the
        // speed and distance it reports to anything else, so the rider is told
        // what actually puts it right.
        let advice = failure.trainerNeedsRestoring
            ? "Your trainer is still set to a gear's wheel size, so it will "
                + "report the wrong speed and distance to other apps. Bring "
                + "your phone near the trainer and open VirtualShift again, "
                + "and it will put the setting back on its own."
            : "Check that Bluetooth is on and your trainer is awake."
        return VStack(alignment: .leading, spacing: 10) {
            Label(heading, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(plainEnglish(message))
            Text(advice)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    /// The messages behind a failure are written for whoever is reading the
    /// diagnostic log, and they name parts of the Bluetooth standard a rider has
    /// no reason to have heard of. The ones that can actually reach this card
    /// are given a sentence that says what happened instead.
    private func plainEnglish(_ message: String) -> String {
        switch message {
        case "KICKR denied FTMS control":
            "Your trainer would not hand over control. Something else may still "
                + "be connected to it."
        case "Initial virtual gear is unavailable",
             "KICKR did not confirm the initial virtual gear":
            "Your trainer did not take the first gear."
        case "These gears are outside the trainer's safe range":
            "These gears go further than your trainer can be set to. Pick a "
                + "different gear set in Settings."
        case "Setup is incomplete":
            "Your setup is not finished yet."
        default:
            message
        }
    }

    private var retryButton: some View {
        Button {
            coordinator.startRide(configuration: store.configuration)
        } label: {
            Label("Start Shifting", systemImage: "bicycle")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canStart)
        .accessibilityHint(
            canStart ? "Starts virtual shifting" : "Your trainer is not connected yet"
        )
    }

    // MARK: - Starting

    /// Readiness means actually connected, not merely remembered.
    private var canStart: Bool {
        store.configuration.canFinishSetup
            && kickr.isReady
            && kickr.selectedID?.uuidString == store.configuration.kickrUUID
    }

    private var failureMessage: String? {
        if case let .failed(message) = coordinator.state { return message }
        return nil
    }

    /// The app does only one thing, so opening it is the instruction.
    private func startIfReady() {
        guard autoStarts, canStart, coordinator.state == .idle else { return }
        kickr.stopScanning()
        mustChoose = false
        coordinator.startRide(configuration: store.configuration)
    }
}


private struct ActiveRideView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var headwind: HeadwindCentralService
    @Bindable var coordinator: ProxyCoordinator
    /// Called only when the rider chooses to stop, so a ride that ends by
    /// itself is never mistaken for one they meant to end.
    let onRiderStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @State private var confirmsStop = false
    @State private var showsSettings = false
    @State private var showsGears = false
    @State private var showsFan = false
    /// Remembers the gears the ride started with, so the session is only rebuilt
    /// when the rider actually changed them.
    @State private var gearsWhenOpened: Drivetrain?
    /// The whole setup as it was before the rider changed gears, so it can be
    /// put back if the change does not take.
    @State private var setupWhenOpened: AppConfiguration?
    /// True while new gears are being applied.
    @State private var isChangingGears = false

    private var configuration: AppConfiguration { store.configuration }

    private func rememberOrRestartGears(isOpen: Bool) {
        if isOpen {
            gearsWhenOpened = configuration.drivetrain
            setupWhenOpened = configuration
        } else {
            applyGearChange(from: gearsWhenOpened, revertingTo: setupWhenOpened)
            gearsWhenOpened = nil
            setupWhenOpened = nil
        }
    }

    /// Changing gears mid-ride rebuilds the gear ladder in place. It deliberately
    /// does not stop and restart the ride: that removes the fitness machine
    /// service and disconnects the riding app, which is a long walk back to the
    /// PC in the middle of a session.
    private func applyGearChange(
        from previous: Drivetrain?,
        revertingTo original: AppConfiguration?
    ) {
        guard previous?.gears != configuration.drivetrain?.gears else { return }
        let updated = store.configuration
        Task {
            isChangingGears = true
            let applied = await coordinator.changeDrivetrain(updated)
            // Settings left showing gears the ride is not using is a quiet lie
            // the rider has no way to spot, and nothing tries again. The choice
            // goes back to the gears they are actually riding.
            if !applied, let original {
                store.configuration = original
            }
            isChangingGears = false
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape = geometry.size.width > geometry.size.height
                VStack(spacing: landscape ? 10 : 14) {
                    if landscape {
                        landscapeControls(geometry)
                    } else {
                        portraitControls(geometry)
                    }
                    equipmentFooter
                }
                .padding(.horizontal, landscape ? 18 : 14)
                .padding(.bottom, 4)
            }
            .navigationTitle(configuration.drivetrainName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Stopping virtual shifting changes the trainer setting, so it
                // still asks for confirmation. It sits alone, far from the
                // settings control, so a sweaty thumb cannot hit both.
                ToolbarItemGroup(placement: .topBarLeading) {
                    // Everything on this screen is aimed at while pedalling, so
                    // the bar's controls are grown well past the size a phone
                    // held in a calm hand would need. The symbol is drawn
                    // explicitly because a Label leaves the toolbar free to pick
                    // its own size and ignore the one asked for.
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2.weight(.semibold))
                            // A phone on handlebars is usually on its side, and
                            // iOS shrinks the bar in landscape. Without a floor
                            // the target drops under the 44pt minimum in exactly
                            // the orientation it is aimed at while moving.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .controlSize(.large)
                    .accessibilityLabel("Settings")
                    .accessibilityHint(
                        "Change your gears, trainer, Click, or Headwind"
                    )
                    if configuration.usesHeadwind {
                        Button {
                            showsFan = true
                        } label: {
                            Image(systemName: "fan.fill")
                                .font(.title2.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .controlSize(.large)
                        .accessibilityLabel("Headwind controls")
                    }
                }
                // The middle of the bar says what the ride is doing whenever it
                // is doing anything other than simply running.
                ToolbarItem(placement: .principal) {
                    if coordinator.state != .active {
                        Label(statusText, systemImage: statusSymbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    } else {
                        gearsMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsStop = true
                    } label: {
                        Text(coordinator.state == .stopping && !isChangingGears
                            ? "Stopping" : "Stop")
                            .font(.title3.weight(.bold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(coordinator.state == .stopping)
                    .accessibilityLabel("Stop virtual shifting")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SetupView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    headwind: headwind,
                    onFinish: { showsSettings = false }
                )
            }
        }
        .sheet(isPresented: $showsFan) {
            NavigationStack {
                HeadwindControlView(headwind: headwind) {
                    showsFan = false
                }
            }
            .presentationDetents([.medium])
        }
        // Asking for gears lands on the gears, not on a screen the rider then
        // has to navigate. Anything else would be a longer way round mid-ride.
        .sheet(isPresented: $showsGears) {
            NavigationStack {
                GearChoiceView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsGears = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
        .onChange(of: showsSettings) { _, isOpen in
            rememberOrRestartGears(isOpen: isOpen)
        }
        .onChange(of: showsGears) { _, isOpen in
            rememberOrRestartGears(isOpen: isOpen)
        }
        .onChange(of: hasEquipmentProblem) { _, hasProblem in
            guard !hasProblem else {
                // A rider not looking at the screen needs telling, because the
                // next shift will not work until this is dealt with.
                announce(equipmentProblem ?? "Check your equipment")
                return
            }
            announce("Equipment reconnected")
        }
        .onChange(of: coordinator.shiftConfirmation) {
            performFeedback(coordinator.lastShiftFeedback)
            announce("Gear \(gearAccessibilityValue)")
        }
        .confirmationDialog(
            "Stop virtual shifting?",
            isPresented: $confirmsStop,
            titleVisibility: .visible
        ) {
            Button("Stop Shifting", role: .destructive) {
                onRiderStop()
                Task { await coordinator.stopRide() }
            }
            Button("Keep Riding", role: .cancel) {}
        } message: {
            Text(
                "VirtualShift will stop virtual shifting and restore the trainer "
                    + "setting it borrowed. Your riding app keeps running."
            )
        }
    }

    /// The gear is the one thing the rider looks at, so it owns the screen and
    /// carries the visual weight on its own. It is a read-out, never a control:
    /// anything tappable has to look tappable, so all shifting lives in the two
    /// buttons below and nothing else on this screen reacts to a tap.
    /// The drivetrain used to sit in the title bar as plain text, which said
    /// nothing about being changeable and invited a tap that did nothing. It is
    /// a control now: it names the gears, says how many there are, and offers
    /// the only two changes worth making mid-ride without opening Settings.
    private var gearsMenu: some View {
        Menu {
            Section("\(configuration.gearCount) gears") {
                Picker("Gears", selection: gearKind) {
                    Text("Virtual gears").tag(true)
                    Text("Copy a real bike").tag(false)
                }
            }
            Button("All Gear Settings…", systemImage: "slider.horizontal.3") {
                showsGears = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(configuration.drivetrainName)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(
            "\(configuration.drivetrainName), \(configuration.gearCount) gears"
        )
        .accessibilityHint("Change your gears")
    }

    /// Writing through a binding keeps the restart in one place, so gears that
    /// change from the menu are put back safely exactly like gears that change
    /// in Settings.
    private var gearKind: Binding<Bool> {
        Binding(
            get: { configuration.usesVirtualGears },
            set: { newValue in
                let previous = configuration.drivetrain
                let original = configuration
                store.configuration.usesVirtualGears = newValue
                applyGearChange(from: previous, revertingTo: original)
            }
        )
    }

    private func portraitControls(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 14) {
            gearHero(
                fontSize: min(
                    geometry.size.width * 0.61,
                    geometry.size.height * 0.38
                )
            )
            HStack(spacing: 12) {
                shiftButton(easier: true)
                shiftButton(easier: false)
            }
            .frame(
                height: min(
                    max(160, geometry.size.height * 0.32),
                    geometry.size.height * 0.36
                )
            )
            .accessibilityElement(children: .contain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func landscapeControls(_ geometry: GeometryProxy) -> some View {
        let buttonWidth = max(150, geometry.size.width * 0.28)
        return HStack(spacing: 12) {
            shiftButton(easier: true)
                .frame(width: buttonWidth)
            gearHero(
                fontSize: min(
                    geometry.size.width * 0.18,
                    geometry.size.height * 0.46
                )
            )
            shiftButton(easier: false)
                .frame(width: buttonWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func gearHero(fontSize: CGFloat) -> some View {
        gearReadout(
            fontSize: fontSize
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasEquipmentProblem: Bool {
        equipmentItems.contains { !$0.isOptional && $0.state != .ok }
    }

    /// The one thing worth telling the rider about, if anything is wrong.
    private var equipmentProblem: String? {
        guard let problem = equipmentItems.first(where: {
            !$0.isOptional && $0.state != .ok
        }) else { return nil }
        return "\(problem.title), \(problem.detail)"
    }

    /// Supporting detail, so it sits at the bottom in the quietest type on the
    /// screen and never takes more than one line. When something is wrong that
    /// single line becomes the plain-English problem instead, so the rider only
    /// ever reads one thing down here.
    private var equipmentFooter: some View {
        Group {
            if let problem = equipmentItems.first(where: {
                !$0.isOptional && $0.state != .ok
            }) {
                Label(
                    "\(problem.title) · \(problem.detail)",
                    systemImage: problem.state.symbol
                )
                .foregroundStyle(problem.state.tint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(equipmentProblem ?? "")
            } else {
                // The KICKR and the Click are grouped because VirtualShift is
                // the one connecting to them. The riding app is set apart
                // because it connects to VirtualShift instead.
                HStack(spacing: 26) {
                    equipmentGroup(items: ownedEquipment.filter { $0.state == .ok })
                    equipmentGroup(items: [ridingAppEquipment])
                    // Deliberately separate from the Click's tick, which means
                    // connected. Tinting that tick would read, at a glance on
                    // a moving bike, as the Click having dropped out.
                    if configuration.usesClick, click.isReady, click.batteryIsLow,
                        let battery = click.batteryLevel {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.25percent")
                                .foregroundStyle(.orange)
                            Text("Click \(battery)%")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Click battery low, \(battery) percent")
                    }
                    if coordinator.ridingAppSetWheelSize {
                        Text("Wheel size from your app")
                            .accessibilityLabel(
                                "Your riding app set the wheel size. "
                                    + "Your gears are built around it."
                            )
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        // The one line a rider most needs when something is wrong is the line
        // that must not be squeezed away. Large text sizes are chosen by people
        // who need them, so it wraps rather than shrinking to nothing.
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Every item carries its own tick. Sharing one tick across a group read as
    /// though only the first piece of equipment was connected.
    private func equipmentGroup(items: [EquipmentItem]) -> some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(item.title)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title), connected")
            }
        }
    }

    private var equipmentItems: [EquipmentItem] {
        ownedEquipment + [ridingAppEquipment]
    }

    /// Everything VirtualShift connects out to.
    private var ownedEquipment: [EquipmentItem] {
        var items = [
            EquipmentItem(
                id: "kickr",
                title: "KICKR",
                state: kickr.isReady
                    ? .ok : (kickr.state.isConnectionInProgress ? .pending : .warn),
                detail: kickr.state.label
            )
        ]
        if configuration.usesClick {
            items.append(
                EquipmentItem(
                    isOptional: true,
                    id: "click",
                    title: "Click",
                    state: click.isReady ? .ok : .pending,
                    detail: click.state.label
                )
            )
        }
        if configuration.usesHeadwind {
            items.append(
                EquipmentItem(
                    isOptional: true,
                    id: "headwind",
                    title: "Fan",
                    state: headwind.isReady ? .ok : .pending,
                    detail: headwind.state.label
                )
            )
        }
        return items
    }

    /// The riding app connects in to VirtualShift, so it is reported apart.
    private var ridingAppEquipment: EquipmentItem {
        let isConnected = coordinator.peripheral.subscribedAppCount > 0
        let isSteering = coordinator.peripheral.controllingAppID != nil
        let isAdvertising = coordinator.peripheral.isAdvertising
        let detail: String
        if isSteering {
            detail = "Connected and steering"
        } else if isConnected {
            detail = "Connected"
        } else if isAdvertising {
            // VirtualShift broadcasts its own name, but iOS also reports the
            // phone's name and will not let an app change it, so some riding
            // apps list the phone instead. A rider hunting a name that is not
            // there assumes it is broken, so name both before they look.
            detail = "Pick VirtualShift or your iPhone's name"
        } else {
            detail = "Not advertising"
        }
        return EquipmentItem(
            id: "ridingapp",
            title: "Riding app",
            state: isConnected ? .ok : (isAdvertising ? .pending : .warn),
            detail: detail
        )
    }

    private func gearReadout(fontSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(primaryGearText)
                .font(.system(
                    size: max(44, fontSize),
                    weight: .black,
                    design: .rounded
                ).monospacedDigit())
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(
                    coordinator.state == .active ? Color.primary : Color.secondary
                )
                .accessibilityLabel("Gear")
                .accessibilityValue(gearAccessibilityValue)
            Text(secondaryGearText)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(isShiftPending ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityHidden(true)
            GearPositionRail(
                gears: coordinator.gearSequence,
                selectedIndex: coordinator.confirmedGearIndex,
                requestedIndex: coordinator.requestedGearIndex
            )
            .padding(.top, 10)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private func shiftButton(easier: Bool) -> some View {
        ShiftButton(
            title: easier ? "Easier" : "Harder",
            symbol: easier ? "minus" : "plus",
            hint: easier
                ? "Requests the next easier gear. Hold to keep shifting easier."
                : "Requests the next harder gear. Hold to keep shifting harder.",
            disabled: easier ? !coordinator.canShiftEasier : !coordinator.canShiftHarder
        ) {
            coordinator.shift(easier ? .easier : .harder)
        } repeatAction: {
            coordinator.beginHold(easier ? .easier : .harder)
        } releaseAction: {
            coordinator.endHold()
        }
    }

    /// True while the rider has asked for a gear the trainer has not confirmed.
    private var isShiftPending: Bool {
        guard let requested = coordinator.requestedGearIndex,
              let confirmed = coordinator.confirmedGearIndex else { return false }
        return requested != confirmed
    }

    /// Shifting is sequential, so the position is the only number worth reading
    /// at arm's length. The real chainring and cog go underneath, small.
    private var primaryGearText: String {
        guard let index = coordinator.confirmedGearIndex else { return "—" }
        return "\(index + 1)"
    }

    private var secondaryGearText: String {
        guard coordinator.confirmedGearIndex != nil else {
            return coordinator.state == .active
                ? "Waiting for the trainer" : statusText
        }
        if isShiftPending { return "Shifting…" }
        let total = coordinator.gearSequence.count
        guard let gear = coordinator.displayedGear,
              !configuration.usesVirtualGears else {
            return "of \(total)"
        }
        return "of \(total) · \(gear.chainring)×\(gear.cog)"
    }

    private var gearAccessibilityLabel: String {
        guard let gear = coordinator.displayedGear,
              let index = coordinator.confirmedGearIndex else {
            return "Confirmed gear unavailable"
        }
        let position = "Confirmed gear \(index + 1) of "
            + "\(coordinator.gearSequence.count)"
        guard !configuration.usesVirtualGears else { return position }
        return position + ", \(gear.chainring) tooth chainring by "
            + "\(gear.cog) tooth cog"
    }

    /// VoiceOver reads a label once and re-reads the *value* when it changes, so
    /// the gear belongs in the value. With everything in the label, a rider who
    /// cannot see the screen hears nothing when they shift.
    private var gearAccessibilityValue: String {
        guard let gear = coordinator.displayedGear,
              let index = coordinator.confirmedGearIndex else {
            return "not available"
        }
        let position = "\(index + 1) of \(coordinator.gearSequence.count)"
        guard !configuration.usesVirtualGears else { return position }
        return position + ", \(gear.chainring) tooth chainring by "
            + "\(gear.cog) tooth cog"
    }

    /// Says something out loud to a rider using VoiceOver. On a bike the screen
    /// is often not being looked at, so a confirmed shift has to be audible.
    private func announce(_ message: String) {
        guard voiceOverRunning else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private var statusText: String {
        if isChangingGears { return "Changing gears" }
        switch coordinator.state {
        case .connecting: return "Connecting equipment"
        case .active: return "Ride active"
        case .reconnecting: return "Control lost · reconnecting"
        case .stopping: return "Stopping safely"
        case .idle: return "Shifting stopped"
        case let .failed(message): return message
        }
    }

    private var statusSymbol: String {
        if isChangingGears { return "progress.indicator" }
        switch coordinator.state {
        case .active: return "checkmark.circle.fill"
        case .connecting, .stopping: return "progress.indicator"
        case .reconnecting, .failed: return "exclamationmark.triangle.fill"
        case .idle: return "stop.circle"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .active: .green
        case .reconnecting, .failed: .orange
        default: .secondary
        }
    }

    /// Haptics only. A shift has to be felt through the bars rather than heard:
    /// a rider is usually wearing headphones or running the riding app's sound,
    /// and a phone chirping into that is noise, not information.
    private func performFeedback(_ kind: ShiftFeedbackKind) {
        switch kind {
        case .single:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .multiple:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        }
    }
}

private struct EquipmentItem: Identifiable {
    /// Optional equipment never raises a problem and is never waited for. A
    /// Zwift Click is an extra: the on-screen buttons always shift, so a Click
    /// that is missing or asleep is not something the rider has to fix.
    var isOptional = false

    enum LinkState: Equatable {
        case ok
        case pending
        case warn

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .pending: "circle.dotted"
            case .warn: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ok: .green
            case .pending: .secondary
            case .warn: .orange
            }
        }
    }

    let id: String
    let title: String
    let state: LinkState
    let detail: String
}

private struct ConnectionStatusItem: Identifiable {
    let id: String
    let name: String
    let role: String
    let detail: String
    let state: EquipmentItem.LinkState
}

/// The same compact, named connection row is used while the app is starting
/// and after it stops. Hiding an optional device until it connects leaves a
/// rider unable to tell "asleep" from "not configured".
private struct ConnectionStatusList: View {
    let items: [ConnectionStatusItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Image(systemName: item.state.symbol)
                        .foregroundStyle(item.state.tint)
                        .font(.title3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(item.role) · \(item.detail)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.name), \(item.role), \(item.detail)")
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }
}

/// An ordinary SwiftUI button, deliberately so: a filled, clearly bounded
/// shape with a label, the system pressed state and standard accessibility.
/// It is simply sized far above the 44 pt minimum for use on a bike. Holding it
/// keeps shifting, matching how holding a Click button sweeps the cassette.
private struct ShiftButton: View {
    let title: String
    let symbol: String
    let hint: String
    let disabled: Bool
    let action: () -> Void
    let repeatAction: () -> Void
    let releaseAction: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 56
    @State private var repeatTask: Task<Void, Never>?
    @State private var isHeld = false
    /// When the hold last shifted a gear. Letting go must not add a further
    /// gear on top of the ones the rider already watched go by. This is a
    /// timestamp rather than a flag so it can never get stuck and swallow a
    /// later, genuine tap.
    @State private var lastRepeatAt: Date?

    var body: some View {
        Button(action: tapped) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .black, design: .rounded))
                    .frame(height: symbolSize)
                Text(title)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .disabled(disabled)
        // The button keeps its normal tap behaviour; this only adds the hold.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startRepeat() }
                .onEnded { _ in stopRepeat() }
        )
        .onDisappear(perform: stopRepeat)
        // A cancelled touch never reports an end, so leaving the foreground has
        // to stop the repeat too or it would keep shifting with no finger down.
        .onChange(of: scenePhase) {
            if scenePhase != .active { stopRepeat() }
        }
        .accessibilityLabel("Shift \(title.lowercased())")
        .accessibilityHint(
            disabled ? "You are already in the last gear" : hint
        )
    }

    private func tapped() {
        if let lastRepeatAt, Date().timeIntervalSince(lastRepeatAt) < 0.4 {
            return
        }
        action()
    }

    private func startRepeat() {
        guard !disabled, repeatTask == nil else { return }
        isHeld = true
        lastRepeatAt = nil
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, isHeld else { return }
            // Said once. From here the trainer sets the pace, so the sweep runs
            // as fast as gears can really be confirmed instead of on a timer
            // that either outruns the trainer or has its beats dropped.
            lastRepeatAt = Date()
            repeatAction()
        }
    }

    private func stopRepeat() {
        let wasSweeping = isHeld && lastRepeatAt != nil
        isHeld = false
        repeatTask?.cancel()
        repeatTask = nil
        if wasSweeping {
            lastRepeatAt = Date()
            releaseAction()
        }
    }
}

private struct GearPositionRail: View {
    let gears: [VirtualGear]
    let selectedIndex: Int?
    let requestedIndex: Int?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let width = max(
                3,
                (proxy.size.width - spacing * CGFloat(max(0, gears.count - 1)))
                    / CGFloat(max(1, gears.count))
            )
            HStack(spacing: spacing) {
                ForEach(Array(gears.indices), id: \.self) { index in
                    Capsule()
                        .fill(fill(for: index))
                        .frame(width: width, height: index == selectedIndex ? 34 : 16)
                        .overlay {
                            if isTarget(index) || (differentiate && index == selectedIndex) {
                                Capsule().stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 40)
        // The big readout directly above already says which gear this is, and
        // saying it twice makes a rider swipe past the same fact to reach the
        // shift buttons. This is a picture of what that number means.
        .accessibilityHidden(true)
    }

    private func fill(for index: Int) -> Color {
        if index == selectedIndex { return .accentColor }
        return .secondary.opacity(0.35)
    }

    /// The gear the rider asked for is outlined until the trainer confirms it,
    /// so a tap is acknowledged without ever showing it as the current gear.
    private func isTarget(_ index: Int) -> Bool {
        guard let requestedIndex, requestedIndex != selectedIndex else { return false }
        return index == requestedIndex
    }
}

#Preview("First run") {
    let diagnostics = ProductDiagnosticsStore()
    let kickr = KickrCentralService(diagnostics: diagnostics)
    let click = ClickCentralService(diagnostics: diagnostics)
    let headwind = HeadwindCentralService(diagnostics: diagnostics)
    VirtualShiftHomeView(
        store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.firstRun")!),
        kickr: kickr,
        click: click,
        headwind: headwind,
        coordinator: ProxyCoordinator(
            kickr: kickr,
            click: click,
            peripheral: FTMSPeripheral(diagnostics: diagnostics),
            screen: DeviceScreenWake(),
            diagnostics: diagnostics
        )
    )
}
