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
                    diagnostics: diagnostics
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
                        isEditing: true
                    ) {
                        showsSettings = false
                    }
                }
            }
            .task {
                kickr.resumeSavedConnection()
                if store.configuration.usesClick {
                    click.resumeSavedConnection()
                }
            }
        }
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready when you are")
                .font(.largeTitle.bold())
            Text("Equipment is saved and your neutral circumference is confirmed.")
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
                Spacer()
                Text("\(store.configuration.neutralCircumferenceMillimeters) mm")
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(store.configuration.drivetrainPreset.detail) drivetrain, "
                    + "\(store.configuration.neutralCircumferenceMillimeters) "
                    + "millimeter neutral circumference, confirmed"
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
            Task {
                await coordinator.startRide(configuration: store.configuration)
            }
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
    @ScaledMetric(relativeTo: .largeTitle) private var gearFontSize: CGFloat = 86
    @State private var confirmsStop = false
    @State private var lastInteraction = Date()
    @State private var isDimmed = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                if landscape {
                    landscapeContent
                } else {
                    portraitContent
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
                    + "restore its neutral circumference, and disconnect."
            )
        }
    }

    private var portraitContent: some View {
        VStack(spacing: 12) {
            rideHeader
            connectionChips
            Spacer(minLength: 0)
            gearPanel
            Spacer(minLength: 0)
            if showsTouchControls { shiftControls }
        }
    }

    private var landscapeContent: some View {
        VStack(spacing: 8) {
            rideHeader
            HStack(spacing: 18) {
                VStack(spacing: 10) {
                    connectionChips
                    gearPanel
                }
                .frame(maxWidth: .infinity)
                if showsTouchControls {
                    shiftControls
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var rideHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VirtualShift")
                    .font(.headline)
                Label(statusText, systemImage: statusSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Button(role: .destructive) {
                confirmsStop = true
            } label: {
                Label(
                    coordinator.state == .stopping ? "Stopping…" : "Stop",
                    systemImage: "stop.circle.fill"
                )
                .frame(minWidth: 76, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.state == .stopping)
        }
        .accessibilityElement(children: .contain)
    }

    private var connectionChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chips: some View {
        ConnectionChip(
            title: "KICKR",
            status: kickr.state.label,
            connected: kickr.isReady
        )
        ConnectionChip(
            title: "RealVelo",
            status: coordinator.peripheral.activeCentralID == nil
                ? (coordinator.peripheral.isAdvertising ? "Advertising" : "Not advertising")
                : "Subscribed",
            connected: coordinator.peripheral.activeCentralID != nil
        )
        ConnectionChip(
            title: "Click",
            status: configuration.usesClick ? click.state.label : "On-screen controls",
            connected: configuration.usesClick && click.isReady
        )
    }

    private var gearPanel: some View {
        VStack(spacing: 12) {
            Text(gearText)
                .font(.system(
                    size: gearFontSize,
                    weight: .heavy,
                    design: .rounded
                ).monospacedDigit())
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .accessibilityLabel(gearAccessibilityLabel)
            if configuration.drivetrainPreset.drivetrain.usesNumberedGears {
                NumberedDrivetrainGraphic(
                    gearNumber: coordinator.displayedGear?.virtualNumber,
                    gearCount: coordinator.gearSequence.count
                )
            } else {
                DrivetrainGraphic(
                    chainrings: configuration.drivetrainPreset.drivetrain.chainrings,
                    cassette: configuration.drivetrainPreset.drivetrain.cassetteCogs,
                    gear: coordinator.displayedGear
                )
            }
            GearPositionRail(
                gears: coordinator.gearSequence,
                selectedIndex: coordinator.confirmedGearIndex
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 26))
    }

    private var shiftControls: some View {
        HStack(spacing: 14) {
            ShiftButton(
                title: "Easier",
                symbol: "minus",
                accessibilityHint: "Requests the next easier gear",
                disabled: !coordinator.canShiftEasier
            ) {
                wake()
                coordinator.shift(.easier)
            }
            ShiftButton(
                title: "Harder",
                symbol: "plus",
                accessibilityHint: "Requests the next harder gear",
                disabled: !coordinator.canShiftHarder
            ) {
                wake()
                coordinator.shift(.harder)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var showsTouchControls: Bool {
        !configuration.usesClick || !click.isReady
    }

    private var gearText: String {
        guard let gear = coordinator.displayedGear else {
            return configuration.drivetrainPreset.drivetrain.usesNumberedGears
                ? "Gear —" : "— × —"
        }
        if let virtualNumber = gear.virtualNumber {
            return "Gear \(virtualNumber)"
        }
        return "\(gear.chainring) × \(gear.cog)"
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

private struct ConnectionChip: View {
    let title: String
    let status: String
    let connected: Bool
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        Label {
            Text("\(title) · \(status)")
                .lineLimit(1)
        } icon: {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dotted")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            connected ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12),
            in: .capsule
        )
        .overlay {
            if differentiate {
                Capsule().stroke(connected ? Color.primary : Color.secondary)
            }
        }
        .accessibilityLabel("\(title), \(status)")
    }
}

private struct ShiftButton: View {
    let title: String
    let symbol: String
    let accessibilityHint: String
    let disabled: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 60

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .bold, design: .rounded))
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .contentShape(.rect)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
        .accessibilityLabel("Shift \(title.lowercased())")
        .accessibilityHint(
            disabled ? "Unavailable at the drivetrain boundary" : accessibilityHint
        )
    }
}

private struct GearPositionRail: View {
    let gears: [VirtualGear]
    let selectedIndex: Int?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let width = max(
                3,
                (proxy.size.width - spacing * CGFloat(max(0, gears.count - 1)))
                    / CGFloat(max(1, gears.count))
            )
            HStack(spacing: spacing) {
                ForEach(Array(gears.indices), id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: width, height: index == selectedIndex ? 12 : 6)
                        .overlay {
                            if differentiate && index == selectedIndex {
                                Capsule().stroke(Color.primary, lineWidth: 2)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(
            selectedIndex.map {
                "Gear position \($0 + 1) of \(gears.count)"
            } ?? "Gear position unavailable"
        )
    }
}

private struct DrivetrainGraphic: View {
    let chainrings: [Int]
    let cassette: [Int]
    let gear: VirtualGear?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(Array(chainrings.enumerated()), id: \.offset) { index, teeth in
                    Circle()
                        .stroke(
                            gear?.chainring == teeth ? Color.accentColor : Color.secondary,
                            lineWidth: gear?.chainring == teeth ? 5 : 2
                        )
                        .frame(
                            width: CGFloat(48 - index * 12),
                            height: CGFloat(48 - index * 12)
                        )
                }
            }
            Rectangle()
                .fill(Color.secondary.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(cassette.enumerated()), id: \.offset) { _, teeth in
                    Capsule()
                        .fill(gear?.cog == teeth ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(
                            width: gear?.cog == teeth ? 5 : 3,
                            height: CGFloat(12 + teeth / 2)
                        )
                }
            }
        }
        .frame(height: 50)
        .accessibilityHidden(true)
    }
}

private struct NumberedDrivetrainGraphic: View {
    let gearNumber: Int?
    let gearCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("1")
                .font(.caption.monospacedDigit().weight(.semibold))
            Rectangle()
                .fill(Color.secondary.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Rectangle()
                .fill(Color.secondary.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            Text("\(gearCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(height: 50)
        .accessibilityHidden(true)
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
