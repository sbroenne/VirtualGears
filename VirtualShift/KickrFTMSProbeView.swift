import SwiftUI
import UIKit

struct KickrFTMSProbeView: View {
    @EnvironmentObject private var probe: KickrFTMSProbeManager
    @State private var preparedTrace: String?
    @State private var copyConfirmation: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Native FTMS connection") {
                    Text(
                        "Directly inspects the KICKR's FTMS service. "
                            + "This probe does not advertise anything to a riding app."
                    )
                    .foregroundStyle(.secondary)
                    LabeledContent("Bluetooth", value: probe.bluetoothState)
                    LabeledContent("Connection", value: probe.connectionState)
                    Button(probe.isScanning ? "Stop Scanning" : "Scan for KICKR") {
                        probe.isScanning ? probe.stopScanning() : probe.startScanning()
                    }
                    .disabled(probe.isConnected || probe.isConnecting)
                    ForEach(probe.candidates) { candidate in
                        Button {
                            probe.connect(to: candidate.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(candidate.name)
                                    Text(candidate.id.uuidString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(candidate.rssi) dBm")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(probe.isConnected || probe.isConnecting)
                    }
                    if probe.candidates.isEmpty {
                        Text("No KICKR devices found yet")
                            .foregroundStyle(.secondary)
                    }
                    if probe.isConnected || probe.isConnecting {
                        Button("Disconnect", role: .destructive) {
                            probe.disconnect()
                        }
                    }
                }

                Section("Safe FTMS control") {
                    Button("Request Control") {
                        probe.requestControl()
                    }
                    .disabled(
                        !probe.isReadyForControl || probe.hasControl || probe.isBusy
                    )
                    LabeledContent(
                        "Control",
                        value: probe.hasControl ? "Granted" : "Not granted"
                    )
                    if probe.hasControl {
                        Button("Start / Resume") {
                            probe.startOrResume()
                        }
                        .disabled(probe.isBusy)
                        Button("Stop", role: .destructive) {
                            probe.stop()
                        }
                        .disabled(probe.isBusy)
                    }
                    Text(
                        "Commands are serialized and require a matching FTMS "
                            + "Control Point response. No ERG, resistance, or "
                            + "simulation commands are exposed."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Discovered characteristics") {
                    if probe.characteristicRecords.isEmpty {
                        Text("Connect to inspect FTMS characteristics")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(probe.characteristicRecords) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.uuid)
                                .font(.system(.body, design: .monospaced))
                            Text(record.properties)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let decoded = record.decodedValue {
                                Text(decoded)
                            }
                            if let raw = record.rawHex {
                                Text(raw)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Section("Recent trace") {
                    if probe.recentEvents.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Text(
                                probe.recentEvents
                                    .map(\.displayText)
                                    .joined(separator: "\n")
                            )
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        }
                    }
                    Text(
                        "\(probe.eventCount) events retained; showing the latest 40."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Prepare JSON Export") {
                        preparedTrace = probe.structuredTrace()
                        copyConfirmation = nil
                    }
                    if let preparedTrace {
                        ShareLink(
                            item: preparedTrace,
                            subject: Text("KICKR Native FTMS Trace")
                        ) {
                            Label("Share Prepared Trace", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Copy JSON Trace") {
                        UIPasteboard.general.string = probe.structuredTrace()
                        copyConfirmation = "Copied \(probe.eventCount) events"
                    }
                    if let copyConfirmation {
                        Label(copyConfirmation, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Clear Trace", role: .destructive) {
                        probe.clearTrace()
                        preparedTrace = nil
                        copyConfirmation = nil
                    }
                }
            }
            .navigationTitle("KICKR Native FTMS")
        }
    }
}
