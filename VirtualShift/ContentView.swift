import SwiftUI
import UIKit
import VirtualShiftCore

struct ContentView: View {
    @EnvironmentObject private var bluetooth: KickrBluetoothManager
    @State private var baselineText = "2070"
    @State private var kickrModel = "KICKR V5"
    @State private var kickrFirmware = ""
    @State private var resistanceResult = "Not tested"

    var body: some View {
        NavigationStack {
            List {
                liveDataSection
                statusSection
                baselineSection
                trainerSection
                commandSection
                safetySection
                hardwareSection
                logSection
            }
            .navigationTitle("KICKR V5 Proof")
        }
    }

    private var liveDataSection: some View {
        Section("Live trainer data") {
            HStack {
                metric(
                    value: bluetooth.powerWatts.map(String.init) ?? "--",
                    unit: "watts"
                )
                Spacer()
                metric(
                    value: bluetooth.cadenceRPM.map {
                        String(format: "%.0f", $0)
                    } ?? "--",
                    unit: "rpm"
                )
            }
            Text(
                "Keep cadence steady, then compare watts after each "
                    + "circumference change."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func metric(value: String, unit: String) -> some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var baselineSection: some View {
        Section("Starting circumference") {
            TextField("Starting value in millimetres", text: $baselineText)
                .keyboardType(.decimalPad)
                .disabled(bluetooth.isConnected || bluetooth.isConnecting)
                .onChange(of: baselineText) {
                    bluetooth.clearBaselineConfirmation()
                }

            Button("Confirm starting value") {
                guard let value = Double(baselineText) else {
                    bluetooth.confirmBaseline(.nan)
                    return
                }
                bluetooth.confirmBaseline(value)
            }
            .disabled(bluetooth.isConnected || bluetooth.isConnecting)

            if let values = bluetooth.proofValues {
                Text(
                    "Confirmed: \(values.baseline.formatted()) mm. "
                        + "Tests: \(values.easier.formatted()) mm and "
                        + "\(values.harder.formatted()) mm."
                )
                .foregroundStyle(.green)
            } else {
                Text("Confirm this value before connecting to the trainer.")
                    .foregroundStyle(.secondary)
            }

            if let error = bluetooth.baselineError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Bluetooth", value: bluetooth.bluetoothStatus)
            LabeledContent("Connection", value: bluetooth.connectionStatus)
            LabeledContent(
                "Control properties",
                value: bluetooth.characteristicProperties
            )
            if let circumference = bluetooth.lastConfirmedCircumference {
                LabeledContent(
                    "Last confirmed",
                    value: "\(Int(circumference)) mm"
                )
            }
        }
    }

    private var trainerSection: some View {
        Section("Choose trainer") {
            Button(bluetooth.isScanning ? "Stop scanning" : "Scan for KICKR") {
                if bluetooth.isScanning {
                    bluetooth.stopScanning()
                } else {
                    bluetooth.startScanning()
                }
            }
            .disabled(bluetooth.isConnected || bluetooth.isConnecting)

            if bluetooth.trainers.isEmpty {
                Text("No KICKR trainers found yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bluetooth.trainers) { trainer in
                    Button {
                        bluetooth.connect(to: trainer.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(trainer.name)
                                Text(trainer.id.uuidString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(trainer.rssi) dBm")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(
                        bluetooth.isBusy
                            || bluetooth.isConnected
                            || bluetooth.isConnecting
                            || bluetooth.proofValues == nil
                    )
                }
            }
        }
    }

    private var commandSection: some View {
        Section("Wheel circumference") {
            Text(
                "The app unlocks the trainer and restores the confirmed "
                    + "starting value before "
                    + "these controls become available."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let values = bluetooth.proofValues {
                ForEach(WahooKickrProofSelection.allCases, id: \.self) {
                    selection in
                    Button(
                        "\(selection.label) - "
                            + "\(values[selection].formatted()) mm"
                    ) {
                        bluetooth.send(selection)
                    }
                    .disabled(!bluetooth.isReady || bluetooth.isBusy)
                }
            }

            Button(stopButtonTitle, role: .destructive) {
                bluetooth.stop()
            }
        }
    }

    @ViewBuilder
    private var safetySection: some View {
        if let warning = bluetooth.safetyWarning {
            Section("Safety warning") {
                Text(warning)
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            }
        }
    }

    private var hardwareSection: some View {
        Section("Hardware result") {
            TextField("KICKR model", text: $kickrModel)
            TextField("KICKR firmware", text: $kickrFirmware)
            LabeledContent(
                "iOS version",
                value: UIDevice.current.systemVersion
            )
            Picker("Resistance direction", selection: $resistanceResult) {
                Text("Not tested").tag("Not tested")
                Text("Confirmed").tag("Confirmed")
                Text("Wrong direction").tag("Wrong direction")
                Text("No physical change").tag("No physical change")
            }
            Button("Copy result summary") {
                UIPasteboard.general.string = resultSummary
            }
        }
    }

    private var logSection: some View {
        Section("Diagnostic log") {
            if bluetooth.entries.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    Text(bluetooth.diagnosticText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Copy diagnostic log") {
                    UIPasteboard.general.string = bluetooth.diagnosticText
                }
            }
        }
    }

    private var resultSummary: String {
        let proofValues = bluetooth.proofValues
        return """
        KICKR model: \(kickrModel)
        KICKR firmware: \(kickrFirmware.isEmpty ? "Not recorded" : kickrFirmware)
        iOS version: \(UIDevice.current.systemVersion)
        Starting circumference: \(proofValues?.baseline.formatted() ?? "Not confirmed") mm
        Easier test: \(proofValues?.easier.formatted() ?? "Not calculated") mm
        Harder test: \(proofValues?.harder.formatted() ?? "Not calculated") mm
        Control characteristic: \(WahooKickrProtocol.controlCharacteristicUUID)
        Properties: \(bluetooth.characteristicProperties)
        Resistance direction: \(resistanceResult)

        Diagnostic log:
        \(bluetooth.diagnosticText)
        """
    }

    private var stopButtonTitle: String {
        guard let baseline = bluetooth.proofValues?.baseline else {
            return "Stop"
        }
        return "Stop and restore \(baseline.formatted()) mm"
    }
}
