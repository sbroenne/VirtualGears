import SwiftUI
import UIKit

struct ClickProofView: View {
    @EnvironmentObject private var click: ClickBluetoothManager

    var body: some View {
        NavigationStack {
            List {
                Section("Independent Click test") {
                    Text(
                        "This screen connects only to the Zwift Click. "
                            + "It does not connect to or control the KICKR."
                    )
                    Text(
                        "Tap changes one gear. Hold for 500 ms to repeat "
                            + "every 300 ms, like Shimano Di2 multi-shift."
                    )
                    .foregroundStyle(.secondary)
                    Text("Press either Click button once to wake it before scanning.")
                        .foregroundStyle(.secondary)
                }

                Section("Status") {
                    LabeledContent("Bluetooth", value: click.bluetoothStatus)
                    LabeledContent("Connection", value: click.connectionStatus)
                    LabeledContent(
                        "Battery",
                        value: click.batteryLevel.map { "\($0)%" } ?? "Not available"
                    )
                    if let battery = click.batteryLevel, battery < 20 {
                        Text("Click battery is low")
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                    }
                }

                Section("Choose Click") {
                    Button(
                        click.isScanning ? "Stop scanning" : "Scan for Click"
                    ) {
                        if click.isScanning {
                            click.stopScanning()
                        } else {
                            click.startScanning()
                        }
                    }
                    .disabled(click.isConnected || click.isConnecting)

                    ForEach(click.candidates) { candidate in
                        Button {
                            click.connect(to: candidate.id)
                        } label: {
                            HStack {
                                Text(candidate.name)
                                Spacer()
                                Text("\(candidate.rssi) dBm")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(click.isConnected || click.isConnecting)
                    }

                    if click.isConnected {
                        Button("Disconnect Click", role: .destructive) {
                            click.disconnect()
                        }
                    }
                }

                Section("Virtual gear") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(click.gear)")
                            .font(
                                .system(
                                    size: 64,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                        Text("of \(click.gearRange.upperBound)")
                            .foregroundStyle(.secondary)
                    }
                    Text(click.lastShift)
                    Button("Reset display to gear 6") {
                        click.resetGear()
                    }
                }

                Section("Diagnostic log") {
                    if click.entries.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Text(click.diagnosticText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Button("Copy Click diagnostic log") {
                            UIPasteboard.general.string = click.diagnosticText
                        }
                    }
                }
            }
            .navigationTitle("Zwift Click Proof")
        }
    }
}
