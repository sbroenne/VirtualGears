import SwiftUI
import UIKit

struct RealVeloProbeView: View {
    @EnvironmentObject private var probe: RealVeloProbeManager
    @State private var realVeloVersion = ""
    @State private var windowsVersion = ""
    @State private var copyConfirmation: String?
    @State private var preparedTrace: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Independent test") {
                    Text(
                        "This iPhone pretends to be an FTMS indoor bike. "
                            + "The KICKR is not used in this test."
                    )
                    .foregroundStyle(.secondary)
                    LabeledContent("Bluetooth", value: probe.bluetoothState)
                    LabeledContent(
                        "Advertising",
                        value: probe.isAdvertising ? "Active" : "Stopped"
                    )
                    LabeledContent(
                        "Subscriptions",
                        value: String(probe.subscriberCount)
                    )
                    LabeledContent(
                        "RealVelo control",
                        value: probe.hasControl ? "Granted" : "Not granted"
                    )
                    Button(probe.isAdvertising ? "Stop Probe" : "Start Probe") {
                        probe.isAdvertising ? probe.stop() : probe.start()
                    }
                }

                Section("Deterministic bike data") {
                    valueSlider(
                        "Speed",
                        value: $probe.speedKilometersPerHour,
                        range: 0...80,
                        step: 0.5,
                        suffix: "km/h"
                    )
                    valueSlider(
                        "Cadence",
                        value: $probe.cadenceRPM,
                        range: 0...150,
                        step: 1,
                        suffix: "rpm"
                    )
                    Stepper(
                        "Power: \(probe.powerWatts) W",
                        value: $probe.powerWatts,
                        in: 0...2_500,
                        step: 5
                    )
                }

                Section("Trace metadata") {
                    TextField("RealVelo version", text: $realVeloVersion)
                    TextField("Windows version", text: $windowsVersion)
                    LabeledContent(
                        "iOS version",
                        value: UIDevice.current.systemVersion
                    )
                }

                Section("Structured trace") {
                    if probe.recentEntries.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Text(
                                probe.recentEntries
                                    .map(\.displayText)
                                    .joined(separator: "\n")
                            )
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    Text(
                        "\(probe.traceEventCount) events captured; "
                            + "showing the latest 40."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Prepare JSON Export") {
                        preparedTrace = probe.structuredTrace(
                            realVeloVersion: realVeloVersion,
                            windowsVersion: windowsVersion
                        )
                        copyConfirmation = nil
                    }
                    if let preparedTrace {
                        ShareLink(
                            item: preparedTrace,
                            subject: Text("VirtualShift RealVelo FTMS Trace")
                        ) {
                            Label(
                                "Share Prepared Trace",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }
                    Button("Copy JSON Trace") {
                        UIPasteboard.general.string = probe.structuredTrace(
                            realVeloVersion: realVeloVersion,
                            windowsVersion: windowsVersion
                        )
                        copyConfirmation =
                            "Copied \(probe.traceEventCount) trace events"
                    }
                    if let copyConfirmation {
                        Label(copyConfirmation, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Clear Trace", role: .destructive) {
                        probe.clearTrace()
                        copyConfirmation = nil
                        preparedTrace = nil
                    }
                }
            }
            .navigationTitle("RealVelo FTMS Probe")
        }
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(value.wrappedValue.formatted()) \(suffix)")
            Slider(value: value, in: range, step: step)
        }
    }
}
