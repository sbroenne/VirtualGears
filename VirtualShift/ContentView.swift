import SwiftUI
import UIKit
import VirtualShiftCore

struct ContentView: View {
    @EnvironmentObject private var bluetooth: KickrBluetoothManager

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                safetySection
                connectionSection
                rangeTestSection
                reportSection
            }
            .navigationTitle("KICKR Range Test")
            .listStyle(.insetGrouped)
        }
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Validate a KICKR V5 safely")
                    .font(.title2.bold())
                Text(
                    "Connect the trainer, then run each staged check without pedalling. "
                        + "Every check automatically returns the trainer to 2070 mm."
                )
                .foregroundStyle(.secondary)
                Label(currentStep, systemImage: currentStepSymbol)
                    .font(.headline)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var safetySection: some View {
        if let warning = bluetooth.safetyWarning {
            Section("Safety warning") {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            }
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Bluetooth", value: bluetooth.bluetoothStatus)
            LabeledContent("Trainer", value: bluetooth.connectionStatus)

            if bluetooth.isConnected || bluetooth.isConnecting {
                Button("Stop and restore 2070 mm", role: .destructive) {
                    bluetooth.stop()
                }
            } else {
                Button {
                    bluetooth.isScanning
                        ? bluetooth.stopScanning()
                        : bluetooth.startScanning()
                } label: {
                    Label(
                        bluetooth.isScanning ? "Stop scanning" : "Find my KICKR",
                        systemImage: bluetooth.isScanning
                            ? "stop.circle" : "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)

                if bluetooth.trainers.isEmpty {
                    Text(
                        bluetooth.isScanning
                            ? "Keep the KICKR awake and nearby."
                            : "Tap Find my KICKR to begin."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(bluetooth.trainers) { trainer in
                        Button {
                            bluetooth.connect(to: trainer.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(trainer.name)
                                        .font(.headline)
                                    Text("Signal \(trainer.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 52)
                        }
                    }
                }
            }
        } header: {
            Text("1. Connect")
        } footer: {
            Text(
                "The app unlocks the KICKR and confirms 2070 mm before enabling "
                    + "the test."
            )
        }
    }

    private var rangeTestSection: some View {
        Section {
            ProgressView(
                value: Double(bluetooth.confirmedRangeProbeValues.count),
                total: Double(KickrBluetoothManager.rangeProbeValues.count)
            )
            .tint(testComplete ? .green : .accentColor)

            HStack {
                Text("Progress")
                Spacer()
                Text(
                    "\(bluetooth.confirmedRangeProbeValues.count) of "
                        + "\(KickrBluetoothManager.rangeProbeValues.count)"
                )
                .monospacedDigit()
                .fontWeight(.semibold)
            }

            if testComplete {
                Label(
                    "Complete range confirmed",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)

                Button("Run the test again") {
                    bluetooth.resetRangeTest()
                }
                .disabled(!bluetooth.isReady || bluetooth.isBusy)
            } else if let next = bluetooth.nextRangeProbeValue {
                Button {
                    bluetooth.sendNextRangeProbe()
                } label: {
                    VStack(spacing: 4) {
                        Text(
                            bluetooth.isBusy
                                ? "Checking and restoring…"
                                : "Run next check"
                        )
                        Text(
                            "\(next.formatted()) mm · then restore 2070 mm"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!bluetooth.isReady || bluetooth.isBusy)
            }

            Text("Do not pedal during these command-acceptance checks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("2. Validate")
        }
    }

    private var reportSection: some View {
        Section {
            LabeledContent("Model", value: "KICKR V5")
            LabeledContent(
                "Validated range",
                value: testComplete ? "646.9–4800 mm" : "Not complete"
            )
            LabeledContent(
                "Last confirmed",
                value: bluetooth.lastConfirmedCircumference.map {
                    "\($0.formatted()) mm"
                } ?? "None"
            )

            Button {
                UIPasteboard.general.string = resultSummary
            } label: {
                Label(
                    "Copy test report",
                    systemImage: "doc.on.doc"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(bluetooth.entries.isEmpty)

            DisclosureGroup("Technical details") {
                LabeledContent(
                    "Control properties",
                    value: bluetooth.characteristicProperties
                )
                Text(bluetooth.diagnosticText.isEmpty
                    ? "No diagnostic events yet."
                    : bluetooth.diagnosticText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        } header: {
            Text("3. Report")
        }
    }

    private var testComplete: Bool {
        bluetooth.confirmedRangeProbeValues.count
            == KickrBluetoothManager.rangeProbeValues.count
    }

    private var currentStep: String {
        if testComplete {
            return "Validation complete"
        }
        if bluetooth.isReady {
            return "Run check \(bluetooth.confirmedRangeProbeValues.count + 1)"
        }
        if bluetooth.isConnected || bluetooth.isConnecting {
            return "Preparing trainer"
        }
        return "Connect your trainer"
    }

    private var currentStepSymbol: String {
        if testComplete {
            return "checkmark.circle.fill"
        }
        if bluetooth.isReady {
            return "play.circle.fill"
        }
        return "1.circle.fill"
    }

    private var resultSummary: String {
        """
        KICKR range validation
        Model: KICKR V5
        iOS version: \(UIDevice.current.systemVersion)
        Neutral circumference: \(KickrBluetoothManager.neutralCircumference.formatted()) mm
        Control characteristic: \(WahooKickrProtocol.controlCharacteristicUUID)
        Properties: \(bluetooth.characteristicProperties)
        Result: \(testComplete ? "PASS" : "INCOMPLETE")
        Confirmed values: \(bluetooth.confirmedRangeProbeValues.map { $0.formatted() }.joined(separator: ", ")) mm

        Diagnostic log:
        \(bluetooth.diagnosticText)
        """
    }
}
