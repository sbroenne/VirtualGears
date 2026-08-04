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

    var body: some View {
        if coordinator.isRidePresented {
            ActiveRideView(
                configuration: store.configuration,
                kickr: kickr,
                click: click,
                coordinator: coordinator
            )
        } else if store.configuration.setupComplete {
            ReadyView(
                store: store,
                kickr: kickr,
                click: click,
                coordinator: coordinator,
                diagnostics: diagnostics
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
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    readinessHeader
                    equipmentCard
                    if let failureMessage {
                        failureCard(failureMessage)
                    }
                    startRideButton
                }
                .frame(maxWidth: 720, alignment: .leading)
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
            }
        }
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready when you are")
                .font(.largeTitle.bold())
            Text("Your equipment and virtual drivetrain are ready.")
                .font(.body)
                .foregroundStyle(.secondary)
            Label(
                coordinator.state.label,
                systemImage: failureMessage == nil
                    ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(failureMessage == nil ? Color.green : Color.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private var equipmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved equipment")
                .font(.title2.bold())
            EquipmentStatusRow(
                title: "KICKR",
                name: store.configuration.kickrName,
                state: kickr.state,
                required: true
            )
            Divider()
            if store.configuration.usesClick {
                EquipmentStatusRow(
                    title: "Click",
                    name: store.configuration.clickName,
                    state: click.state,
                    required: false
                )
            } else {
                Label("On-screen shifting", systemImage: "hand.tap.fill")
                    .accessibilityLabel("Click not configured. On-screen shifting available.")
            }
            Divider()
            HStack {
                Label(
                    store.configuration.drivetrainPreset.detail,
                    systemImage: "gearshape.2.fill"
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(store.configuration.drivetrainPreset.detail) virtual drivetrain"
            )
            Divider()
            Label(
                "Before Start: choose a quiet, straight chain line and leave it there.",
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
            Text("Check Bluetooth and that your saved equipment is awake, then retry.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var startRideButton: some View {
        Button {
            coordinator.startRide(configuration: store.configuration)
        } label: {
            Label(failureMessage == nil ? "Start Ride" : "Retry Ride", systemImage: "bicycle")
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 82)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canStart)
        .accessibilityHint(
            canStart
                ? "Connects your saved equipment and opens the ride controls"
                : "Open Settings and validate the saved equipment before riding"
        )
    }

    private var canStart: Bool {
        store.configuration.canFinishSetup
            && kickr.selectedID?.uuidString == store.configuration.kickrUUID
            && (!store.configuration.usesClick
                || click.selectedID?.uuidString == store.configuration.clickUUID)
    }

    private var failureMessage: String? {
        if case let .failed(message) = coordinator.state { return message }
        return nil
    }
}

private struct EquipmentStatusRow: View {
    let title: String
    let name: String
    let state: ProductConnectionState
    let required: Bool

    var body: some View {
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
            Text(state.label)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(required ? "Required " : "")\(title), \(name), \(state.label)"
        )
    }
}

private struct ActiveRideView: View {
    let configuration: AppConfiguration
    @Bindable var kickr: KickrCentralService
    @Bindable var click: ClickCentralService
    @Bindable var coordinator: ProxyCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var confirmsStop = false
    @State private var lastInteraction = Date()
    @State private var isDimmed = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 8) {
                    rideHeader
                        .opacity(showsChrome ? 1 : 0.45)
                    connectionChips
                        .opacity(showsChrome ? 1 : 0)
                    shiftSurface(geometry, landscape: landscape)
                }
            }
            .safeAreaPadding(.horizontal, landscape ? 18 : 12)
            .safeAreaPadding(.vertical, 8)
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

    /// The whole area below the header is one shifting surface: the left half
    /// always shifts easier and the right half always shifts harder, so the
    /// rider never has to aim. The gear readout floats on top and passes taps
    /// through, which keeps the centre of the screen usable while riding.
    private func shiftSurface(
        _ geometry: GeometryProxy,
        landscape: Bool
    ) -> some View {
        ZStack {
            HStack(spacing: 10) {
                shiftPad(easier: true, landscape: landscape)
                shiftPad(easier: false, landscape: landscape)
            }
            .accessibilityElement(children: .contain)

            gearReadout(
                fontSize: landscape
                    ? min(geometry.size.width * 0.2, geometry.size.height * 0.34)
                    : min(geometry.size.width * 0.46, geometry.size.height * 0.26)
            )
            .frame(maxWidth: landscape ? geometry.size.width * 0.52 : .infinity)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var rideHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .font(.subheadline.weight(.bold))
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(statusColor.opacity(0.14), in: .capsule)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Button(role: .destructive) {
                confirmsStop = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "stop.fill")
                        .font(.subheadline.weight(.bold))
                    Text(coordinator.state == .stopping ? "Stopping" : "Stop")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Color.red, in: .capsule)
                .opacity(coordinator.state == .stopping ? 0.5 : 1)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.state == .stopping)
            .accessibilityLabel("Stop ride")
        }
        .accessibilityElement(children: .contain)
    }

    private var connectionChips: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(equipmentItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.22))
                            .frame(width: 1, height: 20)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: item.state.symbol)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(item.state.tint)
                        Text(item.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.title), \(item.detail)")
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))

            if let problem = equipmentItems.first(where: { $0.state != .ok }) {
                Text("\(problem.title) · \(problem.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
    }

    private var equipmentItems: [EquipmentItem] {
        var items: [EquipmentItem] = [
            EquipmentItem(
                id: "kickr",
                title: "KICKR",
                state: kickr.isReady
                    ? .ok : (kickr.state.isConnectionInProgress ? .pending : .warn),
                detail: kickr.state.label
            )
        ]
        let isSubscribed = coordinator.peripheral.activeCentralID != nil
        let isAdvertising = coordinator.peripheral.isAdvertising
        items.append(
            EquipmentItem(
                id: "realvelo",
                title: "Riding App",
                state: isSubscribed ? .ok : (isAdvertising ? .pending : .warn),
                detail: isSubscribed
                    ? "Connected"
                    : (isAdvertising ? "Waiting to be found" : "Not advertising")
            )
        )
        if configuration.usesClick {
            items.append(
                EquipmentItem(
                    id: "click",
                    title: "Click",
                    state: click.isReady
                        ? .ok : (click.state.isConnectionInProgress ? .pending : .warn),
                    detail: click.state.label
                )
            )
        }
        return items
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
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }

    private func shiftPad(easier: Bool, landscape: Bool) -> some View {
        ShiftPad(
            title: easier ? "Easier" : "Harder",
            symbol: easier ? "minus" : "plus",
            alignment: landscape
                ? (easier ? .bottomLeading : .bottomTrailing)
                : .bottom,
            hint: easier
                ? "Requests the next easier gear"
                : "Requests the next harder gear",
            disabled: easier ? !coordinator.canShiftEasier : !coordinator.canShiftHarder,
            quiet: !showsChrome
        ) {
            wake()
            coordinator.shift(easier ? .easier : .harder)
        }
    }

    /// True while the rider has asked for a gear the trainer has not confirmed.
    private var isShiftPending: Bool {
        guard let requested = coordinator.requestedGearIndex,
              let confirmed = coordinator.confirmedGearIndex else { return false }
        return requested != confirmed
    }

    private var primaryGearText: String {
        guard let gear = coordinator.displayedGear else { return "—" }
        if let virtualNumber = gear.virtualNumber {
            return "\(virtualNumber)"
        }
        return "\(gear.chainring)×\(gear.cog)"
    }

    private var secondaryGearText: String {
        guard let index = coordinator.confirmedGearIndex else {
            return coordinator.state == .active
                ? "Waiting for the trainer" : statusText
        }
        if isShiftPending { return "Shifting…" }
        let total = coordinator.gearSequence.count
        if coordinator.displayedGear?.virtualNumber != nil {
            return "of \(total)"
        }
        return "Gear \(index + 1) of \(total)"
    }

    private var gearAccessibilityLabel: String {
        guard let gear = coordinator.displayedGear,
              let index = coordinator.confirmedGearIndex else {
            return "Confirmed gear unavailable"
        }
        if let virtualNumber = gear.virtualNumber {
            return "Confirmed virtual gear \(virtualNumber) of "
                + "\(coordinator.gearSequence.count)"
        }
        return "Confirmed gear \(gear.chainring) tooth chainring by "
            + "\(gear.cog) tooth cog, position \(index + 1) of "
            + "\(coordinator.gearSequence.count)"
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

private struct ShiftPad: View {
    let title: String
    let symbol: String
    /// In landscape the label moves to the outer corner so the gear readout
    /// keeps the middle of the screen to itself.
    let alignment: Alignment
    let hint: String
    let disabled: Bool
    /// Ambient state: the pad recedes so the gear stays readable without
    /// covering the screen in a dark overlay.
    let quiet: Bool
    let action: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .black, design: .rounded))
                    .frame(height: symbolSize)
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.bottom, 26)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .contentShape(.rect)
        }
        .buttonStyle(
            ShiftPadStyle(disabled: disabled, outlined: differentiate, quiet: quiet)
        )
        .disabled(disabled)
        .accessibilityLabel("Shift \(title.lowercased())")
        .accessibilityHint(
            disabled ? "Unavailable at the drivetrain boundary" : hint
        )
    }
}

private struct ShiftPadStyle: ButtonStyle {
    let disabled: Bool
    let outlined: Bool
    let quiet: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        tint(
                            peak: fill(pressed: configuration.isPressed),
                            uniform: configuration.isPressed
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(tint(peak: border, uniform: false), lineWidth: outlined ? 3 : 2)
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.8), value: quiet)
    }

    /// The pad fades out towards the top so the gear readout sits on clean
    /// space, while the thumb end stays an obvious, solid target.
    private func tint(peak: Double, uniform: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(peak * (uniform ? 0.75 : 0.12)),
                Color.accentColor.opacity(peak)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func fill(pressed: Bool) -> Double {
        if disabled { return 0.05 }
        if pressed { return 0.34 }
        return quiet ? 0.06 : 0.18
    }

    private var border: Double {
        if disabled { return 0.12 }
        return quiet ? 0.16 : 0.45
    }

    private func foreground(pressed: Bool) -> Color {
        if disabled { return .secondary.opacity(0.45) }
        return .accentColor.opacity(quiet && !pressed ? 0.3 : 1)
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
