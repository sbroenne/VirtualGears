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
                if landscape {
                    landscapeContent(geometry)
                } else {
                    portraitContent(geometry)
                }
                if isDimmed {
                    Color.black
                        .opacity(reduceTransparency ? 0.62 : 0.48)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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

    private func portraitContent(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            rideHeader
            connectionChips
            gearDisplay(
                fontSize: min(geometry.size.width * 0.46, geometry.size.height * 0.24)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            shiftControls
                .frame(height: max(190, geometry.size.height * 0.36))
        }
    }

    private func landscapeContent(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            rideHeader
            HStack(spacing: 12) {
                shiftPad(easier: true)
                    .frame(width: max(130, geometry.size.width * 0.26))
                VStack(spacing: 8) {
                    connectionChips
                    gearDisplay(
                        fontSize: min(geometry.size.width * 0.22, geometry.size.height * 0.38)
                    )
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                shiftPad(easier: false)
                    .frame(width: max(130, geometry.size.width * 0.26))
            }
            .frame(maxHeight: .infinity)
        }
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

    private func gearDisplay(fontSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            Text(primaryGearText)
                .font(.system(
                    size: max(44, fontSize),
                    weight: .black,
                    design: .rounded
                ).monospacedDigit())
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(coordinator.state == .active ? Color.primary : Color.secondary)
                .accessibilityLabel(gearAccessibilityLabel)
            Text(secondaryGearText)
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            GearPositionRail(
                gears: coordinator.gearSequence,
                selectedIndex: coordinator.confirmedGearIndex
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var shiftControls: some View {
        HStack(spacing: 12) {
            shiftPad(easier: true)
            shiftPad(easier: false)
        }
        .accessibilityElement(children: .contain)
    }

    private func shiftPad(easier: Bool) -> some View {
        ShiftPad(
            title: easier ? "Easier" : "Harder",
            symbol: easier ? "minus" : "plus",
            hint: easier
                ? "Requests the next easier gear"
                : "Requests the next harder gear",
            disabled: easier ? !coordinator.canShiftEasier : !coordinator.canShiftHarder
        ) {
            wake()
            coordinator.shift(easier ? .easier : .harder)
        }
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
        return "Gear \(index + 1) of \(coordinator.gearSequence.count)"
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
    let hint: String
    let disabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .black, design: .rounded))
                    .frame(height: symbolSize)
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(ShiftPadStyle(disabled: disabled, outlined: differentiate))
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(disabled ? Color.secondary : Color.white)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        disabled
                            ? AnyShapeStyle(Color.secondary.opacity(0.18))
                            : AnyShapeStyle(Color.accentColor)
                    )
            }
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(disabled ? Color.secondary : Color.primary, lineWidth: 2)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GearPositionRail: View {
    let gears: [VirtualGear]
    let selectedIndex: Int?
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
                        .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: width, height: index == selectedIndex ? 22 : 10)
                        .overlay {
                            if differentiate && index == selectedIndex {
                                Capsule().stroke(Color.primary, lineWidth: 2)
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
