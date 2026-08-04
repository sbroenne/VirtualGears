import AudioToolbox
import SwiftUI
import UIKit
import VirtualShiftCore

struct VirtualShiftHomeView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var coordinator: ProxyCoordinator
    @Bindable var diagnostics: ProductDiagnosticsStore
    /// Set once the rider stops a ride, so the app does not immediately start a
    /// new one. Reopening the app is the only way to ask for another ride.
    @State private var riderStopped = false

    var body: some View {
        if coordinator.isRidePresented {
            ActiveRideView(
                configuration: store.configuration,
                kickr: kickr,
                click: click,
                coordinator: coordinator,
                onRiderStop: { riderStopped = true }
            )
        } else if store.configuration.setupComplete {
            ReadyView(
                store: store,
                kickr: kickr,
                click: click,
                coordinator: coordinator,
                diagnostics: diagnostics,
                autoStarts: !riderStopped
            )
        } else {
            NavigationStack {
                SetupView(
                    store: store,
                    kickr: kickr,
                    click: click,
                    diagnostics: diagnostics,
                    onStartRide: {
                        coordinator.startRide(configuration: store.configuration)
                    }
                )
            }
        }
    }
}

private struct ReadyView: View {
    @Bindable var store: ConfigurationStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var coordinator: ProxyCoordinator
    @Bindable var diagnostics: ProductDiagnosticsStore
    /// False after the rider stops a ride, so this screen waits for a tap.
    var autoStarts: Bool = true
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    equipmentCard
                    if let failureMessage {
                        failureCard(failureMessage)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                startRideBar
            }
            .navigationTitle("VirtualShift")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    .accessibilityHint("Review equipment, diagnostics, and ride setup")
                }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SetupView(
                        store: store,
                        kickr: kickr,
                        click: click,
                        diagnostics: diagnostics,
                        isEditing: true,
                        onFinish: { showsSettings = false }
                    )
                }
            }
            .task {
                kickr.autoConnectSavedDevice()
                if store.configuration.usesClick {
                    click.autoConnectSavedDevice()
                }
                startIfReady()
            }
            .onChange(of: canStart) { _, _ in startIfReady() }
        }
    }

    private var equipmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            EquipmentStatusRow(
                title: "KICKR",
                name: store.configuration.kickrName,
                state: kickr.state,
                required: true,
                isStalled: kickr.connectionIsStalled,
                wakeInstruction: WakeInstruction.trainer
            )
            Divider()
            if store.configuration.usesClick {
                EquipmentStatusRow(
                    title: "Click",
                    name: store.configuration.clickName,
                    state: click.state,
                    required: false,
                    isStalled: click.connectionIsStalled,
                    wakeInstruction: WakeInstruction.click
                )
            } else {
                Label("On-screen shifting", systemImage: "hand.tap.fill")
                    .accessibilityLabel("Click not configured. On-screen shifting available.")
            }
            Divider()
            HStack {
                Label(
                    store.configuration.gearSummary,
                    systemImage: "gearshape.2.fill"
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Gears: \(store.configuration.drivetrainName), "
                    + store.configuration.gearSummary
            )
            Divider()
            Label(
                "Put your chain in one quiet, straight position and leave it there.",
                systemImage: "link.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ride could not start", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(message)
            Text("Check that Bluetooth is on and your equipment is awake, then retry.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    /// The button is the only thing that reports readiness. A filled, tappable
    /// button means go; the system's disabled styling means not yet. Saying it a
    /// second time in prose would only be something else to read.
    private var startRideBar: some View {
        VStack(spacing: 8) {
            if isWaitingToStart {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to your trainer…")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Connecting to your trainer. The ride starts by itself."
                )
                Text("Your ride starts by itself. Make sure the trainer is awake.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                startRideButton
            }
        }
        .padding()
        .background(.bar)
    }

    /// True while the app is connecting on the rider's behalf, so it shows
    /// progress instead of a dimmed button the rider is not meant to press.
    private var isWaitingToStart: Bool {
        autoStarts && !canStart && failureMessage == nil
    }

    private var startRideButton: some View {
        VStack(spacing: 8) {
            if let blockingReason {
                Text(blockingReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                coordinator.startRide(configuration: store.configuration)
            } label: {
                Label(
                    failureMessage == nil ? "Start Ride" : "Retry Ride",
                    systemImage: "bicycle"
                )
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStart)
            .accessibilityHint(
                canStart
                    ? "Opens the ride controls"
                    : (blockingReason ?? "Not ready to ride yet")
            )
        }
    }

    /// Names the one thing still missing, so a dimmed button is never a dead end.
    private var blockingReason: String? {
        guard !canStart else { return nil }
        if !store.configuration.canFinishSetup {
            return "Check your setup before riding."
        }
        if !kickr.isReady {
            return "Your KICKR is not connected yet."
        }
        return nil
    }

    /// Readiness means actually connected, not merely remembered. The ride would
    /// fail otherwise, and the button would have promised something it could not
    /// deliver.
    private var canStart: Bool {
        store.configuration.canFinishSetup
            && kickr.isReady
            && kickr.selectedID?.uuidString == store.configuration.kickrUUID
    }

    private var failureMessage: String? {
        if case let .failed(message) = coordinator.state { return message }
        return nil
    }

    /// The app does only one thing, so opening it is the instruction. As soon as
    /// the trainer is connected the ride begins on its own; the button below is
    /// only for retrying after a stop or a failure.
    private func startIfReady() {
        guard autoStarts, canStart, coordinator.state == .idle else { return }
        coordinator.startRide(configuration: store.configuration)
    }
}

private struct EquipmentStatusRow: View {
    let title: String
    let name: String
    let state: ProductConnectionState
    let required: Bool
    let isStalled: Bool
    let wakeInstruction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: state == .ready
                    ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(state == .ready ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.shortLabel)
                    .lineLimit(2)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(required ? "Required " : "")\(title), \(name), \(state.label)"
            )

            if needsWakeHint {
                Text(wakeInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Waiting is normal for a few seconds. Waiting with no explanation is what
    /// makes it feel broken, so the advice appears as soon as it stalls, or
    /// straight away if nothing is being attempted at all.
    ///
    /// Only equipment a ride actually needs says this. Telling a rider to wake
    /// a Zwift Click would be asking them to fix something that is not holding
    /// anything up, since the on-screen buttons always shift.
    private var needsWakeHint: Bool {
        guard required, state != .ready else { return false }
        if isStalled { return true }
        return !state.isConnectionInProgress && state != .scanning
    }
}

private struct ActiveRideView: View {
    let configuration: AppConfiguration
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var coordinator: ProxyCoordinator
    /// Called only when the rider chooses to stop, so a ride that ends by
    /// itself is never mistaken for one they meant to end.
    let onRiderStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsStop = false
    @State private var lastInteraction = Date()
    @State private var isDimmed = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape = geometry.size.width > geometry.size.height
                VStack(spacing: landscape ? 10 : 14) {
                    gearHero(geometry, landscape: landscape)
                    shiftButtons(geometry, landscape: landscape)
                    equipmentFooter
                        .opacity(showsChrome ? 1 : 0.3)
                }
                .padding(.horizontal, landscape ? 18 : 14)
                .padding(.bottom, 4)
            }
            .navigationTitle(configuration.drivetrainName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coordinator.state != .active {
                        Label(statusText, systemImage: statusSymbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsStop = true
                    } label: {
                        Text(coordinator.state == .stopping ? "Stopping" : "Stop")
                            .font(.body.weight(.semibold))
                    }
                    .tint(.red)
                    .disabled(coordinator.state == .stopping)
                    .accessibilityLabel("Stop ride")
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded(wake))
        .onChange(of: coordinator.shiftConfirmation) {
            wake()
            performFeedback(coordinator.lastShiftFeedback)
        }
        .onChange(of: coordinator.shiftInteraction) {
            wake()
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard Date().timeIntervalSince(lastInteraction) >= 30 else {
                    continue
                }
                if reduceMotion {
                    isDimmed = true
                } else {
                    withAnimation(.easeOut(duration: 0.8)) {
                        isDimmed = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Stop this ride?",
            isPresented: $confirmsStop,
            titleVisibility: .visible
        ) {
            Button("Stop Ride", role: .destructive) {
                wake()
                onRiderStop()
                Task { await coordinator.stopRide() }
            }
            Button("Keep Riding", role: .cancel) {}
        } message: {
            Text(
                "VirtualShift will stop accepting controls, safely stop the trainer, "
                    + "restore its starting state, and disconnect."
            )
        }
    }

    /// The gear is the one thing the rider looks at, so it owns the screen and
    /// carries the visual weight on its own. It is a read-out, never a control:
    /// anything tappable has to look tappable, so all shifting lives in the two
    /// buttons below and nothing else on this screen reacts to a tap.
    private func gearHero(
        _ geometry: GeometryProxy,
        landscape: Bool
    ) -> some View {
        gearReadout(
            fontSize: landscape
                ? min(geometry.size.width * 0.18, geometry.size.height * 0.28)
                : min(geometry.size.width * 0.5, geometry.size.height * 0.26)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Two plainly bordered, filled buttons. They are far larger than the 44 pt
    /// minimum so they still work with sweaty hands, but they are ordinary
    /// buttons: obvious edges, a real pressed state and standard VoiceOver.
    private func shiftButtons(
        _ geometry: GeometryProxy,
        landscape: Bool
    ) -> some View {
        HStack(spacing: 12) {
            shiftButton(easier: true)
            shiftButton(easier: false)
        }
        .frame(height: max(96, geometry.size.height * (landscape ? 0.36 : 0.44)))
        .accessibilityElement(children: .contain)
    }

    /// Equipment trouble always wins over the ambient state, so a problem can
    /// never hide behind a faded screen. The Stop control and the layout stay
    /// put either way, so no target ever moves under the rider's thumb.
    private var showsChrome: Bool {
        !isDimmed || hasEquipmentProblem || coordinator.state != .active
    }

    private var hasEquipmentProblem: Bool {
        equipmentItems.contains { $0.state != .ok }
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
            } else {
                // The KICKR and the Click are grouped because VirtualShift is
                // the one connecting to them. The riding app is set apart
                // because it connects to VirtualShift instead.
                HStack(spacing: 26) {
                    equipmentGroup(items: ownedEquipment.filter { $0.state == .ok })
                    equipmentGroup(items: [ridingAppEquipment])
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
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
            detail = "Waiting to be found"
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
                .accessibilityLabel(gearAccessibilityLabel)
            Text(secondaryGearText)
                .font(.headline)
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
            .padding(.horizontal, 18)
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
            wake()
            coordinator.shift(easier ? .easier : .harder)
        } repeatAction: {
            wake()
            coordinator.shiftRepeatedly(easier ? .easier : .harder)
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

    private var statusText: String {
        switch coordinator.state {
        case .connecting: "Connecting equipment"
        case .active: "Ride active"
        case .reconnecting: "Control lost · reconnecting"
        case .stopping: "Stopping safely"
        case .idle: "Ride stopped"
        case let .failed(message): message
        }
    }

    private var statusSymbol: String {
        switch coordinator.state {
        case .active: "checkmark.circle.fill"
        case .connecting, .stopping: "progress.indicator"
        case .reconnecting, .failed: "exclamationmark.triangle.fill"
        case .idle: "stop.circle"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .active: .green
        case .reconnecting, .failed: .orange
        default: .secondary
        }
    }

    private func wake() {
        lastInteraction = Date()
        guard isDimmed else { return }
        if reduceMotion {
            isDimmed = false
        } else {
            withAnimation(.easeIn(duration: 0.2)) {
                isDimmed = false
            }
        }
    }

    private func performFeedback(_ kind: ShiftFeedbackKind) {
        switch kind {
        case .single:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1104)
        case .multiple:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
            AudioServicesPlaySystemSound(1157)
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
            disabled ? "Unavailable at the drivetrain boundary" : hint
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
            while !Task.isCancelled, isHeld {
                lastRepeatAt = Date()
                repeatAction()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func stopRepeat() {
        isHeld = false
        repeatTask?.cancel()
        repeatTask = nil
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
                        .frame(width: width, height: index == selectedIndex ? 22 : 10)
                        .overlay {
                            if isTarget(index) || (differentiate && index == selectedIndex) {
                                Capsule().stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel(
            selectedIndex.map {
                "Gear position \($0 + 1) of \(gears.count)"
            } ?? "Gear position unavailable"
        )
    }

    private func fill(for index: Int) -> Color {
        if index == selectedIndex { return .accentColor }
        return .secondary.opacity(0.25)
    }

    /// The gear the rider asked for is outlined until the trainer confirms it,
    /// so a tap is acknowledged without ever showing it as the current gear.
    private func isTarget(_ index: Int) -> Bool {
        guard let requestedIndex, requestedIndex != selectedIndex else { return false }
        return index == requestedIndex
    }
}

struct DiagnosticsView: View {
    @Bindable var diagnostics: ProductDiagnosticsStore
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Environment(\.dismiss) private var dismiss
    @State private var preparedExport: String?
    @State private var copied = false

    var body: some View {
        List {
            Section("Bluetooth") {
                DiagnosticStatusRow(title: "KICKR", value: kickr.state.label)
                DiagnosticStatusRow(title: "Click", value: click.state.label)
                if needsBluetoothHelp {
                    Text(
                        "Allow Bluetooth in Settings, turn Bluetooth on, keep equipment "
                            + "awake and nearby, then retry the connection."
                    )
                    Button("Open App Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section("App & Device") {
                DiagnosticStatusRow(title: "App", value: appVersion)
                DiagnosticStatusRow(title: "Device", value: deviceDescription)
                DiagnosticStatusRow(
                    title: "Operation",
                    value: "Foreground required · no ride history stored"
                )
            }

            Section {
                Button {
                    preparedExport = diagnostics.exportText(
                        appVersion: appVersion,
                        deviceDescription: deviceDescription
                    )
                } label: {
                    Label("Prepare Export", systemImage: "square.and.arrow.up")
                }
                if let preparedExport {
                    ShareLink(item: preparedExport) {
                        Label("Share Prepared Diagnostics", systemImage: "square.and.arrow.up.fill")
                    }
                }
                Button {
                    UIPasteboard.general.string = diagnostics.exportText(
                        appVersion: appVersion,
                        deviceDescription: deviceDescription
                    )
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Diagnostics", systemImage: "doc.on.doc")
                }
            } footer: {
                Text(
                    "Export is generated only when requested. Bluetooth identifiers are "
                        + "redacted and only the newest \(diagnostics.capacity) events are retained."
                )
            }

            Section("Recent Events (\(diagnostics.entries.count))") {
                if diagnostics.entries.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "checkmark.circle",
                        description: Text("Connection and recovery events will appear here.")
                    )
                } else {
                    ForEach(Array(diagnostics.entries.suffix(100).reversed())) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.source)
                                    .font(.headline)
                                Spacer()
                                Text(entry.level.rawValue.capitalized)
                                    .font(.caption.weight(.semibold))
                            }
                            Text(entry.message)
                                .font(.subheadline)
                                .textSelection(.enabled)
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var needsBluetoothHelp: Bool {
        [kickr.state.label, click.state.label].contains {
            $0.localizedCaseInsensitiveContains("permission")
                || $0.localizedCaseInsensitiveContains("unauthorized")
                || $0.localizedCaseInsensitiveContains("off")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var deviceDescription: String {
        "\(UIDevice.current.model) · \(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion)"
    }
}

private struct DiagnosticStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .combine)
    }
}

#Preview("First run") {
    let diagnostics = ProductDiagnosticsStore()
    let kickr = KickrCentralService(diagnostics: diagnostics)
    let click = ClickCentralService(diagnostics: diagnostics)
    VirtualShiftHomeView(
        store: ConfigurationStore(defaults: UserDefaults(suiteName: "preview.firstRun")!),
        kickr: kickr,
        click: click,
        coordinator: ProxyCoordinator(
            kickr: kickr,
            click: click,
            diagnostics: diagnostics
        ),
        diagnostics: diagnostics
    )
}
